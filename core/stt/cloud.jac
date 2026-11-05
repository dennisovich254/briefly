"""Cloud streaming speech-to-text: Deepgram and AssemblyAI (architecture §9.3; plan 1.6, spike S3).

Each engine opens one WebSocket per source for the session (§9.7: never outside one), sends the
source's PCM as binary frames of 100 ms, and turns the service's results into utterances. Both
take the brief's vocabulary. Protocols as documented on 2026-11-05:

- Deepgram `wss://api.deepgram.com/v1/listen`, header `Authorization: Token <key>`; Nova-3, one
  `keyterm` parameter per term (500 tokens in all); `Results` messages carry
  `channel.alternatives[0].transcript`, `is_final`, `start` and `duration`; `CloseStream` ends the
  stream. `mip_opt_out=true` keeps the audio out of Deepgram's model-improvement program.
- AssemblyAI `wss://streaming.assemblyai.com/v3/ws`, header `Authorization: <key>`; Universal
  Streaming English, `keyterms_prompt` as a JSON list (100 terms of up to 50 characters); `Turn`
  messages carry `transcript`, `end_of_turn`, `turn_is_formatted` and word times in ms; `Terminate`
  ends the session (it is billed until closed). Free accounts cannot opt out of training.

The keys are read from `DEEPGRAM_API_KEY` and `ASSEMBLYAI_API_KEY` (or `.env` in development) and
never logged. `url` can point an engine at a local fake service (tests/stt/).
"""
import json;
import os;
import threading;
import urllib.parse;
import from websockets.sync.client { ClientConnection, connect }
import from websockets.exceptions { ConnectionClosed }
import from core.stt.transcript { Transcript }

glob DEEPGRAM_URL: str = "wss://api.deepgram.com/v1/listen",
     ASSEMBLYAI_URL: str = "wss://streaming.assemblyai.com/v3/ws",
     MAX_ASSEMBLYAI_TERMS: int = 100,
     MAX_ASSEMBLYAI_TERM_CHARS: int = 50;

"""A key from the environment, or from the development `.env` file."""
def api_key(name: str) -> str {
    found = os.environ.get(name, "");
    if found {
        return found;
    }
    if os.path.exists(".env") {
        with open(".env") as fh {
            for line in fh {
                if line.startswith(name + "=") {
                    return line.split("=", 1)[1].strip();
                }
            }
        }
    }
    return "";
}

"""Deepgram's query: Nova-3, raw 16 kHz mono PCM, interim results, one `keyterm` per term."""
def deepgram_query(vocabulary: list[str]) -> str {
    pairs = [
        ("model", "nova-3"),
        ("encoding", "linear16"),
        ("sample_rate", "16000"),
        ("channels", "1"),
        ("interim_results", "true"),
        ("smart_format", "true"),
        ("endpointing", "300"),
        ("mip_opt_out", "true")
    ];
    for term in vocabulary {
        pairs.append(("keyterm", term));
    }
    return urllib.parse.urlencode(pairs);
}

"""AssemblyAI's query: Universal Streaming English, formatted turns, the vocabulary as JSON."""
def assemblyai_query(vocabulary: list[str]) -> str {
    terms = [
        t
        for t in vocabulary
        if len(t) <= MAX_ASSEMBLYAI_TERM_CHARS
    ][:MAX_ASSEMBLYAI_TERMS];
    pairs = [
        ("sample_rate", "16000"),
        ("encoding", "pcm_s16le"),
        ("speech_model", "universal-streaming-english"),
        ("format_turns", "true")
    ];
    if terms {
        pairs.append(("keyterms_prompt", json.dumps(terms)));
    }
    return urllib.parse.urlencode(pairs);
}

"""One Deepgram `Results` message into the transcript."""
def take_deepgram(transcript: Transcript, message: dict[str, object]) {
    if message.get("type") != "Results" {
        return;
    }
    channel = message.get("channel");
    if not isinstance(channel, dict) {
        return;
    }
    alternatives = channel.get("alternatives");
    if not isinstance(alternatives, list) or not alternatives {
        return;
    }
    best = alternatives[0];
    text = str(best.get("transcript", "")) if isinstance(best, dict) else "";
    end = float(str(message.get("start", 0))) + float(str(message.get("duration", 0)));
    transcript.record(text, bool(message.get("is_final")), end);
}

"""One AssemblyAI `Turn` message into the transcript (a turn is final once formatted)."""
def take_assemblyai(transcript: Transcript, message: dict[str, object]) {
    if message.get("type") != "Turn" {
        return;
    }
    words = message.get("words");
    end = 0.0;
    if isinstance(words, list) and words {
        last = words[-1];
        if isinstance(last, dict) {
            end = float(str(last.get("end", 0))) / 1000;
        }
    }
    final = bool(message.get("end_of_turn")) and bool(message.get("turn_is_formatted"));
    transcript.record(str(message.get("transcript", "")), final, end);
}

"""A WebSocket streaming session shared by both services."""
obj Stream {
    has url: str,
        headers: dict[str, str],
        close_message: str,
        transcript: Transcript,
        service: str,
        _ws: ClientConnection | None = None,
        _receiver: threading.Thread | None = None,
        _ready: threading.Event = threading.Event(),
        _failure: str = "";

    """Connect; returns once the service has accepted the connection (raises if it refused)."""
    def open {
        self._ready = threading.Event();
        self._receiver = threading.Thread(target=self._run, daemon=True);
        self._receiver.start();
        self._ready.wait(timeout=20);
        if self._ws is None {
            raise RuntimeError(f"{self.service}: could not connect: {self._failure}");
        }
    }

    def _run {
        try {
            # websockets 17 wants the connection held in a with block (17.1 deprecates the rest).
            with connect(
                self.url,
                additional_headers=self.headers,
                open_timeout=15,
                close_timeout=10,
                max_size=2 ** 20
            ) as ws {
                self._ws = ws;
                self.transcript.begin();
                self._ready.set();
                self._receive(ws);
            }
        } except Exception as e {
            self._failure = f"{type(e).__name__}: {e}";
        } finally {
            self._ready.set();
        }
    }

    def _receive(ws: ClientConnection) {
        try {
            for raw in ws {
                if isinstance(raw, bytes) {
                    continue;
                }
                message = json.loads(raw);
                if not isinstance(message, dict) {
                    continue;
                }
                if message.get("type") == "Error" or "error" in message {
                    self.transcript.error = str(
                        message.get("description") or message.get("error")
                    );
                } elif self.service == "deepgram" {
                    take_deepgram(self.transcript, message);
                } else {
                    take_assemblyai(self.transcript, message);
                }
            }
        } except ConnectionClosed as e {
            if e.rcvd is not None and e.rcvd.code not in (1000, 1005) {
                self.transcript.error = f"closed {e.rcvd.code}: {e.rcvd.reason}";
            }
        }
    }

    def send(chunk: bytes) {
        if self._ws is not None {
            self._ws.send(chunk);
        }
    }

    """Ask the service to finish; wait for its last results and the close."""
    def close(timeout: float = 15.0) {
        ws = self._ws;
        if ws is None {
            return;
        }
        try {
            ws.send(self.close_message);
        } except ConnectionClosed {}
        if self._receiver is not None {
            self._receiver.join(timeout=timeout);
        }
        if self._receiver is not None and self._receiver.is_alive() {
            ws.close();
            self._receiver.join(timeout=5);
        }
        self._ws = None;
    }
}

obj DeepgramEngine {
    has tag: str,
        url: str = DEEPGRAM_URL,
        key: str = "",
        transcript: Transcript = Transcript(tag="", engine="deepgram"),
        _stream: Stream | None = None;

    def postinit {
        self.transcript = Transcript(tag=self.tag, engine="deepgram");
    }

    def start(vocabulary: list[str]) {
        key = self.key or api_key("DEEPGRAM_API_KEY");
        if not key {
            raise RuntimeError("no DEEPGRAM_API_KEY");
        }
        self._stream = Stream(
            url=f"{self.url}?{deepgram_query(vocabulary)}",
            headers={"Authorization": f"Token {key}"},
            close_message=json.dumps({"type": "CloseStream"}),
            transcript=self.transcript,
            service="deepgram"
        );
        self._stream.open();
    }

    def feed(chunk: bytes) {
        if self._stream is not None {
            self._stream.send(chunk);
        }
    }

    def finish {
        if self._stream is not None {
            self._stream.close();
            self._stream = None;
        }
    }
}

obj AssemblyAIEngine {
    has tag: str,
        url: str = ASSEMBLYAI_URL,
        key: str = "",
        transcript: Transcript = Transcript(tag="", engine="assemblyai"),
        _stream: Stream | None = None;

    def postinit {
        self.transcript = Transcript(tag=self.tag, engine="assemblyai");
    }

    def start(vocabulary: list[str]) {
        key = self.key or api_key("ASSEMBLYAI_API_KEY");
        if not key {
            raise RuntimeError("no ASSEMBLYAI_API_KEY");
        }
        self._stream = Stream(
            url=f"{self.url}?{assemblyai_query(vocabulary)}",
            headers={"Authorization": key},
            close_message=json.dumps({"type": "Terminate"}),
            transcript=self.transcript,
            service="assemblyai"
        );
        self._stream.open();
    }

    def feed(chunk: bytes) {
        if self._stream is not None {
            self._stream.send(chunk);
        }
    }

    def finish {
        if self._stream is not None {
            self._stream.close();
            self._stream = None;
        }
    }
}
