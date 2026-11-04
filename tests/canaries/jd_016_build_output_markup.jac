"""Canary for JD-016: `jac build` prints raw markup and a malformed path in its output.

The success line shows `[cyan]dist/<name>.jab[/cyan]` literally, and a native build prints
`Run with: .//tmp/...`. Asserts the current output. When this test fails, Jac has changed it:
re-check JD-016 and mark it fixed.
"""
import os;
import subprocess;
import tempfile;

test "jd_016 jac build prints literal [cyan] markup and a .// path" {
    with tempfile.TemporaryDirectory() as project {
        with open(os.path.join(project, "jac.toml"), "w") as fh {
            fh.write(
                "[project]\nname = \"repro\"\nversion = \"0.1.0\"\nentry-point = \"main\"\n"
            );
        }
        with open(os.path.join(project, "main.jac"), "w") as fh {
            fh.write(
                "def double(x: int) -> int {\n    return x * 2;\n}\n\nwith entry {\n    print(double(2));\n}\n"
            );
        }
        done = subprocess.run(
            ["jac", "build"], cwd=project, capture_output=True, text=True, timeout=600
        );
        out = done.stdout + done.stderr;
        assert done.returncode == 0 , f"build failed: {out[-300:]!r}";
        assert "[cyan]dist/repro.jab[/cyan]" in out , f"JD-016 changed: no literal markup in {out[-300:]!r}";
        assert "Run with: .//" in out , f"JD-016 changed: no './/' path in {out[-300:]!r}";
    }
}
