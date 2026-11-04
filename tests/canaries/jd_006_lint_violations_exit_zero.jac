"""Canary for JD-006: no Jac command fails on a lint violation that cannot be auto-fixed.

`jac check --lint` prints the violation and exits 0 (JI-010), and `jac precommit --verify` exits 0
too. Asserts the current behaviour. When this test fails, Jac has changed it: re-check JD-006, mark
it fixed, and consider replacing scripts/jac_lint.sh with Jac's command.
"""
import os;
import subprocess;
import tempfile;

def write(path: str, text: str) {
    with open(path, "w") as fh {
        fh.write(text);
    }
}

def run_jac(project: str, args: list[str]) -> subprocess.CompletedProcess[str] {
    return subprocess.run(
        ["jac"] + args, cwd=project, capture_output=True, text=True, timeout=300
    );
}

test "jd_006 a reported lint violation exits 0 from both jac check --lint and jac precommit" {
    with tempfile.TemporaryDirectory() as project {
        write(
            os.path.join(project, "jac.toml"),
            "[project]\nname = \"repro\"\nversion = \"0.1.0\"\n"
        );
        write(
            os.path.join(project, "mutable.jac"),
            "def m(items: list[int] = []) -> int {\n    return len(items);\n}\n"
        );
        lint = run_jac(project, ["check", "--lint", "mutable.jac"]);
        lint_out = lint.stdout + lint.stderr;
        assert "mutable-default" in lint_out , f"JD-006 changed: lint no longer reports the violation: {lint_out[-300:]!r}";
        assert lint.returncode == 0 , f"JD-006 changed: jac check --lint exits {lint.returncode}";
        verify = run_jac(project, ["precommit", "--verify", "mutable.jac"]);
        assert verify.returncode == 0 , f"JD-006 changed: jac precommit --verify exits {verify.returncode}";
    }
}
