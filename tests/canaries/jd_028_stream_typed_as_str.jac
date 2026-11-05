"""Canary for JD-028: a `by llm(stream=True)` call is typed as its declared `str`, not as the generator it returns.

So iterating its `StreamEvent`s (`logging=True`) fails `jac check` with E1030, exactly as the byLLM
reference's own example does, and `jac run` refuses the file. Asserts the current behaviour (no LLM
call is made: the file is only checked). When this test fails, Jac has changed it: re-check JD-028
and drop the `cast` in core/ai/answer.jac.
"""
import os;
import subprocess;
import tempfile;

glob SOURCE: str = "def answer(question: str) -> str by llm(stream=True, logging=True);\n\nwith entry {\n    for event in answer(\"q\") {\n        print(event.event_type);\n    }\n}\n";

test "jd_028 iterating a logged stream's events fails jac check with E1030" {
    with tempfile.TemporaryDirectory() as project {
        with open(os.path.join(project, "jac.toml"), "w") as fh {
            fh.write("[project]\nname = \"repro\"\nversion = \"0.1.0\"\n");
        }
        with open(os.path.join(project, "stream.jac"), "w") as fh {
            fh.write(SOURCE);
        }
        done = subprocess.run(
            ["jac", "check", "stream.jac"],
            cwd=project,
            capture_output=True,
            text=True,
            timeout=300
        );
        out = done.stdout + done.stderr;
        assert done.returncode != 0 and "E1030" in out and "event_type" in out , f"JD-028 changed: exit {done.returncode}, output {out[-400:]!r}";
    }
}
