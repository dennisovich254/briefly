"""Canary for JD-025: JacTestClient serves the app from its own copy of every module.

A module variable set through the test's own import is not seen by the served app, which loaded the
module again under `_jac_app_<hash>.`. Asserts the current behaviour. When this test fails, Jac has
changed it: re-check JD-025, and core/clock.jac could keep its frozen time in a module variable again.
"""
import os;
import subprocess;
import tempfile;

glob FLAG_SRC: str = "glob _value: str = \"unset\";\n\ndef set_value(v: str) {\n    _value = v;\n}\n\ndef:pub read_value -> str {\n    return _value;\n}\n",
     MAIN_SRC: str = "import from core.flag { read_value }\n\ndef:pub app -> str {\n    return read_value();\n}\n",
     TEST_SRC: str = "import os;\nimport tempfile;\nimport from jaclang.testing.testing { JacTestClient }\nimport from core.flag { set_value }\n\ntest \"probe\" {\n    set_value(\"from-test\");\n    with tempfile.TemporaryDirectory() as base {\n        client = JacTestClient.from_file(os.path.join(os.getcwd(), \"main.jac\"), base_path=base);\n        try {\n            served = client.post(\"/function/read_value\", json={}).data[\"result\"];\n            assert served == \"unset\" , \"served \" + served;\n        } finally {\n            client.close();\n        }\n    }\n}\n";

def write(path: str, text: str) {
    os.makedirs(os.path.dirname(path), exist_ok=True);
    with open(path, "w") as fh {
        fh.write(text);
    }
}

test "jd_025 module state set by a test does not reach the app JacTestClient serves" {
    with tempfile.TemporaryDirectory() as project {
        write(
            os.path.join(project, "jac.toml"),
            "[project]\nname = \"repro\"\nversion = \"0.1.0\"\n\n[placement]\ndefault = \"server\"\n\n[test]\ndirectory = \"tests\"\n"
        );
        write(os.path.join(project, "core", "flag.jac"), FLAG_SRC);
        write(os.path.join(project, "main.jac"), MAIN_SRC);
        write(os.path.join(project, "tests", "probe_tests.jac"), TEST_SRC);
        done = subprocess.run(
            ["jac", "test", "-v"],
            cwd=project,
            capture_output=True,
            text=True,
            timeout=300
        );
        out = done.stdout + done.stderr;
        assert done.returncode == 0 and "1 passed" in out , f"JD-025 changed: exit {done.returncode}, output {out[-400:]!r}";
    }
}
