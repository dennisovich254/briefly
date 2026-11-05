"""Contract tests for live answers through byLLM (plan 1.4, architecture §10). MockLLM only: no key, no cost."""
import core.ai.answer as answer;
import from jaclang.byllm.lib { MockLLM, MockError, MockRawResponse, Image, LLMTimeout }

glob PNG: bytes = bytes.fromhex(
         "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000000000300015a7d8cd40000000049454e44ae426082"
     );

def frames_of(question: str, request_id: str) -> list[dict[str, object]] {
    return [f for f in answer.answer_frames(question, "", request_id)];
}

test "a draft answer comes back as structured output" {
    answer.llm = MockLLM(
        outputs=[
            answer.AnswerDraft(
                answer="PR #12 merged the expiry fix.", citations=["abc123"]
            )
        ]
    );
    draft = answer.draft_answer("What did I merge?", "abc123 Add notice expiry");
    assert draft.answer == "PR #12 merged the expiry fix."
        and draft.citations == ["abc123"];
    assert "Add notice expiry" in str(answer.llm.sent("messages")[0]);
}

test "a malformed structured answer is retried and recovered" {
    answer.llm = MockLLM(
        outputs=[
            MockRawResponse(content="{\"answer\": \"PR #12\", \"citations\":"),
            MockRawResponse(
                content="{\"answer\": \"PR #12\", \"citations\": [\"abc123\"]}"
            )
        ]
    );
    draft = answer.draft_answer("What did I merge?", "abc123");
    assert draft.citations == ["abc123"];
    assert len(answer.llm.seen_prompts) == 2;
}

test "a streamed answer arrives in order and ends with its token usage" {
    answer.llm = MockLLM(
        outputs=[
            (
                "Yesterday I merged the notice expiry fix.",
                {"prompt_tokens": 40, "completion_tokens": 9, "total_tokens": 49}
            )
        ]
    );
    frames = frames_of("What did I do yesterday?", "r1");
    deltas = [
        str(f["text"])
        for f in frames
        if f["type"] == "delta"
    ];
    assert len(deltas) >= 1
        and "".join(deltas) == "Yesterday I merged the notice expiry fix.";
    assert frames[-1]["type"] == "usage" , frames[-1];
    tokens = frames[-1]["tokens"];
    assert isinstance(tokens, dict) and tokens["total_tokens"] == 49 , frames[-1];
}

test "a screen frame reaches the model with the question" {
    answer.llm = MockLLM(outputs=["A failing test in notices_test.py."]);
    assert answer.read_screen("What is failing?", Image(PNG))
        == "A failing test in notices_test.py.";
    assert "image" in str(answer.llm.sent("messages")[0]);
}

test "cancelling an answer closes its stream" {
    answer.llm = MockLLM(outputs=["one two three four five six seven eight nine ten"]);
    frames = answer.answer_frames("q", "", "r2");
    first = next(frames);
    assert first["type"] == "delta";
    assert answer.cancel_answer("r2");
    rest = [f for f in frames];
    assert rest[-1]["type"] == "cancelled" , rest;
    assert not answer.cancel_answer("r2") , "a cancelled answer is forgotten";
}

test "a provider that keeps timing out ends the stream with a timeout frame" {
    answer.llm = MockLLM(
        outputs=[MockError(error=LLMTimeout("provider stalled")) for _ in range(6)]
    );
    frames = frames_of("q", "r3");
    assert frames[-1] == {"type": "error", "code": "timeout"} , frames;
}

test "a provider failure mid-answer keeps the text so far and ends with an error frame" {
    answer.llm = MockLLM(
        outputs=[
            MockError(
                error=RuntimeError("connection reset"), content="one two three", after=2
            )
        ]
    );
    frames = frames_of("q", "r4");
    assert any(f["type"] == "delta" for f in frames) , frames;
    assert frames[-1]
        == {"type": "error", "code": "provider", "detail": "RuntimeError"} , frames;
}
