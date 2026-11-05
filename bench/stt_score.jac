"""Score speech-to-text engines on the owner's reading of the fixed standup (plan 1.6, S3; §9.3).

    jac run bench/stt_score.jac --plan                       # duration and estimated cost; nothing sent
    jac run bench/stt_score.jac --engines vosk                # local only: free, nothing leaves the laptop
    jac run bench/stt_score.jac --engines vosk,deepgram,assemblyai [--max-cost 0.10]

Streams bench/private/standup.wav (bench/stt/record.jac) to each engine at real-time pace, as a
live meeting would, with the terms in bench/stt/terms.txt as vocabulary. Reports per engine: word
error rate, the terms it got right, the lag from the end of speech to its final text (p50, p95),
the cost, and for the local model its memory. Writes bench/results/stt-<time>.json (text only,
never audio). Cloud keys come from DEEPGRAM_API_KEY / ASSEMBLYAI_API_KEY or .env and are never
printed. Prices as published on 2026-11-05; both services bill new accounts from free credit.
"""
import json;
import os;
import statistics;
import sys;
import time;
import wave;
import bench.stt.score as score;
import core.stt.cloud as cloud;
import core.stt.local_vosk as local_vosk;

glob WAV: str = os.path.join("bench", "private", "standup.wav"),
     # US dollars per minute of streamed audio, vocabulary (keyterms) included.
     PRICE_PER_MINUTE: dict[str, float] = {
         "vosk": 0.0,
         "deepgram": 0.0077 + 0.0013,
         "assemblyai": (0.15 + 0.04) / 60
     },
     CHUNK_SECONDS: float = 0.1;

def rss_mb -> float {
    with open("/proc/self/status") as fh {
        for line in fh {
            if line.startswith("VmRSS:") {
                return int(line.split()[1]) / 1024;
            }
        }
    }
    return 0.0;
}

def make_engine(
    name: str
) -> local_vosk.VoskEngine | cloud.DeepgramEngine | cloud.AssemblyAIEngine {
    if name == "vosk" {
        return local_vosk.VoskEngine(tag="others");
    } elif name == "deepgram" {
        return cloud.DeepgramEngine(tag="others");
    }
    return cloud.AssemblyAIEngine(tag="others");
}

def percentile(values: list[float], q: float) -> float {
    if not values {
        return -1.0;
    }
    ordered = sorted(values);
    return ordered[min(len(ordered) - 1, int(round(q * (len(ordered) - 1))))];
}

"""Stream the audio at real-time pace into one engine and score what comes back."""
def run_engine(
    name: str, pcm: bytes, terms: list[score.Term], reference: str
) -> dict[str, object] {
    engine = make_engine(name);
    before = rss_mb();
    started = time.monotonic();
    engine.start(score.vocabulary(terms));
    chunk = int(CHUNK_SECONDS * 32000);
    sent_at = time.monotonic();
    for (i, offset) in enumerate(range(0, len(pcm), chunk)) {
        engine.feed(pcm[offset:offset + chunk]);
        pause = sent_at + (i + 1) * CHUNK_SECONDS - time.monotonic();
        if pause > 0 {
            time.sleep(pause);
        }
    }
    engine.finish();
    after = rss_mb();
    finals = engine.transcript.finals();
    hypothesis = engine.transcript.text();
    lags = [
        u.received_at - u.audio_end
        for u in finals
        if u.audio_end > 0
    ];
    found = score.terms_found(terms, hypothesis);
    minutes = len(pcm) / 32000 / 60;
    return {
        "engine": name,
        "error": engine.transcript.error,
        "word_error_rate": round(score.word_error_rate(reference, hypothesis), 4),
        "terms_right": len(found),
        "terms_total": len(terms),
        "terms_missed": [
            t.name
            for t in terms
            if t.name not in found
        ],
        "final_lag_p50_s": round(statistics.median(lags), 2) if lags else -1,
        "final_lag_p95_s": round(percentile(lags, 0.95), 2),
        "utterances": len(finals),
        "cost_usd": round(minutes * PRICE_PER_MINUTE[name], 4),
        "rss_growth_mb": round(after - before, 1) if name == "vosk" else None,
        "wall_seconds": round(time.monotonic() - started, 1),
        "transcript": hypothesis
    };
}

def main -> int {
    args = sys.argv[1:];
    wav_path = args[args.index("--wav") + 1] if "--wav" in args else WAV;
    names = (
        args[args.index("--engines") + 1].split(",")
            if "--engines" in args
            else ["vosk", "deepgram", "assemblyai"]
    );
    cap = float(args[args.index("--max-cost") + 1]) if "--max-cost" in args else 0.10;
    unknown = [
        n
        for n in names
        if n not in PRICE_PER_MINUTE
    ];
    if unknown {
        print(f"Unknown engines: {unknown}. Known: {list(PRICE_PER_MINUTE)}");
        return 2;
    }
    if not os.path.exists(wav_path) {
        print(
            f"No recording at {wav_path}: record it first with jac run bench/stt/record.jac"
        );
        return 2;
    }
    with wave.open(wav_path) as w {
        if w.getframerate() != 16000
            or w.getnchannels() != 1
            or w.getsampwidth() != 2 {
            print(
                "The recording must be 16 kHz mono 16-bit (bench/stt/record.jac writes that)."
            );
            return 2;
        }
        pcm = w.readframes(w.getnframes());
    }
    minutes = len(pcm) / 32000 / 60;
    estimate = sum([minutes * PRICE_PER_MINUTE[n] for n in names]);
    print(
        f"{wav_path}: {minutes * 60:.0f} s; engines {', '.join(names)}; estimated cost ${estimate:.4f} (cap ${cap:.2f})"
    );
    if "--plan" in args {
        for n in names {
            print(f"  {n}: ${minutes * PRICE_PER_MINUTE[n]:.4f}");
        }
        return 0;
    }
    if estimate > cap {
        print("Over the cap; nothing was sent. Raise --max-cost to run.");
        return 2;
    }
    for n in names {
        if n != "vosk" and not cloud.api_key(f"{n.upper()}_API_KEY") {
            print(
                f"No {n.upper()}_API_KEY in the environment or .env; nothing was sent."
            );
            return 2;
        }
    }
    lines = score.load_script();
    terms = score.load_terms();
    reference = score.reference_text(lines);
    results: list[dict[str, object]] = [];
    for n in names {
        print(f"\n{n}: streaming {minutes * 60:.0f} s of audio at real-time pace…");
        try {
            result = run_engine(n, pcm, terms, reference);
        } except Exception as e {
            result = {"engine": n, "error": f"{type(e).__name__}: {e}"};
        }
        results.append(result);
        if result.get("error") {
            print(f"  error: {result['error']}");
        }
        if "word_error_rate" in result {
            print(
                f"  WER {float(str(result['word_error_rate'])) * 100:.1f} %, terms {result[
                    'terms_right'
                ]}/{result['terms_total']}, "
                    + f"final lag p50 {result['final_lag_p50_s']} s / p95 {result[
                        'final_lag_p95_s'
                    ]} s, ${result['cost_usd']}"
            );
            missed = result.get("terms_missed");
            missed_text = ", ".join([str(t) for t in missed])
                if isinstance(missed, list)
                else "";
            print(f"  missed: {missed_text or 'none'}");
        }
    }
    stamp = time.strftime("%Y%m%dT%H%MZ", time.gmtime());
    out = os.path.join("bench", "results", f"stt-{stamp}.json");
    with open(out, "w") as fh {
        json.dump(
            {
                "recording_seconds": round(minutes * 60, 1),
                "jac": os.popen("jac --version").read().strip(),
                "engines": results
            },
            fh,
            indent=2
        );
        fh.write("\n");
    }
    print(f"\nWrote {out}");
    return 0 if all([not r.get("error") for r in results]) else 1;
}

with entry {
    sys.exit(main());
}
