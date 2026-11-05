"""The answer stream over HTTP (plan 1.4, architecture §11.3): an authenticated Jac response stream (SSE)."""
import os;
import tempfile;
import from jaclang.testing.testing { JacTestClient }
import from jaclang.byllm.lib { MockLLM }
import from tests.support.served { served_module }

glob PASSWORD: str = "Fixture-Pass-7319-xq";

def open_client(base: str) -> JacTestClient {
    return JacTestClient.from_file(
        os.path.join(os.getcwd(), "main.jac"), base_path=base
    );
}

test "the answer stream needs a signed-in client" {
    with tempfile.TemporaryDirectory() as base {
        client = open_client(base);
        try {
            resp = client.post(
                "/function/answer_stream", json={"question": "q", "request_id": "r1"}
            );
            assert resp.status_code == 401 , f"{resp.status_code} {resp.text[:200]}";
        } finally {
            client.close();
        }
    }
}

test "a signed-in client receives the answer as SSE frames" {
    with tempfile.TemporaryDirectory() as base {
        client = open_client(base);
        try {
            registered = client.register_user("standup", PASSWORD);
            assert registered.ok , registered.text;
            client.login("standup", PASSWORD);
            served_module("core.ai.answer").llm = MockLLM(
                outputs=["Merged the expiry fix."]
            );
            resp = client.post(
                "/function/answer_stream",
                json={"question": "What did I merge?", "request_id": "r2"}
            );
            assert resp.ok , f"{resp.status_code} {resp.text[:200]}";
            assert "\"type\": \"delta\"" in resp.text , resp.text[:400];
            assert "event: end" in resp.text , resp.text[-200:];
        } finally {
            client.close();
        }
    }
}
