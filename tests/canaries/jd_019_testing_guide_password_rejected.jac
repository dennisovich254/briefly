"""Canary for JD-019: the testing guide's JacTestClient example registers a password the auth policy rejects.

`jac guide jac-testing` registers "testuser" with "password123"; the server answers 400
POLICY_VIOLATION ("the password is too common"), and `register_user` returns that response without
raising, so the example's later requests run unauthenticated. Asserts the current behaviour. When
this test fails, Jac has changed it: re-check JD-019.
"""
import os;
import tempfile;
import from jaclang.testing.testing { JacTestClient }

test "jd_019 register_user with the guide's password returns a 400 policy violation" {
    with tempfile.TemporaryDirectory() as base {
        with open(os.path.join(base, "app.jac"), "w") as fh {
            fh.write("def:protect hello -> str {\n    return \"hi\";\n}\n");
        }
        client = JacTestClient.from_file(os.path.join(base, "app.jac"), base_path=base);
        try {
            resp = client.register_user("testuser", "password123");
            assert resp.status_code == 400 and "POLICY_VIOLATION" in resp.text , f"JD-019 changed: register answered {resp.status_code} {resp.text[:200]!r}";
            assert client.post("/function/hello", json={}).status_code == 401 , "JD-019 changed: the client is now authenticated";
        } finally {
            client.close();
        }
    }
}
