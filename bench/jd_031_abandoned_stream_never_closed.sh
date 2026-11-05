#!/usr/bin/env bash
# Canary for JD-031: when a client disconnects from a streamed (SSE) endpoint, the server neither
# resumes nor closes the endpoint's generator: its `finally` runs only at server shutdown.
# Builds a throwaway service whose stream logs each yield and its `finally`, disconnects a client
# after about 1 s of a 20-chunk stream, and checks the log 20 s later. No LLM call is made.
# Exit 0 = the finding still holds; exit 1 = the generator was closed: re-check JD-031; exit 2 = setup failed.
set -uo pipefail
work="$(mktemp -d -t briefly-sse-XXXXXX)"
server=""
cleanup() {
    [[ -n "$server" ]] && kill "$server" 2>/dev/null && for _ in $(seq 1 40); do kill -0 "$server" 2>/dev/null || break; sleep 1; done
    rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/app" "$work/run"
cd "$work/app" || exit 2
printf '[project]\nname = "sse"\nversion = "0.1.0"\n\n[apps.api]\nkind = "service"\nentry-point = "main"\n\n[placement]\ndefault = "server"\n' > jac.toml
cat > main.jac <<'JAC'
import os;
import time;
import from typing { Generator }

node Marker {
    has n: int = 0;
}

def log(line: str) {
    with open(os.environ["SSE_LOG"], "a") as fh {
        fh.write(line + "\n");
    }
}

def:protect slow_stream(n: int) {
    def frames -> Generator[str, None, None] {
        try {
            for i in range(n) {
                time.sleep(0.5);
                log(f"yield {i}");
                yield f"chunk {i}";
            }
        } finally {
            log("closed");
        }
    }
    report frames();
}
JAC
jac build api >/dev/null 2>&1 || { echo "jac build failed"; exit 2; }
cp dist/sse.jab "$work/run/"
export SSE_LOG="$work/run/sse.log" JAC_SERVE_WORKERS=1 JAC_SERVE_HOST=127.0.0.1
: > "$SSE_LOG"
(cd "$work/run" && exec jac run --port 8091 sse.jab >"$work/run/server.log" 2>&1) &
server=$!
for _ in $(seq 1 90); do curl -fs http://127.0.0.1:8091/healthz >/dev/null 2>&1 && break; sleep 1; done
# A synthetic fixture password for a throwaway local account, not a secret.
account='{"identities":[{"type":"username","value":"canary"}],"credential":{"type":"password","password":"Fixture-Pass-7319-xq"}}'  # gitleaks:allow
token="$(curl -s -X POST -H 'Content-Type: application/json' -d "$account" \
    http://127.0.0.1:8091/user/register | grep -oE '"token": *"[^"]+"' | cut -d'"' -f4)"
[[ -n "$token" ]] || { echo "could not register"; exit 2; }
echo "jac $(jac --version | awk '{print $2}')"
timeout 1.2 curl -sN -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $token" \
    -d '{"n":20}' http://127.0.0.1:8091/function/slow_stream >/dev/null
sleep 20
echo "log 20 s after the disconnect: $(tr '\n' ' ' < "$SSE_LOG")"
grep -q '^yield 0' "$SSE_LOG" || { echo "the stream never started"; exit 2; }
if grep -q '^closed' "$SSE_LOG"; then
    echo "changed: the abandoned stream's generator was closed"
    exit 1
fi
echo "REPRODUCES: the abandoned stream's generator is still suspended, not closed"
exit 0
