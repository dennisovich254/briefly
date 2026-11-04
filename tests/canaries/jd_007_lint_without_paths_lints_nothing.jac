"""Canary for JD-007: `jac check --lint` with no paths lints no files and reports success.

Asserts the current behaviour. When this test fails, Jac has changed it: re-check JD-007, mark it
fixed, and consider letting scripts/jac_lint.sh run without listing the files.
"""
import os;
import subprocess;
import tempfile;

def write(path: str, text: str) {
    with open(path, "w") as fh {
        fh.write(text);
    }
}

test "jd_007 jac check --lint without paths lints 0 files" {
    with tempfile.TemporaryDirectory() as project {
        write(
            os.path.join(project, "jac.toml"),
            "[project]\nname = \"repro\"\nversion = \"0.1.0\"\n"
        );
        write(
            os.path.join(project, "main.jac"),
            "def g() -> int {\n    return 1;\n}\n\nwith entry {\n    print(g());\n}\n"
        );
        done = subprocess.run(
            ["jac", "check", "--lint"],
            cwd=project,
            capture_output=True,
            text=True,
            timeout=300
        );
        out = done.stdout + done.stderr;
        assert done.returncode == 0 and "Linted 0 '.jac' files" in out , f"JD-007 changed: exit {done.returncode}, output {out[-300:]!r}";
    }
}
