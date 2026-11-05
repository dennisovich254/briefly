"""Canary for JD-036: an omitted argument of a served function receives the text of its default.

`def:pub f(on: bool = False)` called with `{}` runs with `on == "False"` (a truthy string), because
the endpoint records each default as `str(default)` (upstream jaseci-labs/jac#10602). Asserts the
current behaviour, through Jac's own test client on a throwaway project. When this test fails, Jac
has changed it: re-check JD-036, and the rule in tests/served_defaults_tests.jac can go.
"""
import os;
import tempfile;
import from jaclang.testing.testing { JacTestClient }

glob SOURCE: str = "def:pub flag(on: bool = False) -> str {\n    return type(on).__name__ + \":\" + repr(on);\n}\n";

test "jd_036 an omitted bool argument arrives as the text of its default" {
    with tempfile.TemporaryDirectory() as project {
        with open(os.path.join(project, "jac.toml"), "w") as fh {
            fh.write("[project]\nname = \"repro\"\nversion = \"0.1.0\"\n");
        }
        with open(os.path.join(project, "main.jac"), "w") as fh {
            fh.write(SOURCE);
        }
        client = JacTestClient.from_file(
            os.path.join(project, "main.jac"), base_path=os.path.join(project, "base")
        );
        try {
            text = client.post("/function/flag", json={}).text;
            assert "str:'False'" in text , f"JD-036 changed: {text[:300]!r}";
        } finally {
            client.close();
        }
    }
}
