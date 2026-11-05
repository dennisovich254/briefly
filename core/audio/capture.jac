"""Meeting audio capture through PipeWire (architecture §9.1, §9.2, §9.6; plan 1.6, spike S3).

Two sources, captured as separate streams: the meeting application's playback stream ("others")
and the microphone ("me"). The source is the speaker tag (§9.2), so they must never mix. Each source
is captured by its own `pw-record` process targeting that one PipeWire node, as 16 kHz mono signed
16-bit PCM on standard output, read live into a bounded ring buffer (about 30 s, §9.7); nothing is
written to disk. Listeners receive each chunk as it arrives, which is how speech-to-text is fed.

Audio capture is an OS boundary Jac does not claim to cover (§6.3): this module drives PipeWire's
own tools, which every Ubuntu desktop with PipeWire ships (`pw-dump`, `pw-record`).
"""
import json;
import os;
import subprocess;
import threading;
import time;

glob SAMPLE_RATE: int = 16000,
     BYTES_PER_SECOND: int = 32000,
     RING_SECONDS: int = 30,
     CHUNK_BYTES: int = 3200;  # 100 ms

obj AudioSource {
    has serial: str,
        kind: str,  # "app": an application's playback stream; "mic": a capture device
        name: str,
        detail: str = "";
}

"""PipeWire's objects (`pw-dump`); an empty list when PipeWire does not answer."""
def pipewire_objects -> list[dict[str, object]] {
    try {
        done = subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=10);
    } except (OSError, subprocess.TimeoutExpired) {
        return [];
    }
    if done.returncode != 0 or not done.stdout.strip() {
        return [];
    }
    found = json.loads(done.stdout);
    return found if isinstance(found, list) else [];
}

def props_of(item: dict[str, object]) -> dict[str, object] {
    info = item.get("info");
    if not isinstance(info, dict) {
        return {};
    }
    props = info.get("props");
    return props if isinstance(props, dict) else {};
}

"""The sources a meeting can be captured from: application playback streams, then microphones."""
def list_sources -> list[AudioSource] {
    apps: list[AudioSource] = [];
    mics: list[AudioSource] = [];
    for item in pipewire_objects() {
        if item.get("type") != "PipeWire:Interface:Node" {
            continue;
        }
        props = props_of(item);
        media_class = str(props.get("media.class", ""));
        serial = str(props.get("object.serial", ""));
        if not serial {
            continue;
        }
        if media_class == "Stream/Output/Audio" {
            apps.append(
                AudioSource(
                    serial=serial,
                    kind="app",
                    name=str(
                        props.get("application.name", "") or props.get("node.name", "")
                    ),
                    detail=str(props.get("media.name", ""))
                )
            );
        } elif media_class in ("Audio/Source", "Audio/Source/Virtual") {
            mics.append(
                AudioSource(
                    serial=serial,
                    kind="mic",
                    name=str(
                        props.get("node.description", "") or props.get("node.name", "")
                    ),
                    detail=str(props.get("node.name", ""))
                )
            );
        }
    }
    return apps + mics;
}

"""The node name in a `pw-metadata 0 default.audio.source` line, or "" when there is none.

The line reads `update: id:0 key:'default.audio.source' value:'{"name":"<node>"}' type:'…'`.
"""
def default_source_name(output: str) -> str {
    for line in output.splitlines() {
        if "value:'" not in line {
            continue;
        }
        value = line.split("value:'", 1)[1].split("'", 1)[0];
        try {
            parsed = json.loads(value);
        } except ValueError {
            continue;
        }
        if isinstance(parsed, dict) and parsed.get("name") {
            return str(parsed["name"]);
        }
    }
    return "";
}

"""The default microphone, as PipeWire's session manager has chosen it; None when there is none."""
def default_microphone -> AudioSource | None {
    try {
        done = subprocess.run(
            ["pw-metadata", "0", "default.audio.source"],
            capture_output=True,
            text=True,
            timeout=10
        );
    } except (OSError, subprocess.TimeoutExpired) {
        return None;
    }
    name = default_source_name(done.stdout);
    for source in list_sources() {
        if source.kind == "mic" and source.detail == name {
            return source;
        }
    }
    return None;
}

"""The most recent audio, bounded to `seconds` (§9.7: about 30 s in memory, nothing on disk)."""
obj RingBuffer {
    has seconds: int = RING_SECONDS,
        _data: bytearray = bytearray(),
        _lock: threading.Lock = threading.Lock(),
        total_bytes: int = 0;

    def append(chunk: bytes) {
        limit = self.seconds * BYTES_PER_SECOND;
        with self._lock {
            self._data.extend(chunk);
            self.total_bytes = self.total_bytes + len(chunk);
            if len(self._data) > limit {
                del self._data[:len(self._data) - limit];
            }
        }
    }

    def snapshot -> bytes {
        with self._lock {
            return bytes(self._data);
        }
    }
}

"""One source captured on its own; `tag` is the speaker label (§9.2): "others" or "me"."""
obj Capture {
    has source: AudioSource,
        tag: str,
        ring: RingBuffer = RingBuffer(),
        listeners: list[Callable[[str, bytes], None]] = [],
        started_at: float = 0.0,
        first_audio_after: float = -1.0,
        _process: subprocess.Popen[bytes] | None = None,
        _reader: threading.Thread | None = None;

    def start {
        self._process = subprocess.Popen(
            [
                "pw-record",
                "--target",
                self.source.serial,
                "--rate",
                str(SAMPLE_RATE),
                "--channels",
                "1",
                "--format",
                "s16",
                "--media-category",
                "Capture",
                "--properties",
                "{ application.name=\"Briefly\" media.name=\"Briefly capture ("
                    + self.tag
                    + ")\" }",
                "--raw",
                "-"
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL
        );
        self.started_at = time.monotonic();
        self._reader = threading.Thread(target=self._read, daemon=True);
        self._reader.start();
    }

    def _read {
        process = self._process;
        if process is None or process.stdout is None {
            return;
        }
        while True {
            chunk = os.read(process.stdout.fileno(), CHUNK_BYTES);
            if not chunk {
                return;
            }
            if self.first_audio_after < 0 {
                self.first_audio_after = time.monotonic() - self.started_at;
            }
            self.ring.append(chunk);
            for listener in list(self.listeners) {
                listener(self.tag, chunk);
            }
        }
    }

    """Stop capturing; returns once the capture process has exited."""
    def stop {
        if self._process is not None {
            self._process.terminate();
            try {
                self._process.wait(timeout=5);
            } except subprocess.TimeoutExpired {
                self._process.kill();
                self._process.wait(timeout=5);
            }
            self._process = None;
        }
        if self._reader is not None {
            self._reader.join(timeout=5);
            self._reader = None;
        }
    }

    def seconds_captured -> float {
        return self.ring.total_bytes / BYTES_PER_SECOND;
    }
}
