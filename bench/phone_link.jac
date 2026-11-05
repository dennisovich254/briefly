"""The phone link on a real phone (plan 1.5, spike S7; architecture §5.6). Run by the owner.

    jac install --dev                              # once: segno, for the QR code
    jac run lean                                   # terminal 1 (or the desktop app: pass its --base)
    jac run bench/phone_link.jac [--https] [--base http://127.0.0.1:8000]   # terminal 2

Plays the laptop's side against the running app: signs in with a throwaway account, starts a phone
session, and prints the QR code (the LAN URL with a one-time pairing code). Scan it with the phone
on the same network: home Wi-Fi, or the phone's hotspot with the laptop joined to it. Once the
phone pairs, three messages are sent to it a few seconds apart. Then try the same link on a second
device (it must be refused), and press Enter to end the session (the phone must show it ended).

With --https the phone link uses this install's self-signed certificate: the phone browser will
warn; compare the fingerprint it shows (if it shows one) with the one printed here. Makes no Claude
calls and costs nothing.
"""
import json;
import secrets;
import segno;
import sys;
import time;
import urllib.error;
import urllib.request;

def post(
    base: str, path: str, body: dict[str, object], token: str = ""
) -> dict[str, object] {
    headers = {"Content-Type": "application/json"};
    if token {
        headers["Authorization"] = f"Bearer {token}";
    }
    req = urllib.request.Request(
        base + path, data=json.dumps(body).encode(), headers=headers, method="POST"
    );
    try {
        with urllib.request.urlopen(req, timeout=30) as resp {
            return json.loads(resp.read())["data"];
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"{path}: HTTP {e.code} {e.read()[:200]!r}") from None;
    }
}

def result(data: dict[str, object]) -> dict[str, object] {
    found = data.get("result");
    return found if isinstance(found, dict) else {};
}

def show_qr(url: str) {
    # segno ships .pyi stubs, which jac check ignores (JD-037): without the cast it types make_qr
    # as returning `object` and refuses the file.
    qr = segno.make_qr(url, error="m") as segno.QRCode;
    qr.terminal(compact=True);
}

def main -> int {
    args = sys.argv[1:];
    https = "--https" in args;
    base = "http://127.0.0.1:8000";
    if "--base" in args {
        base = args[args.index("--base") + 1].rstrip("/");
    }
    try {
        post(base, "/function/app_info", {});
    } except (OSError, RuntimeError) as e {
        print(
            f"Briefly is not answering at {base} ({e}). Start it first: jac run lean"
        );
        return 2;
    }
    user = f"phone-bench-{secrets.token_hex(4)}";
    password = secrets.token_urlsafe(18) + "-Aa1";
    signed = post(
        base,
        "/user/register",
        {
            "identities": [{"type": "username", "value": user}],
            "credential": {"type": "password", "password": password}
        }
    );
    token = str(signed["token"]);
    session = result(post(base, "/function/phone_start", {"tls": https}, token));
    url = str(session["url"]);
    expires = int(str(session["expires_in"]));
    print(f"\nScan this with the phone (the code expires in {expires} s):\n");
    show_qr(url);
    shown = url.split("#")[0];
    print(f"\n  {shown}   (the code follows '#pair=' and is not shown)");
    if https {
        print(f"  certificate fingerprint (SHA-256): {session['fingerprint']}");
    }
    print("\nWaiting for the phone to pair…");
    deadline = time.monotonic() + expires + 5;
    paired = False;
    while time.monotonic() < deadline and not paired {
        time.sleep(1);
        paired = bool(
            result(post(base, "/function/phone_status", {}, token)).get("paired")
        );
    }
    if not paired {
        print("The code expired before a phone paired. Run again for a new one.");
        post(base, "/function/phone_stop", {}, token);
        return 1;
    }
    started = time.monotonic();
    print("Paired. Sending three messages to the phone…");
    for text in [
        "Yesterday I merged the notice expiry fix (PR #12).",
        "Today: the phone link spike.",
        "No blockers."
    ] {
        time.sleep(3);
        post(base, "/function/phone_push", {"text": text}, token);
        print(f"  sent: {text}");
    }
    print(
        "\nNow open the same link on a second device or browser tab: it must say the code was used."
            + "\nNote whether the phone kept its screen on (shown at the bottom of the page)."
    );
    input("Press Enter to end the session… ");
    post(base, "/function/phone_stop", {}, token);
    minutes = (time.monotonic() - started) / 60;
    print(
        f"Session ended after {minutes:.1f} min paired. The phone should say it was disconnected."
    );
    return 0;
}

with entry {
    sys.exit(main());
}
