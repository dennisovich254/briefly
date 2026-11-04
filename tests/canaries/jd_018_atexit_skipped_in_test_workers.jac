"""Canary for JD-018: `atexit` handlers registered by test modules do not run in parallel test workers.

With several test files and four workers, no handler runs; with JAC_TEST_JOBS=0 (serial) every one
does. Asserts the current behaviour. When this test fails, Jac has changed it: re-check JD-018.
"""
import os;
import subprocess;
import tempfile;

def module_source(n: int) -> str {
    return (
        "import atexit;\nimport os;\n\n"
        + "def mark {\n"
        + f"    with open(os.path.join(os.getcwd(), \"ran-{n}.txt\"), \"w\") as fh {{\n"
        + "        fh.write(\"ran\\n\");\n    }\n}\n\n"
        + "glob _registered: bool = atexit.register(mark) is not None;\n\n"
        + f"test \"case {n}\" {{\n    assert _registered;\n}}\n"
    );
}

def handlers_run(jobs: str) -> int {
    with tempfile.TemporaryDirectory() as project {
        os.makedirs(os.path.join(project, "tests"));
        with open(os.path.join(project, "jac.toml"), "w") as fh {
            fh.write(
                "[project]\nname = \"repro\"\nversion = \"0.1.0\"\n\n[test]\ndirectory = \"tests\"\n"
            );
        }
        for n in range(5) {
            with open(
                os.path.join(project, "tests", f"case{n}_tests.jac"), "w"
            ) as fh {
                fh.write(module_source(n));
            }
        }
        env = dict(os.environ);
        env["JAC_TEST_JOBS"] = jobs;
        subprocess.run(
            ["jac", "test"], cwd=project, env=env, capture_output=True, timeout=300
        );
        return len(
            [
                f
                for f in os.listdir(project)
                if f.startswith("ran-")
            ]
        );
    }
}

test "jd_018 atexit handlers run serially but not in parallel test workers" {
    parallel = handlers_run("4");
    serial = handlers_run("0");
    assert parallel == 0 and serial == 5 , f"JD-018 changed: {parallel} ran in parallel, {serial} serially";
}
