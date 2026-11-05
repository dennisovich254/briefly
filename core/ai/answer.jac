"""Live answers through byLLM (plan 1.4, spike S4; architecture §10).

Every Claude call goes through byLLM (A05). A streamed answer leaves the server as an authenticated
Jac response stream (SSE, `answer_stream`), the delivery that works on the desktop window and the
phone alike (§11.3; JD-014 and JD-030 rule out the other two). Each frame is a dict: `delta` (text),
then exactly one of `usage` (tokens), `cancelled`, or `error` (`timeout`, or `provider` with the
exception's class name as `detail`).
"""
import from typing { Generator, cast }
import from jaclang.byllm.lib { Image, LLMTimeout, StreamEvent }

# A live answer is a few spoken sentences; the cap also bounds what one answer can cost (§10.5).
glob MAX_ANSWER_TOKENS: int = 300;

obj AnswerDraft {
    has answer: str,
        citations: list[str];
}

sem AnswerDraft.answer = "The answer, in first person, as the developer would say it in a standup.";
sem AnswerDraft.citations = "Commit SHAs, file paths or PR numbers from the evidence that support the answer; empty when none do.";

sem draft_answer = "Answer a standup question from the developer's evidence only; say so when the evidence does not answer it.";
def draft_answer(question: str, evidence: str) -> AnswerDraft by llm();

sem stream_answer = "Answer a standup question from the developer's evidence only, briefly, in first person.";
def stream_answer(question: str, evidence: str) -> str by llm(
    stream=True, logging=True, max_tokens=MAX_ANSWER_TOKENS
);

sem read_screen = "Answer the question about what is on the developer's screen.";
def read_screen(question: str, frame: Image) -> str by llm();

# Open answer streams by request ID, so `cancel_answer` can close one that its client abandoned: a
# response stream whose client disconnects is never resumed or closed by the server (JD-031).
glob _streams: dict[str, Generator[StreamEvent, None, None]] = {},
     _cancelled: set[str] = set();

"""The frames of one streamed answer (see the module docstring)."""
def answer_frames(
    question: str, evidence: str, request_id: str
) -> Generator[dict[str, object], None, None] {
    # stream=True returns a generator although the function is declared `-> str` (JD-028).
    events = cast(
        Generator[StreamEvent, None, None], stream_answer(question, evidence)
    );
    _streams[request_id] = events;
    try {
        for event in events {
            if request_id in _cancelled {
                break;
            }
            if event.event_type == "chunk" {
                yield {"type": "delta", "text": event.data["content"]};
            } elif event.event_type == "usage" {
                yield {"type": "usage", "tokens": event.data["total"]};
            }
        }
        if request_id in _cancelled {
            yield {"type": "cancelled"};
        }
    } except LLMTimeout {
        yield {"type": "error", "code": "timeout"};
    } except Exception as e {
        # A provider failure mid-stream arrives as the provider's own exception, not a ByLLMError.
        yield {"type": "error", "code": "provider", "detail": type(e).__name__};
    } finally {
        _streams.pop(request_id, None);
        _cancelled.discard(request_id);
        events.close();
    }
}

"""Stop an answer: close its byLLM stream (and so the provider's). Returns whether it was open."""
def cancel_answer(request_id: str) -> bool {
    events = _streams.pop(request_id, None);
    if events is None {
        return False;
    }
    _cancelled.add(request_id);
    try {
        events.close();
    } except ValueError {
        # The stream is running in another thread right now; answer_frames stops at its next event.
    }
    return True;
}

"""Stream an answer to the signed-in client as SSE frames (`answer.cancel` is `answer_cancel`)."""
def:protect answer_stream(question: str, request_id: str) {
    report answer_frames(question, "", request_id);
}

def:protect answer_cancel(request_id: str) -> bool {
    return cancel_answer(request_id);
}
