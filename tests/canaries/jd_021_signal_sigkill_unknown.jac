"""Canary for JD-021: the type checker treats `signal.SIGKILL` as Unknown, so Jac refuses valid code.

`os.kill(pid, signal.SIGKILL)` fails `jac check` (and so `jac run`) with E1053, while
`signal.SIGTERM` and `signal.Signals.SIGKILL` are accepted. Asserts the current behaviour. When this
test fails, Jac has changed it: re-check JD-021 and drop the `signal.Signals.SIGKILL` workaround in
bench/mem.jac.
"""
import os;
import subprocess;
import tempfile;

glob SOURCE: str = "import os;\nimport signal;\n\ndef stop(pid: int) {\n    os.kill(pid, signal.SIGKILL);\n}\n\ndef term(pid: int) {\n    os.kill(pid, signal.SIGTERM);\n}\n";

test "jd_021 jac check rejects os.kill(pid, signal.SIGKILL) but not SIGTERM" {
    with tempfile.TemporaryDirectory() as project {
        with open(os.path.join(project, "jac.toml"), "w") as fh {
            fh.write("[project]\nname = \"repro\"\nversion = \"0.1.0\"\n");
        }
        with open(os.path.join(project, "sig.jac"), "w") as fh {
            fh.write(SOURCE);
        }
        done = subprocess.run(
            ["jac", "check", "sig.jac"],
            cwd=project,
            capture_output=True,
            text=True,
            timeout=300
        );
        out = done.stdout + done.stderr;
        assert done.returncode != 0
            and "E1053" in out
            and "sig.jac:5:" in out
            and "sig.jac:9:" not in out , f"JD-021 changed: exit {done.returncode}, output {out[-400:]!r}";
    }
}
