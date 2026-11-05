"""Local speech-to-text with Vosk's small English model (architecture §9.3, the local option).

Audio never leaves the laptop and nothing is paid per minute. Measured in 1.6: about 155 MB and two
times real time on the owner's two cores. It takes no vocabulary list: `start` accepts one only so
every engine has the same shape. The model is downloaded once (`ensure_model`) into
`$XDG_DATA_HOME/briefly/models` and checked against the SHA-256 pinned here (§9.7). Vosk's
publisher posts no checksums, so the pin is the hash of the archive fetched on 2026-11-05.
"""
import hashlib;
import json;
import os;
import urllib.request;
import zipfile;
import vosk;
import from core.stt.transcript { Transcript }

glob MODEL_NAME: str = "vosk-model-small-en-us-0.15",
     MODEL_URL: str = "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip",
     MODEL_SHA256: str = "30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498";

def models_dir -> str {
    data = os.environ.get("XDG_DATA_HOME", "") or os.path.expanduser("~/.local/share");
    return os.path.join(data, "briefly", "models");
}

"""The model's directory, downloading and verifying it the first time."""
def ensure_model -> str {
    target = os.path.join(models_dir(), MODEL_NAME);
    if os.path.isdir(target) {
        return target;
    }
    os.makedirs(models_dir(), exist_ok=True);
    archive = target + ".zip.part";
    urllib.request.urlretrieve(MODEL_URL, archive);
    digest = hashlib.sha256();
    with open(archive, "rb") as fh {
        block = fh.read(1 << 20);
        while block {
            digest.update(block);
            block = fh.read(1 << 20);
        }
    }
    if digest.hexdigest() != MODEL_SHA256 {
        os.remove(archive);
        raise RuntimeError(f"{MODEL_NAME}: checksum mismatch, download refused");
    }
    with zipfile.ZipFile(archive) as zf {
        zf.extractall(models_dir());
    }
    os.remove(archive);
    return target;
}

obj VoskEngine {
    has tag: str,
        transcript: Transcript = Transcript(tag="", engine="vosk"),
        _recognizer: vosk.KaldiRecognizer | None = None,
        _fed_bytes: int = 0;

    def postinit {
        self.transcript = Transcript(tag=self.tag, engine="vosk");
    }

    """Load the model; `_vocabulary` is accepted for the common shape and unused (Vosk takes none)."""
    def start(_vocabulary: list[str]) {
        vosk.SetLogLevel(-1);
        model = vosk.Model(ensure_model());
        self._recognizer = vosk.KaldiRecognizer(model, 16000);
        self._recognizer.SetWords(True);
        self.transcript.begin();
    }

    def feed(chunk: bytes) {
        if self._recognizer is None {
            return;
        }
        self._fed_bytes = self._fed_bytes + len(chunk);
        audio_end = self._fed_bytes / 32000;
        if self._recognizer.AcceptWaveform(chunk) {
            self.take_final(self._recognizer.Result(), audio_end);
        } else {
            partial = str(
                json.loads(self._recognizer.PartialResult()).get("partial", "")
            );
            self.transcript.record(partial, False, audio_end);
        }
    }

    """A final result; it ends where its last word ends (word times on), else where the feed is."""
    def take_final(raw: str, fed_until: float) {
        result = json.loads(raw);
        words = result.get("result") if isinstance(result, dict) else None;
        end = fed_until;
        if isinstance(words, list) and words and isinstance(words[-1], dict) {
            end = float(str(words[-1].get("end", fed_until)));
        }
        text = str(result.get("text", "")) if isinstance(result, dict) else "";
        self.transcript.record(text, True, end);
    }

    def finish {
        if self._recognizer is None {
            return;
        }
        self.take_final(self._recognizer.FinalResult(), self._fed_bytes / 32000);
        self._recognizer = None;
    }
}
