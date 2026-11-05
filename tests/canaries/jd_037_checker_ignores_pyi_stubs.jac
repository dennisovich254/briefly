"""Canary for JD-037: `jac check` ignores a `.pyi` stub beside its `.py`.

A module whose `.py` is unannotated and whose `.pyi` declares `make() -> Code` is typed from the
`.py`, so `make().show()` fails with E1030 (`Type "object" has no attribute "show"`). Asserts the
current behaviour. When this test fails, Jac has changed it: re-check JD-037 and drop the cast in
bench/phone_link.jac.
"""
import os;
import subprocess;
import tempfile;

glob FILES: dict[str, str] = {
         "jac.toml": "[project]\nname = \"repro\"\nversion = \"0.1.0\"\n",
         "stubmod.py": "class Code:\n    def show(self):\n        print(\"shown\")\n\ndef make():\n    return Code()\n",
         "stubmod.pyi": "class Code:\n    def show(self) -> None: ...\n\ndef make() -> Code: ...\n",
         "s.jac": "import stubmod;\n\nwith entry {\n    stubmod.make().show();\n}\n"
     };

test "jd_037 a call typed only by a pyi stub fails jac check with E1030" {
    with tempfile.TemporaryDirectory() as project {
        for (name, text) in FILES.items() {
            with open(os.path.join(project, name), "w") as fh {
                fh.write(text);
            }
        }
        done = subprocess.run(
            ["jac", "check", "s.jac"],
            cwd=project,
            capture_output=True,
            text=True,
            timeout=300
        );
        out = done.stdout + done.stderr;
        assert done.returncode != 0 and "E1030" in out and "show" in out , f"JD-037 changed: exit {done.returncode}, output {out[-400:]!r}";
    }
}
