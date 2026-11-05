"""Canary for JD-029: the checker accepts `Generator` without an import, but at run time it is undefined.

`jac check` passes a file that uses `Generator[...]` in an expression without importing it, and
`jac run` then fails with "name 'Generator' is not defined". Asserts the current behaviour. When
this test fails, Jac has changed it: re-check JD-029.
"""
import os;
import subprocess;
import tempfile;

glob SOURCE: str = "import from typing { cast }\n\ndef numbers -> Generator[int, None, None] {\n    yield 1;\n    yield 2;\n}\n\nwith entry {\n    it = cast(Iterator[int], numbers());\n    print(f\"Iterator ok: {list(it)}\");\n    gen = cast(Generator[int, None, None], numbers());\n    print(f\"Generator ok: {list(gen)}\");\n}\n";

test "jd_029 an unimported Generator passes jac check and fails jac run" {
    with tempfile.TemporaryDirectory() as project {
        with open(os.path.join(project, "jac.toml"), "w") as fh {
            fh.write("[project]\nname = \"repro\"\nversion = \"0.1.0\"\n");
        }
        with open(os.path.join(project, "gen.jac"), "w") as fh {
            fh.write(SOURCE);
        }
        checked = subprocess.run(
            ["jac", "check", "gen.jac"],
            cwd=project,
            capture_output=True,
            text=True,
            timeout=300
        );
        ran = subprocess.run(
            ["jac", "run", "gen.jac"],
            cwd=project,
            capture_output=True,
            text=True,
            timeout=300
        );
        out = ran.stdout + ran.stderr;
        assert checked.returncode == 0 and "name 'Generator' is not defined" in out , f"JD-029 changed: check exit {checked.returncode}, run output {out[-300:]!r}";
    }
}
