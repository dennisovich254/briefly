"""Checks that the suite runs the way scripts/test.sh promises (plan 0.4)."""
import os;
import subprocess;
import tempfile;
import from jaclang.byllm.lib { MockLLM }

glob llm = MockLLM(outputs=["Merged the notices fix."]);

def summarise(change: str) -> str by llm();

def write(path: str, text: str) {
    os.makedirs(os.path.dirname(path), exist_ok=True);
    with open(path, "w") as fh {
        fh.write(text);
    }
}

"""Run `jac test` on a throwaway project whose only test file imports a module that does not exist."""
def run_broken_project(strict: bool) -> int {
    with tempfile.TemporaryDirectory() as project {
        write(
            os.path.join(project, "jac.toml"),
            "[project]\nname = \"repro\"\nversion = \"0.1.0\"\n\n[test]\ndirectory = \"tests\"\n"
        );
        write(
            os.path.join(project, "tests", "broken_tests.jac"),
            "import from missing_module { thing }\n\ntest \"uses thing\" {\n    assert thing == 1;\n}\n"
        );
        env = dict(os.environ);
        env.pop("JAC_TEST_STRICT", None);
        if strict {
            env["JAC_TEST_STRICT"] = "1";
        }
        done = subprocess.run(
            ["jac", "test"],
            cwd=project,
            env=env,
            capture_output=True,
            text=True,
            timeout=300
        );
        return done.returncode;
    }
}

test "the suite runs in strict mode" {
    assert os.environ.get("JAC_TEST_STRICT") == "1" , "run the tests with scripts/test.sh";
}

test "the suite runs with clock control enabled" {
    assert os.environ.get("BRIEFLY_CLOCK_CONTROL") == "1" , "run the tests with scripts/test.sh";
}

test "strict mode fails a test file whose local import is missing" {
    assert run_broken_project(True) != 0;
}

test "MockLLM answers a by-llm function offline" {
    assert summarise("PR #12 merged") == "Merged the notices fix.";
    assert "PR #12 merged" in str(llm.sent("messages")[0]);
}
