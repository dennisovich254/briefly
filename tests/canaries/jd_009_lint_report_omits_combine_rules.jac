"""Canary for JD-009: `jac check --lint` never reports combine-glob or combine-has, which the fix applies.

`jac fmt --lintfix` and `jac precommit` apply and report both rules, and the merge moves the first
declaration's trailing comment to the end of the combined statement. Asserts the current behaviour.
When this test fails, Jac has changed it: re-check JD-009 and mark it fixed.
"""
import os;
import subprocess;
import tempfile;

glob SRC: str = "glob A: int = 1;  # about A\nglob B: int = 2;\n";

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

test "jd_009 lint reports nothing that lintfix rewrites, and the rewrite moves a comment" {
    with tempfile.TemporaryDirectory() as project {
        write(
            os.path.join(project, "jac.toml"),
            "[project]\nname = \"repro\"\nversion = \"0.1.0\"\n"
        );
        path = os.path.join(project, "globs.jac");
        write(path, SRC);
        lint = run_jac(project, ["check", "--lint", "globs.jac"]);
        lint_out = lint.stdout + lint.stderr;
        assert "combine-glob" not in lint_out , f"JD-009 changed: jac check --lint reports combine-glob: {lint_out[-300:]!r}";
        verify = run_jac(project, ["precommit", "--verify", "globs.jac"]);
        assert verify.returncode == 1 , f"JD-009 changed: jac precommit --verify exits {verify.returncode}";
        run_jac(project, ["fmt", "--lintfix", "globs.jac"]);
        with open(path) as fh {
            fixed = fh.read();
        }
        assert fixed == "glob A: int = 1,\n     B: int = 2;  # about A\n" , f"JD-009 changed: lintfix wrote {fixed!r}";
    }
}
