"""Shared helpers for the live Claude benchmarks (bench/stream_latency.jac, bench/live_checks.jac).

No entry block: importing this module never makes a call. Reads the key from the environment or
.env without printing it; the model list check is free.
"""
import json;
import os;
import tomllib;
import urllib.request;

glob ROOT: str = os.path.dirname(os.path.dirname(os.path.abspath(__file__)));

def load_key -> bool {
    if os.environ.get("ANTHROPIC_API_KEY") {
        return True;
    }
    path = os.path.join(ROOT, ".env");
    if os.path.exists(path) {
        with open(path) as fh {
            for line in fh {
                if line.startswith("ANTHROPIC_API_KEY=") {
                    os.environ["ANTHROPIC_API_KEY"] = line.split("=", 1)[1].strip();
                }
            }
        }
    }
    return bool(os.environ.get("ANTHROPIC_API_KEY"));
}

def configured_model -> str {
    with open(os.path.join(ROOT, "jac.toml"), "rb") as fh {
        return str(
            tomllib.load(fh).get("byllm", {}).get("model", {}).get("default_model", "")
        );
    }
}

"""The model IDs the key can use (a free request), or the error that made it fail."""
def available_models -> tuple[list[str], str] {
    request = urllib.request.Request(
        "https://api.anthropic.com/v1/models?limit=100",
        headers={
            "x-api-key": os.environ["ANTHROPIC_API_KEY"],
            "anthropic-version": "2023-06-01"
        }
    );
    try {
        with urllib.request.urlopen(request, timeout=20) as resp {
            body = json.loads(resp.read());
        }
        return ([str(m["id"]) for m in body.get("data", [])], "");
    } except urllib.error.HTTPError as e {
        return ([], f"HTTP {e.code}");
    } except Exception as e {
        return ([], type(e).__name__);
    }
}
