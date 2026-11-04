"""Canary for JD-015: four layout quirks of `jac fmt`, all behaviour-preserving.

A continued `glob` list is indented by 9 spaces; a multi-line dict with a trailing comma collapses to
one line that keeps the comma; `assert x, msg` becomes `assert x , msg`; an expression inside an
f-string's braces is split across lines. Asserts the current output. When this test fails, Jac has
changed it: re-check JD-015 and mark the quirk fixed.
"""
import os;
import subprocess;
import tempfile;

glob CASES: dict[str, tuple[str, str]] = {
         "glob_list": (
             "glob NAMES: list[str] = [\n    \"alpha-alpha-alpha-alpha\",\n    \"beta-beta-beta-beta-beta\",\n    \"gamma-gamma-gamma-gamma\"\n];\n",
             "         \"alpha-alpha-alpha-alpha\","
         ),
         "dict_trailing_comma": (
             "with entry {\n    settings = {\n        \"alpha\": 1,\n        \"beta\": 2,\n    };\n    print(settings);\n}\n",
             "settings = {\"alpha\": 1, \"beta\": 2,};"
         ),
         "assert_message": (
             "test \"message\" {\n    assert 1 == 1, \"one is one\";\n}\n",
             "assert 1 == 1 , \"one is one\";"
         ),
         "fstring_braces": (
             "with entry {\n    items = [\"alpha\", \"beta\"];\n    print(f\"the items were {', '.join(sorted(item.upper() for item in items if item.startswith('a') or item.startswith('b')))} today\");\n}\n",
             "f\"the items were {', '.join(\n"
         )
     };

test "jd_015 jac fmt keeps its four layout quirks" {
    with tempfile.TemporaryDirectory() as project {
        with open(os.path.join(project, "jac.toml"), "w") as fh {
            fh.write("[project]\nname = \"repro\"\nversion = \"0.1.0\"\n");
        }
        changed: list[str] = [];
        for (name, (source, expected)) in CASES.items() {
            path = os.path.join(project, f"{name}.jac");
            with open(path, "w") as fh {
                fh.write(source);
            }
            subprocess.run(
                ["jac", "fmt", path], cwd=project, capture_output=True, timeout=300
            );
            with open(path) as fh {
                formatted = fh.read();
            }
            if expected not in formatted {
                changed.append(f"{name}: {formatted!r}");
            }
        }
        assert not changed , f"JD-015 changed: {changed}";
    }
}
