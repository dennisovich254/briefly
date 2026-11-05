"""One live call for each byLLM capability the answer path needs (plan 1.4, architecture §10.1).

    jac run bench/live_checks.jac

Spends real money (import helpers from bench/llm_live.jac, never from a module with an entry block), about $0.001 in all on claude-haiku-5-5: a structured answer, a question about a
generated image (a drawn test failure, never a capture of the screen), a streamed answer cancelled
after its first chunk, and a call with a 0.2 s deadline. Checks the key against the free model list
first and stops if it is refused. Reads ANTHROPIC_API_KEY from the environment or .env; never prints it.
"""
import io;
import os;
import sys;
import time;
import core.ai.answer as answer;
import from jaclang.byllm.lib { Image, LLMTimeout }
import from bench.llm_live { available_models, configured_model, load_key }

sem slow_question = "Answer in one short sentence.";
def slow_question(question: str) -> str by llm(timeout=0.2);

def failure_png -> bytes {
    import from PIL { Image as PilImage, ImageDraw }
    canvas = PilImage.new("RGB", (420, 70), "white");
    draw = ImageDraw.Draw(canvas);
    draw.text((10, 10), "FAILED tests/notices_test.py::test_expiry", fill="black");
    draw.text((10, 35), "AssertionError: expected 3 notices, got 2", fill="black");
    out = io.BytesIO();
    canvas.save(out, format="PNG");
    return out.getvalue();
}

def check(name: str, ok: bool, detail: str) -> bool {
    print(f"  {'ok  ' if ok else 'FAIL'}  {name}: {detail}");
    return ok;
}

def main -> int {
    if not load_key() {
        print("No ANTHROPIC_API_KEY in the environment or .env; nothing was sent.");
        return 2;
    }
    (models, error) = available_models();
    if error or configured_model() not in models {
        reason = error or configured_model();
        print(f"The key or model is not usable ({reason}); nothing was spent.");
        return 2;
    }
    print(f"model {configured_model()}");
    results: list[bool] = [];
    started = time.monotonic();
    draft = answer.draft_answer(
        "What did I merge yesterday?",
        "abc1234 Add notice expiry (src/notices.py), in PR #12 'Notice expiry', merged 16:40."
    );
    results.append(
        check(
            "structured output",
            isinstance(draft, answer.AnswerDraft) and len(draft.citations) > 0,
            f"{time.monotonic() - started:.1f} s, answer {draft.answer[:60]!r}, citations {draft.citations}"
        )
    );
    started = time.monotonic();
    seen = answer.read_screen("Which test is failing?", Image(failure_png()));
    results.append(
        check(
            "image input",
            "expiry" in seen.lower() or "notices_test" in seen.lower(),
            f"{time.monotonic() - started:.1f} s, {seen[:80]!r}"
        )
    );
    started = time.monotonic();
    frames = answer.answer_frames(
        "Describe my week in detail.",
        "Ten commits across three repositories.",
        "live-cancel"
    );
    first = next(frames);
    cancelled = answer.cancel_answer("live-cancel");
    rest = [f for f in frames];
    last = str(rest[-1]["type"]) if len(rest) > 0 else "none";
    count = len(rest);
    results.append(
        check(
            "cancellation",
            first["type"] == "delta" and cancelled and last == "cancelled",
            f"first chunk at {time.monotonic() - started:.1f} s, then {count} frame(s) ending {last}"
        )
    );
    started = time.monotonic();
    try {
        slow_question("What is a standup?");
        results.append(check("timeout", False, "the call finished inside 0.2 s"));
    } except LLMTimeout {
        results.append(
            check(
                "timeout", True, f"LLMTimeout after {time.monotonic() - started:.1f} s"
            )
        );
    }
    print("All live checks passed." if all(results) else "Some live checks failed.");
    return 0 if all(results) else 1;
}

with entry {
    sys.exit(main());
}
