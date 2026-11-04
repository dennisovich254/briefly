"""Canary for JD-013 (JI-019): the mobile scaffold pins React 18 at the project level.

In a workspace, that pin applies to every app, so a web or desktop app installs React 18.3.1 instead
of the React 19 the client runtime expects. Asserts the current behaviour. When this test fails, Jac
has changed it: re-check JD-013 and mark it fixed.
"""
import os;
import subprocess;
import tempfile;
import tomllib;

test "jd_013 jac create --kind mobile pins react ^18 in the project dependencies" {
    with tempfile.TemporaryDirectory() as base {
        done = subprocess.run(
            ["jac", "create", "m", "--kind", "mobile", "--skip"],
            cwd=base,
            capture_output=True,
            text=True,
            timeout=300
        );
        assert done.returncode == 0 , f"jac create failed: {done.stderr[-300:]!r}";
        with open(os.path.join(base, "m", "jac.toml"), "rb") as fh {
            config = tomllib.load(fh);
        }
        pin = str(config.get("dependencies", {}).get("npm", {}).get("react", ""));
        assert pin.startswith("^18") , f"JD-013 changed: react pin is {pin!r}";
    }
}
