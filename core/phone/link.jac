"""Pairing a phone with the laptop for one session (architecture §5.6; plan 1.5, spike S7).

The laptop starts a session (`phone_start`): the LAN listener opens and a one-time pairing code is
issued, which the laptop shows in a QR code with the LAN URL. The phone redeems the code
(`phone_pair`) for a device token, kept in the page's memory only, and reads what the laptop sends
over `phone_feed` (SSE). Codes and tokens live in Jac's app-token store: only their hashes are
stored, expiry is enforced by the server, and a code can be redeemed by exactly one caller. One
device per session: pairing revokes every other code, and a second device needs the laptop to issue
a new code (`phone_new_code`), which revokes the first device. `phone_stop` revokes everything and
closes the LAN listener.

The laptop's endpoints are `def:protect`; the phone's are `def:pub` (it holds no account) and check
the device token themselves. The LAN listener is the gate (core/phone/gate.jac), switch
`BRIEFLY_PHONE_LISTENER`:
- `gate` (default): the gate opens on the LAN address for the session (JD-035).
- `jac`: no gate; the URL points at the Jac server's own port, which then has to listen on the LAN
  itself (`JAC_SERVE_HOST=0.0.0.0`, lean profile only, for the whole server's life). Kept to re-test
  the Jac way.

Configuration: `BRIEFLY_PHONE_HOST` (the LAN address; found from the default route when unset),
`BRIEFLY_PHONE_PORT` (default 47913; 0 picks a free port), `BRIEFLY_PHONE_PAIR_TTL_SECONDS`
(default 120).
"""
import hashlib;
import os;
import queue;
import socket;
import ssl;
import subprocess;
import threading;
import uuid;
import from typing { Generator }
import from jaclang.server.exchange { current_request, respond }
import from jaclang.server.identity.app_tokens {
    token_consume,
    token_create,
    token_peek,
    token_revoke
}
import from core.phone.gate { Gate }

glob PAIR_PURPOSE: str = "phone-pair",
     DEVICE_PURPOSE: str = "phone-device",
     DEFAULT_PORT: int = 47913,
     DEFAULT_PAIR_TTL_SECONDS: int = 120,
     DEVICE_TTL_SECONDS: int = 4 * 3600,
     FEED_POLL_SECONDS: float = 1.0,
     FEED_PING_SECONDS: float = 15.0;

obj PhoneSession {
    has url: str,
        code: str,
        expires_in: int,
        scheme: str,
        fingerprint: str = "";
}

obj PhoneStatus {
    has active: bool,
        listening: bool,
        paired: bool,
        url: str = "";
}

obj PhonePairing {
    has token: str;
}

obj LinkState {
    has session_id: str = "",
        gate: Gate | None = None,
        base_url: str = "",
        scheme: str = "http",
        fingerprint: str = "",
        paired: bool = False,
        inbox: queue.Queue[str] = queue.Queue();
}

glob _state: LinkState = LinkState(),
     _lock: threading.Lock = threading.Lock();

"""The laptop's address on the network its default route uses (no packet is sent)."""
def lan_address -> str {
    configured = os.environ.get("BRIEFLY_PHONE_HOST", "");
    if configured {
        return configured;
    }
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM);
    try {
        probe.connect(("192.0.2.1", 9));
        return probe.getsockname()[0];
    } finally {
        probe.close();
    }
}

"""The port the laptop reached this server on: the gate forwards there."""
def own_port -> int {
    request = current_request();
    host = (request.header("host") or "") if request else "";
    if ":" not in host {
        raise ValueError(f"cannot tell the server's port from Host {host!r}");
    }
    return int(host.rsplit(":", 1)[1]);
}

def pair_ttl -> int {
    return int(
        os.environ.get("BRIEFLY_PHONE_PAIR_TTL_SECONDS", str(DEFAULT_PAIR_TTL_SECONDS))
    );
}

def tls_dir -> str {
    data = os.environ.get("XDG_DATA_HOME", "") or os.path.expanduser("~/.local/share");
    return os.path.join(data, "briefly", "phone-tls");
}

"""This install's self-signed certificate (made once, with openssl), as a server context and its fingerprint."""
def tls_context(directory: str) -> tuple[ssl.SSLContext, str] {
    cert = os.path.join(directory, "cert.pem");
    key = os.path.join(directory, "key.pem");
    if not (os.path.exists(cert) and os.path.exists(key)) {
        os.makedirs(directory, mode=0o700, exist_ok=True);
        subprocess.run(
            [
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "ec",
                "-pkeyopt",
                "ec_paramgen_curve:prime256v1",
                "-nodes",
                "-days",
                "825",
                "-subj",
                "/CN=Briefly phone link",
                "-keyout",
                key,
                "-out",
                cert
            ],
            check=True,
            capture_output=True
        );
        os.chmod(key, 0o600);
    }
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);
    context.minimum_version = ssl.TLSVersion.TLSv1_2;
    context.load_cert_chain(cert, key);
    with open(cert) as fh {
        der = ssl.PEM_cert_to_DER_cert(fh.read());
    }
    digest = hashlib.sha256(der).hexdigest().upper();
    return (context, ":".join([digest[i:i + 2] for i in range(0, len(digest), 2)]));
}

def issue_code -> PhoneSession {
    ttl = pair_ttl();
    code = token_create(
        PAIR_PURPOSE,
        subject=_state.session_id,
        ttl_seconds=ttl,
        payload={"session": _state.session_id}
    );
    return PhoneSession(
        url=f"{_state.base_url}/phone#pair={code}",
        code=code,
        expires_in=ttl,
        scheme=_state.scheme,
        fingerprint=_state.fingerprint
    );
}

def end_session {
    if _state.session_id {
        token_revoke(PAIR_PURPOSE, _state.session_id);
        token_revoke(DEVICE_PURPOSE, _state.session_id);
    }
    if _state.gate is not None {
        _state.gate.stop();
    }
    _state.session_id = "";
    _state.gate = None;
    _state.base_url = "";
    _state.fingerprint = "";
    _state.paired = False;
    _state.inbox = queue.Queue();
}

"""Start a phone session: open the LAN listener and issue a pairing code (any earlier session ends)."""
def start_session(upstream_port: int, tls: bool) -> PhoneSession {
    with _lock {
        end_session();
        host = lan_address();
        context: ssl.SSLContext | None = None;
        fingerprint = "";
        if tls {
            (context, fingerprint) = tls_context(tls_dir());
        }
        mode = os.environ.get("BRIEFLY_PHONE_LISTENER", "gate");
        if mode == "jac" {
            port = upstream_port;
        } else {
            wanted = int(os.environ.get("BRIEFLY_PHONE_PORT", str(DEFAULT_PORT)));
            gate = Gate(
                host=host, upstream_port=upstream_port, port=wanted, tls=context
            );
            try {
                port = gate.start();
            } except OSError {
                gate = Gate(
                    host=host, upstream_port=upstream_port, port=0, tls=context
                );
                port = gate.start();
            }
            _state.gate = gate;
        }
        _state.session_id = uuid.uuid4().hex;
        _state.scheme = "https" if tls else "http";
        _state.fingerprint = fingerprint;
        _state.base_url = f"{_state.scheme}://{host}:{port}";
        return issue_code();
    }
}

"""The device token's session, if the token is valid for the current one."""
def device_ok(token: str) -> bool {
    if not token or not _state.session_id {
        return False;
    }
    found = token_peek(DEVICE_PURPOSE, token);
    return found is not None and found["payload"].get("session") == _state.session_id;
}

"""Redeem a pairing code for the session's one device token; None when refused."""
def pair_device(code: str) -> str | None {
    with _lock {
        found = token_consume(PAIR_PURPOSE, code) if code else None;
        if found is None or found["payload"].get("session") != _state.session_id {
            return None;
        }
        if _state.paired {
            return None;
        }
        # Exactly one device: no other code may still be redeemed.
        token_revoke(PAIR_PURPOSE, _state.session_id);
        _state.paired = True;
        return token_create(
            DEVICE_PURPOSE,
            subject=_state.session_id,
            ttl_seconds=DEVICE_TTL_SECONDS,
            payload={"session": _state.session_id}
        );
    }
}

"""What the paired phone receives: `paired`, then each `message`, a `ping` when quiet, and `ended`."""
def feed_frames(token: str) -> Generator[dict[str, object], None, None] {
    inbox = _state.inbox;
    yield {"type": "paired"};
    quiet = 0.0;
    while device_ok(token) {
        try {
            text = inbox.get(timeout=FEED_POLL_SECONDS);
            quiet = 0.0;
            yield {"type": "message", "text": text};
        } except queue.Empty {
            quiet = quiet + FEED_POLL_SECONDS;
            if quiet >= FEED_PING_SECONDS {
                quiet = 0.0;
                yield {"type": "ping"};
            }
        }
    }
    yield {"type": "ended"};
}

"""Laptop: start a phone session. Returns the URL and code for the QR code; `tls` serves HTTPS.

`tls` has no default: an omitted argument would arrive as the text "False", which is truthy (JD-036).
"""
def:protect phone_start(tls: bool) -> PhoneSession {
    return start_session(own_port(), tls);
}

"""Laptop: approve a new device. Revokes the paired one and issues a fresh code."""
def:protect phone_new_code -> PhoneSession | None {
    with _lock {
        if not _state.session_id {
            respond(status=409);
            return None;
        }
        token_revoke(DEVICE_PURPOSE, _state.session_id);
        token_revoke(PAIR_PURPOSE, _state.session_id);
        _state.paired = False;
        return issue_code();
    }
}

"""Laptop: send a line of text to the paired phone (the spike's stand-in for an answer)."""
def:protect phone_push(text: str) -> bool {
    if not _state.paired {
        return False;
    }
    _state.inbox.put(text);
    return True;
}

def:protect phone_status -> PhoneStatus {
    return PhoneStatus(
        active=bool(_state.session_id),
        listening=_state.gate is not None and _state.gate.is_open(),
        paired=_state.paired,
        url=_state.base_url
    );
}

"""Laptop: end the session. Revokes the code and the device token and closes the LAN listener."""
def:protect phone_stop -> bool {
    with _lock {
        was_active = bool(_state.session_id);
        end_session();
        return was_active;
    }
}

"""Phone: redeem the pairing code from the QR code for a device token (403 when refused)."""
def:pub phone_pair(code: str) -> PhonePairing | None {
    token = pair_device(code);
    if token is None {
        respond(status=403);
        return None;
    }
    return PhonePairing(token=token);
}

"""Phone: the session's feed, as SSE (401 without a valid device token)."""
def:pub phone_feed(token: str) {
    if not device_ok(token) {
        respond(status=401);
        return;
    }
    report feed_frames(token);
}
