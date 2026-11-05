"""Meeting audio capture (plan 1.6, spike S3; architecture §9.2, §9.6).

Each test builds its own silent PipeWire fixture: a virtual speaker the fake meeting app plays into
(so nothing reaches the real speakers) and a virtual microphone fed through a loopback. The meeting
app plays 440 Hz and the microphone carries 880 Hz; each capture must hold only its own tone.
Skipped when no PipeWire daemon answers; CI starts one, so they run there.
"""
import math;
import os;
import struct;
import subprocess;
import tempfile;
import time;
import uuid;
import wave;
import core.audio.capture as capture;

glob TONE_SECONDS: float = 4.0;

def pipewire_running -> bool {
    try {
        return subprocess.run(
            ["pw-cli", "info", "0"], capture_output=True, timeout=10
        ).returncode
            == 0;
    } except (OSError, subprocess.TimeoutExpired) {
        return False;
    }
}

def write_tone(path: str, frequency: float, seconds: float) {
    rate = 48000;
    frames = bytearray();
    for i in range(int(rate * seconds)) {
        frames.extend(
            struct.pack("<h", int(12000 * math.sin(2 * math.pi * frequency * i / rate)))
        );
    }
    with wave.open(path, "wb") as out {
        out.setnchannels(1);
        out.setsampwidth(2);
        out.setframerate(rate);
        out.writeframes(bytes(frames));
    }
}

"""The power of one frequency in 16-bit mono PCM (Goertzel)."""
def tone_power(pcm: bytes, frequency: float) -> float {
    count = len(pcm) // 2;
    if count == 0 {
        return 0.0;
    }
    samples = struct.unpack(f"<{count}h", pcm[:count * 2]);
    k = 2 * math.cos(2 * math.pi * frequency / capture.SAMPLE_RATE);
    s1 = 0.0;
    s2 = 0.0;
    for v in samples {
        s0 = v + k * s1 - s2;
        s2 = s1;
        s1 = s0;
    }
    return (s1 * s1 + s2 * s2 - k * s1 * s2) / (count * count);
}

obj Fixture {
    has tag: str,
        folder: str,
        processes: list[subprocess.Popen[bytes]] = [];

    def speaker -> str {
        return f"briefly-test-{self.tag}-speaker";
    }

    def mic -> str {
        return f"briefly-test-{self.tag}-mic";
    }

    def app -> str {
        return f"FakeMeet-{self.tag}";
    }

    def launch(args: list[str]) -> subprocess.Popen[bytes] {
        process = subprocess.Popen(
            args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        );
        self.processes.append(process);
        return process;
    }

    """The virtual speaker and microphone; returns once PipeWire lists both."""
    def open {
        self.launch(
            [
                "pw-loopback",
                f"--capture-props=node.name={self.speaker()} media.class=Audio/Sink",
                f"--playback-props=node.name={self.speaker()}-out node.passive=true node.autoconnect=false"
            ]
        );
        self.launch(
            [
                "pw-loopback",
                f"--capture-props=node.name={self.mic()}-in media.class=Audio/Sink",
                f"--playback-props=node.name={self.mic()} media.class=Audio/Source"
            ]
        );
        deadline = time.monotonic() + 10;
        while time.monotonic() < deadline {
            if self.mic_source() is not None {
                return;
            }
            time.sleep(0.2);
        }
        raise RuntimeError("the virtual microphone did not appear");
    }

    """Play the two tones: 440 Hz from the fake meeting app, 880 Hz into the microphone."""
    def play {
        meeting = os.path.join(self.folder, "meeting.wav");
        voice = os.path.join(self.folder, "voice.wav");
        write_tone(meeting, 440, TONE_SECONDS);
        write_tone(voice, 880, TONE_SECONDS);
        self.launch(
            [
                "pw-play",
                "--target",
                self.speaker(),
                f"--properties={{ application.name=\"{self.app()}\" media.name=\"standup call\" }}",
                meeting
            ]
        );
        self.launch(["pw-play", "--target", f"{self.mic()}-in", voice]);
    }

    def app_source -> capture.AudioSource | None {
        for source in capture.list_sources() {
            if source.kind == "app" and source.name == self.app() {
                return source;
            }
        }
        return None;
    }

    def mic_source -> capture.AudioSource | None {
        for source in capture.list_sources() {
            if source.kind == "mic" and source.detail == self.mic() {
                return source;
            }
        }
        return None;
    }

    def wait_for_app -> capture.AudioSource {
        deadline = time.monotonic() + 10;
        while time.monotonic() < deadline {
            found = self.app_source();
            if found is not None {
                return found;
            }
            time.sleep(0.1);
        }
        raise RuntimeError("the fake meeting app's stream did not appear");
    }

    def close {
        for process in reversed(self.processes) {
            process.terminate();
            try {
                process.wait(timeout=5);
            } except subprocess.TimeoutExpired {
                process.kill();
            }
        }
    }
}

def fixture(folder: str) -> Fixture {
    if not pipewire_running() {
        testskip("no PipeWire daemon answers");
    }
    made = Fixture(tag=uuid.uuid4().hex[:8], folder=folder);
    made.open();
    return made;
}

test "the default microphone's name is read from pw-metadata's output" {
    line = "update: id:0 key:'default.audio.source' value:'{\"name\":\"alsa_input.pci-0000_00_0e.0.analog-stereo\"}' type:'Spa:String:JSON'";
    out = "Found \"default\" metadata 41\n" + line + "\n";
    assert capture.default_source_name(out)
        == "alsa_input.pci-0000_00_0e.0.analog-stereo";
    assert capture.default_source_name("Found \"default\" metadata 41\n") == "";
}

test "when the session reports a default source, it is the one found (read-only)" {
    if not pipewire_running() {
        testskip("no PipeWire daemon answers");
    }
    reported = capture.default_source_name(
        subprocess.run(
            ["pw-metadata", "0", "default.audio.source"],
            capture_output=True,
            text=True,
            timeout=10
        ).stdout
    );
    if not reported {
        testskip("this session reports no default source");
    }
    mic = capture.default_microphone();
    assert mic is not None and mic.detail == reported , f"{reported!r} -> {mic}";
}

test "the ring buffer keeps only the most recent audio" {
    ring = capture.RingBuffer(seconds=1);
    ring.append(b"\x01\x00" * capture.SAMPLE_RATE);
    ring.append(b"\x02\x00" * (capture.SAMPLE_RATE // 2));
    kept = ring.snapshot();
    assert len(kept) == capture.BYTES_PER_SECOND , len(kept);
    assert kept[-2:] == b"\x02\x00" and kept[:2] == b"\x01\x00";
    assert ring.total_bytes == capture.BYTES_PER_SECOND * 3 // 2;
}

test "the sources list a playing meeting app's stream and the microphone" {
    with tempfile.TemporaryDirectory() as folder {
        f = fixture(folder);
        try {
            f.play();
            app = f.wait_for_app();
            assert app.kind == "app" and app.detail == "standup call" , app;
            mic = f.mic_source();
            assert mic is not None and mic.kind == "mic";
            kinds = [s.kind for s in capture.list_sources()];
            assert kinds.index("app") < kinds.index("mic") , "apps are listed before microphones";
        } finally {
            f.close();
        }
    }
}

test "the meeting stream and the microphone are captured separately" {
    with tempfile.TemporaryDirectory() as folder {
        f = fixture(folder);
        try {
            f.play();
            app = f.wait_for_app();
            mic = f.mic_source();
            assert mic is not None;
            others = capture.Capture(source=app, tag="others");
            me = capture.Capture(source=mic, tag="me");
            heard: dict[str, int] = {"others": 0, "me": 0};
            def count(tag: str, chunk: bytes) {
                heard[tag] = heard[tag] + len(chunk);
            }
            others.listeners.append(count);
            me.listeners.append(count);
            others.start();
            me.start();
            time.sleep(2.0);
            others.stop();
            me.stop();
            assert others.seconds_captured() > 1.0 and me.seconds_captured() > 1.0 , f"{others.seconds_captured()} {me.seconds_captured()}";
            assert heard["others"] == others.ring.total_bytes
                and heard["me"] == me.ring.total_bytes;
            o = others.ring.snapshot();
            m = me.ring.snapshot();
            assert tone_power(o, 440) > 1000 * max(tone_power(o, 880), 1.0) , "others must hold only the meeting app";
            assert tone_power(m, 880) > 1000 * max(tone_power(m, 440), 1.0) , "me must hold only the microphone";
            assert 0 <= others.first_audio_after < 1.5 , others.first_audio_after;
        } finally {
            f.close();
        }
    }
}

test "stopping a capture ends its process" {
    with tempfile.TemporaryDirectory() as folder {
        f = fixture(folder);
        try {
            mic = f.mic_source();
            assert mic is not None;
            me = capture.Capture(source=mic, tag="me");
            me.start();
            time.sleep(0.5);
            process = me._process;
            me.stop();
            assert process is not None and process.poll() is not None;
            assert me._process is None;
        } finally {
            f.close();
        }
    }
}
