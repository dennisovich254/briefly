"""Canary for JD-004: a module Jac compiles native crashes on `glob t: datetime | None` plus `t = t + delta`.

Asserts the current behaviour. When this test fails, Jac has changed it: re-check JD-004, mark it
fixed, and consider removing `[placement] default = "server"` from jac.toml.
The module runs as its own `jac run` in a throwaway project with Jac's default placement (native).
"""
import os;
import subprocess;
import tempfile;

glob MOD_SRC: str = """import from datetime { datetime, timedelta, timezone }

glob _t: datetime | None = None;

def setv(at: datetime) {
    _t = at;
}

def advance(delta: timedelta) {
    _t = _t + delta;
}

def value -> datetime | None {
    return _t;
}
""",
     MAIN_SRC: str = """import from datetime { datetime, timedelta, timezone }
import from mod { setv, advance, value }

with entry {
    setv(datetime(2026, 3, 2, 9, 30, tzinfo=timezone.utc));
    advance(timedelta(hours=25));
    print(f"t={value()}");
}
""";

def write(path: str, text: str) {
    with open(path, "w") as fh {
        fh.write(text);
    }
}

test "jd_004 a native module crashes adding a timedelta to an optional datetime glob" {
    with tempfile.TemporaryDirectory() as project {
        write(
            os.path.join(project, "jac.toml"),
            "[project]\nname = \"repro\"\nversion = \"0.1.0\"\n"
        );
        write(os.path.join(project, "mod.jac"), MOD_SRC);
        write(os.path.join(project, "main.jac"), MAIN_SRC);
        done = subprocess.run(
            ["jac", "run", "main.jac"],
            cwd=project,
            capture_output=True,
            text=True,
            timeout=300
        );
        assert done.returncode in [-11, 139] , f"JD-004 changed: exit {done.returncode}, output {done.stdout[-300:]!r}";
    }
}
