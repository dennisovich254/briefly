"""Canary for JD-002: JacTestClient cannot serve an entry that is not at the project root.

Asserts the current behaviour. When this test fails, Jac has changed it: re-check JD-002, mark it
fixed, and consider moving the lean entry back to hosts/lean/main.jac (architecture §6.5).
The repro runs as its own `jac run` in a throwaway project, because a test client in this
process can only serve the project under test.
"""
import os;
import subprocess;
import tempfile;

glob CHECK_SRC: str = """import os;
import tempfile;
import from jaclang.testing.testing { JacTestClient }

def ping_status(entry_file: str) -> int {
    with tempfile.TemporaryDirectory() as base {
        client = JacTestClient.from_file(os.path.join(os.getcwd(), entry_file), base_path=base);
        try {
            return client.post("/function/ping", json={}).status_code;
        } finally {
            client.close();
        }
    }
}

with entry {
    print(f"root={ping_status('main.jac')}");
    print(f"nested={ping_status(os.path.join('hosts', 'web', 'main.jac'))}");
}
""",
     ENTRY_SRC: str = """import from core.ping { ping }

with entry {
    _ = ping;
}
""";

def write(path: str, text: str) {
    os.makedirs(os.path.dirname(path), exist_ok=True);
    with open(path, "w") as fh {
        fh.write(text);
    }
}

test "jd_002 a nested entry cannot be served by JacTestClient" {
    with tempfile.TemporaryDirectory() as project {
        write(
            os.path.join(project, "jac.toml"),
            "[project]\nname = \"repro\"\nversion = \"0.1.0\"\n"
        );
        write(
            os.path.join(project, "core", "ping.jac"),
            "def:pub ping -> str {\n    return \"pong\";\n}\n"
        );
        write(os.path.join(project, "main.jac"), ENTRY_SRC);
        write(os.path.join(project, "hosts", "web", "main.jac"), ENTRY_SRC);
        write(os.path.join(project, "check.jac"), CHECK_SRC);
        done = subprocess.run(
            ["jac", "run", "check.jac"],
            cwd=project,
            capture_output=True,
            text=True,
            timeout=300
        );
        lines = done.stdout.splitlines();
        assert "root=200" in lines , f"the root entry should work: {done.stdout[-500:]} {done.stderr[-500:]}";
        assert "nested=500" in lines , f"JD-002 changed, the nested entry now gives: {lines}";
    }
}
