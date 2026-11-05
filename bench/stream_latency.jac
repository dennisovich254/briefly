"""Time to the first readable sentence of a streamed live answer (plan 1.4, §13 typed first useful draft).

    jac run bench/stream_latency.jac --plan                  what it would do and its worst-case cost
    jac run bench/stream_latency.jac --mock                  the same path on MockLLM: free
    jac run bench/stream_latency.jac [--runs 20] [--max-cost 0.05]   live, through core/ai/answer.jac

Live runs spend money, so they are guarded: the key and the model are first checked against
Anthropic's model list (free), each answer is capped at MAX_ANSWER_TOKENS, and the run stops as soon
as the spend (byLLM's reported cost, or a conservative estimate from the token counts) reaches
--max-cost dollars. Reads ANTHROPIC_API_KEY from the environment or from .env, and never prints it.
The first answer in a process also pays for loading byLLM's provider packages (about 10 s on the
owner's laptop, JD-033), so it is reported as `cold` and left out of p50/p95, which measure warm
answers. Writes bench/results/stream-latency-<UTC time>.json; exits 1 if the warm p95 misses 4 s.
"""
import json;
import os;
import statistics;
import sys;
import time;
import core.ai.answer as answer;
import from bench.llm_live { available_models, configured_model, load_key }
import from jaclang.byllm.lib { MockLLM }

glob ROOT: str = os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
     QUESTION: str = "What did I work on yesterday?",
     EVIDENCE: str = "Commits by the developer yesterday: abc1234 Add notice expiry (src/notices.py); def5678 Rename notes to design (docs/design.md). PR #12 'Notice expiry' was merged by a reviewer at 16:40.",
     # Dollars per million tokens (input, output) for the estimate when byLLM reports no cost;
     # any other model is estimated at the conservative fallback.
     PRICES: dict[str, tuple[float, float]] = {"claude-haiku-5-5": (0.10, 0.50)},
     FALLBACK_PRICE: tuple[float, float] = (5.0, 25.0),
     TARGET_P95_S: float = 4.0;

def option(args: list[str], name: str, fallback: str) -> str {
    return args[args.index(name) + 1] if name in args else fallback;
}


obj Sample {
    has first_delta_s: float,
        first_sentence_s: float,
        total_s: float,
        prompt_tokens: int,
        completion_tokens: int,
        cost: float,
        outcome: str;
}

def one_answer(request_id: str) -> Sample {
    started = time.monotonic();
    text = "";
    first_delta = -1.0;
    first_sentence = -1.0;
    prompt_tokens = 0;
    completion_tokens = 0;
    cost = -1.0;
    outcome = "ok";
    for frame in answer.answer_frames(QUESTION, EVIDENCE, request_id) {
        elapsed = time.monotonic() - started;
        if frame["type"] == "delta" {
            if first_delta < 0 {
                first_delta = elapsed;
            }
            text += str(frame["text"]);
            if first_sentence < 0
                and any(mark in text for mark in [". ", "! ", "? ", ".\n"]) {
                first_sentence = elapsed;
            }
        } elif frame["type"] == "usage" {
            tokens = frame["tokens"];
            if isinstance(tokens, dict) {
                prompt_tokens = int(tokens.get("prompt_tokens", 0) or 0);
                completion_tokens = int(tokens.get("completion_tokens", 0) or 0);
                reported = tokens.get("cost");
                if isinstance(reported, float) or isinstance(reported, int) {
                    cost = float(reported);
                }
            }
        } else {
            outcome = str(frame.get("code", frame["type"]));
        }
    }
    total = time.monotonic() - started;
    if first_sentence < 0 and text {
        first_sentence = total;
    }
    # byLLM reports a cost of 0 for a model litellm has no price for, so 0 with tokens is unknown too.
    if cost < 0 or (cost == 0 and (prompt_tokens or completion_tokens)) {
        (in_price, out_price) = PRICES.get(configured_model(), FALLBACK_PRICE);
        cost = (prompt_tokens * in_price + completion_tokens * out_price) / 1000000;
    }
    return Sample(
        first_delta_s=round(first_delta, 3),
        first_sentence_s=round(first_sentence, 3),
        total_s=round(total, 3),
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        cost=round(cost, 6),
        outcome=outcome
    );
}

def p95(values: list[float]) -> float {
    ordered = sorted(values);
    return ordered[min(len(ordered) - 1, int(round(0.95 * (len(ordered) - 1))))];
}

def main(args: list[str]) -> int {
    runs = int(option(args, "--runs", "20"));
    max_cost = float(option(args, "--max-cost", "0.05"));
    model = configured_model();
    (in_price, out_price) = PRICES.get(model, FALLBACK_PRICE);
    worst = runs * (1000 * in_price + answer.MAX_ANSWER_TOKENS * out_price) / 1000000;
    if "--plan" in args {
        print(
            f"{runs} answers from {model}, each capped at {answer.MAX_ANSWER_TOKENS} output tokens; stops at ${max_cost:.2f} spent (every answer at the cap would be ${worst:.4f})"
        );
        return 0;
    }
    if "--mock" in args {
        model = "mock";
        answer.llm = MockLLM(
            outputs=[
                (
                    "Yesterday I added notice expiry. PR #12 was merged.",
                    {"prompt_tokens": 120, "completion_tokens": 14}
                ) for _ in range(runs)
            ]
        );
    } else {
        if not load_key() {
            print("No ANTHROPIC_API_KEY in the environment or .env; nothing was sent.");
            return 2;
        }
        (models, error) = available_models();
        if error {
            print(
                f"The key was refused by the model list ({error}); nothing was spent."
            );
            return 2;
        }
        if model not in models {
            print(
                f"{model} is not available to this key; available: {', '.join(models)}"
            );
            return 2;
        }
    }
    samples: list[Sample] = [];
    spent = 0.0;
    for n in range(runs) {
        if spent >= max_cost {
            print(
                f"Stopped after {n} answers: ${spent:.4f} spent reached the ${max_cost:.2f} cap."
            );
            break;
        }
        sample = one_answer(f"latency-{n}");
        samples.append(sample);
        spent += sample.cost;
        print(
            f"answer {n + 1}/{runs}: first sentence {sample.first_sentence_s} s, total {sample.total_s} s, {sample.prompt_tokens}+{sample.completion_tokens} tokens, ${sample.cost:.5f}, {sample.outcome}"
        );
    }
    cold = samples[0].first_sentence_s if samples else -1.0;
    firsts = [
        s.first_sentence_s
        for s in samples[1:]
        if s.outcome == "ok" and s.first_sentence_s >= 0
    ];
    if not firsts {
        print("No warm answer produced a sentence (it needs at least two runs).");
        return 1;
    }
    summary = {
        "model": model,
        "runs": len(samples),
        "spent_usd": round(spent, 4),
        "cold_first_sentence_s": cold,
        "first_sentence_s": {
            "p50": round(statistics.median(firsts), 3),
            "p95": round(p95(firsts), 3)
        },
        "samples": [
            {
                "first_delta_s": s.first_delta_s,
                "first_sentence_s": s.first_sentence_s,
                "total_s": s.total_s,
                "prompt_tokens": s.prompt_tokens,
                "completion_tokens": s.completion_tokens,
                "cost": s.cost,
                "outcome": s.outcome
            } for s in samples
        ]
    };
    if model != "mock" {
        out_dir = os.path.join(ROOT, "bench", "results");
        os.makedirs(out_dir, exist_ok=True);
        out = os.path.join(
            out_dir,
            f"stream-latency-{time.strftime('%Y%m%dT%H%MZ', time.gmtime())}.json"
        );
        with open(out, "w") as fh {
            json.dump(summary, fh, indent=2);
            fh.write("\n");
        }
        print(f"-> {out}");
    }
    print(
        f"first readable sentence: cold {cold} s; warm p50 {summary['first_sentence_s'][
            'p50'
        ]} s, p95 {summary['first_sentence_s']['p95']} s (target p95 {TARGET_P95_S} s); spent ${spent:.4f}"
    );
    return 0 if p95(firsts) <= TARGET_P95_S else 1;
}

with entry {
    sys.exit(main(sys.argv[1:]));
}
