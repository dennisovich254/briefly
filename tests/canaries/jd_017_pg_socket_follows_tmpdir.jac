"""Canary for JD-017: the embedded Postgres socket lives under the caller's TMPDIR.

With a TMPDIR long enough to push the socket path past the AF_UNIX limit, the first graph access
waits 60 s and only then fails with `AF_UNIX path too long`. Asserts the current behaviour (this
canary takes about two minutes). When this test fails, Jac has changed it: re-check JD-017.
"""
import os;
import subprocess;
import tempfile;

test "jd_017 a long TMPDIR makes graph access fail with AF_UNIX path too long" {
    with tempfile.TemporaryDirectory() as project {
        long_tmp = os.path.join(project, "t" * 60, "u" * 60);
        os.makedirs(long_tmp);
        with open(os.path.join(project, "jac.toml"), "w") as fh {
            fh.write("[project]\nname = \"repro\"\nversion = \"0.1.0\"\n");
        }
        with open(os.path.join(project, "main.jac"), "w") as fh {
            fh.write(
                "node Item {\n    has n: int;\n}\n\nwith entry {\n    root ++> Item(n=1);\n    print(len([root-->]));\n}\n"
            );
        }
        env = dict(os.environ);
        env["TMPDIR"] = long_tmp;
        done = subprocess.run(
            ["jac", "run", "main.jac"],
            cwd=project,
            env=env,
            capture_output=True,
            text=True,
            timeout=600
        );
        out = done.stdout + done.stderr;
        assert done.returncode != 0 and "AF_UNIX path too long" in out , f"JD-017 changed: exit {done.returncode}, output {out[-300:]!r}";
    }
}
