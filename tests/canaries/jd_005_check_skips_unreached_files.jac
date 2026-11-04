"""Canary for JD-005: in a workspace, `jac check` with no paths skips every file no app imports.

Asserts the current behaviour. When this test fails, Jac has changed it: re-check JD-005, mark it
fixed, and consider letting scripts/check_warnings.sh run a bare `jac check` again.
"""
import os;
import subprocess;
import tempfile;

def write(path: str, text: str) {
    os.makedirs(os.path.dirname(path), exist_ok=True);
    with open(path, "w") as fh {
        fh.write(text);
    }
}

test "jd_005 jac check passes a workspace whose unreached file has a type error" {
    with tempfile.TemporaryDirectory() as project {
        write(
            os.path.join(project, "jac.toml"),
            "[project]\nname = \"repro\"\nversion = \"0.1.0\"\n\n[apps.web]\nkind = \"web-app\"\nentry-point = \"main\"\n"
        );
        write(
            os.path.join(project, "main.jac"), "with entry {\n    print(\"hi\");\n}\n"
        );
        write(
            os.path.join(project, "tests", "broken.jac"),
            "def broken -> int {\n    return \"not an int\";\n}\n"
        );
        done = subprocess.run(
            ["jac", "check"], cwd=project, capture_output=True, text=True, timeout=300
        );
        out = done.stdout + done.stderr;
        assert done.returncode == 0 and "broken.jac" not in out , f"JD-005 changed: exit {done.returncode}, output {out[-300:]!r}";
    }
}
