"""Canary for JD-012 (JI-001): without strict mode, `jac test` skips a test file whose in-project import is missing.

Asserts the current behaviour: the file is reported as skipped and `jac test` exits 0.
scripts/test.sh sets JAC_TEST_STRICT=1, which turns it into an error. When this test fails, Jac has
changed it: re-check JD-012 and mark it fixed.
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

test "jd_012 a test file with a missing local import is skipped and jac test exits 0" {
    with tempfile.TemporaryDirectory() as project {
        write(
            os.path.join(project, "jac.toml"),
            "[project]\nname = \"repro\"\nversion = \"0.1.0\"\n"
        );
        write(
            os.path.join(project, "mylib", "real.jac"),
            "def one -> int {\n    return 1;\n}\n"
        );
        write(
            os.path.join(project, "checks", "broken_tests.jac"),
            "import from mylib.missing { one }\n\ntest \"never runs\" {\n    assert one() == 999;\n}\n"
        );
        env = dict(os.environ);
        env.pop("JAC_TEST_STRICT", None);
        done = subprocess.run(
            ["jac", "test", "-d", "checks"],
            cwd=project,
            env=env,
            capture_output=True,
            text=True,
            timeout=300
        );
        out = done.stdout + done.stderr;
        assert done.returncode == 0 and "1 skipped" in out , f"JD-012 changed: exit {done.returncode}, output {out[-300:]!r}";
    }
}
