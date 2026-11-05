"""The phone companion page (architecture §5.6; plan 1.5, spike S7).

Opened from the laptop's QR code: the link carries a one-time pairing code after `#pair=`, which a
browser never sends to a server. The page takes the code out of the address bar, redeems it for a
device token kept only in this component's memory (never in storage), and shows what the laptop
sends over `phone_feed`, one message at a time in large type. It asks for a screen wake lock, which
browsers grant only to secure (HTTPS) pages: the spike records whether the phone kept it.
"""
import from core.phone.link { phone_pair }

def:pub Phone -> JsxElement {
    has status: str = "Pairing…",
        latest: str = "",
        earlier: list[str] = [],
        awake: str = "";

    async can with entry {
        hash = String(window.location.hash);  # jac:ignore[W2001]
        code = hash[6:] if hash.startswith("#pair=") else "";
        window.history.replaceState(None, "", "/phone");  # jac:ignore[W2001]
        if not code {
            status = "Scan the QR code on the laptop to pair.";
            return;
        }
        token = "";
        try {
            pairing = await phone_pair(code);
            token = pairing.token if pairing else "";
        } except Exception {
            token = "";
        }
        if not token {
            status = "This code has expired or was already used. Ask the laptop for a new one.";
            return;
        }
        try {
            # The checker's navigator type has no wakeLock yet; the browser API exists.
            await navigator.wakeLock.request("screen");  # jac:ignore[E1030, W1051]
            awake = "Screen kept on.";
        } except Exception {
            awake = "This browser will not keep the screen on over plain HTTP.";
        }
        status = "Paired. Waiting for the laptop…";
        resp = await fetch(  # jac:ignore[W2001]
            "/function/phone_feed",
            {
                "method": "POST",
                "headers": {"Content-Type": "application/json"},
                "body": JSON.stringify({"token": token})  # jac:ignore[W2001]
            }
        );
        if not resp.ok {
            status = "The laptop refused this phone. Pair again from the laptop.";
            return;
        }
        reader = resp.body.getReader();
        decoder = new(TextDecoder);  # jac:ignore[W2001]
        nl = chr(10);
        buf = "";
        shown = "";
        history: list[str] = [];
        reading = True;
        ending = "The session has ended.";
        while reading {
            try {
                part = await reader.read();
            } except Exception {
                # The laptop closes the LAN listener when the session ends, cutting the stream.
                ending = "Disconnected from the laptop. The session has ended.";
                reading = False;
                continue;
            }
            if part.done {
                reading = False;
                continue;
            }
            buf = buf + decoder.decode(part.value, {"stream": True});
            frames = buf.split(nl + nl);
            buf = frames.pop();
            for frame in frames {
                for line in frame.split(nl) {
                    if line.startswith("data: ") and not frame.startswith("event:") {
                        event: dict[str, str] = JSON.parse(line[6:]);  # jac:ignore[W2001, E1001]
                        if event["type"] == "message" {
                            if shown {
                                history = [shown] + history;
                            }
                            shown = event["text"];
                            latest = shown;
                            earlier = history;
                            status = "Paired";
                        } elif event["type"] == "ended" {
                            reading = False;
                        }
                    }
                }
            }
        }
        status = ending;
    }

    <main
        style={{
            "padding": "1.5rem",
            "fontFamily": "system-ui, sans-serif",
            "maxWidth": "40rem",
            "margin": "0 auto"
        }}
    >
        <p style={{"fontSize": "1rem", "opacity": 0.7}}>{status}</p>
        <p style={{"fontSize": "2rem", "lineHeight": 1.3}}>{latest}</p>
        {[
            <p key={i} style={{"fontSize": "1.1rem", "opacity": 0.6}}>{text}</p>
            for (i, text) in enumerate(earlier)
        ]}
        <p style={{"fontSize": "0.9rem", "opacity": 0.5}}>{awake}</p>
    </main>
}
