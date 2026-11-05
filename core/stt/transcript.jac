"""What every speech-to-text engine produces (architecture §9.1; plan 1.6, spike S3).

An engine is fed one source's audio (16 kHz mono signed 16-bit PCM, core/audio/capture.jac) and
reports utterances: partial ones as they form, then each final one. `audio_end` is where the
utterance ends in the source's own audio clock (seconds since the stream began) and `received_at`
when the engine reported it (seconds since the stream began, wall clock): their difference is the
latency from the end of speech to its text, which §13 budgets.

Every engine has the same methods: `start(vocabulary)`, `feed(chunk)`, `finish()`.
"""
import threading;
import time;

obj Utterance {
    has tag: str,
        text: str,
        final: bool,
        audio_end: float,
        received_at: float,
        engine: str;
}

"""An engine's utterances, and who to tell about each."""
obj Transcript {
    has tag: str,
        engine: str,
        started_at: float = 0.0,
        utterances: list[Utterance] = [],
        listeners: list[Callable[[Utterance], None]] = [],
        error: str = "",
        _lock: threading.Lock = threading.Lock();

    def begin {
        self.started_at = time.monotonic();
    }

    def elapsed -> float {
        return time.monotonic() - self.started_at;
    }

    def record(text: str, final: bool, audio_end: float) {
        cleaned = text.strip();
        if not cleaned {
            return;
        }
        said = Utterance(
            tag=self.tag,
            text=cleaned,
            final=final,
            audio_end=audio_end,
            received_at=self.elapsed(),
            engine=self.engine
        );
        with self._lock {
            self.utterances.append(said);
        }
        for listener in list(self.listeners) {
            listener(said);
        }
    }

    def finals -> list[Utterance] {
        with self._lock {
            return [
                u
                for u in self.utterances
                if u.final
            ];
        }
    }

    def text -> str {
        return " ".join([u.text for u in self.finals()]);
    }
}
