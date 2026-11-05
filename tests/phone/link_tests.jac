"""The phone link over HTTP (plan 1.5, spike S7; architecture §5.6).

The app runs on a real loopback port (tests/support/live.jac); the gate listens on 127.0.0.2, which
stands in for the LAN address (Linux routes all of 127.0.0.0/8 to the loopback interface).
"""
import hashlib;
import http.client;
import json;
import os;
import re;
import socket;
import ssl;
import tempfile;
import threading;
import time;
import urllib.parse;
import from jaclang.testing.testing { JacTestClient }
import from tests.support.live { Reply, accepts, call, live_server, request, sign_up }

glob LAN: str = "127.0.0.2";

obj Rig {
    has client: JacTestClient,
        port: int,
        stop: Callable[[], None],
        token: str;

    def laptop(name: str, body: dict[str, object] | None = None) -> Reply {
        return call("127.0.0.1", self.port, name, body, self.token);
    }

    def close {
        self.laptop("phone_stop");
        self.stop();
        self.client.close();
    }
}

def rig(base: str, pair_ttl: int = 120) -> Rig {
    os.environ["BRIEFLY_PHONE_HOST"] = LAN;
    os.environ["BRIEFLY_PHONE_PORT"] = "0";
    os.environ["BRIEFLY_PHONE_PAIR_TTL_SECONDS"] = str(pair_ttl);
    os.environ.pop("BRIEFLY_PHONE_LISTENER", None);
    client = JacTestClient.from_file(
        os.path.join(os.getcwd(), "main.jac"), base_path=base
    );
    (port, stop) = live_server(client);
    return Rig(client=client, port=port, stop=stop, token=sign_up(port, "standup"));
}

obj Session {
    has host: str,
        port: int,
        code: str,
        fingerprint: str;
}

def start(r: Rig, tls: bool = False) -> Session {
    reply = r.laptop("phone_start", {"tls": tls});
    assert reply.status == 200 , f"phone_start: {reply.status} {reply.text[:300]}";
    url = urllib.parse.urlsplit(reply.get("url"));
    assert url.fragment.startswith("pair=") , reply.text;
    assert url.hostname is not None and url.port is not None , reply.text;
    return Session(
        host=url.hostname,
        port=url.port,
        code=url.fragment[len("pair="):],
        fingerprint=reply.get("fingerprint")
    );
}

def pair(s: Session, code: str) -> Reply {
    return call(s.host, s.port, "phone_pair", {"code": code});
}

def device_token(s: Session, code: str) -> str {
    reply = pair(s, code);
    assert reply.status == 200 , f"pairing: {reply.status} {reply.text[:300]}";
    return reply.get("token");
}

test "the laptop's phone controls need a signed-in client" {
    with tempfile.TemporaryDirectory() as base {
        r = rig(base);
        try {
            for name in [
                "phone_start",
                "phone_stop",
                "phone_status",
                "phone_push",
                "phone_new_code"
            ] {
                reply = call("127.0.0.1", r.port, name, {"text": "x", "tls": False});
                assert reply.status == 401 , f"{name}: {reply.status} {reply.text[:200]}";
            }
        } finally {
            r.close();
        }
    }
}

test "the LAN listener exists only while a session is active" {
    with tempfile.TemporaryDirectory() as base {
        r = rig(base);
        try {
            status = r.laptop("phone_status").fields();
            assert not status["active"] and not status["listening"] , status;
            assert not accepts(LAN, r.port) , "the server itself must not listen on the LAN address";
            s = start(r);
            assert s.host == LAN , s.host;
            assert accepts(LAN, s.port) , "the gate should listen during the session";
            assert r.laptop("phone_status").fields()["listening"];
            assert r.laptop("phone_stop").result() is True;
            assert not accepts(LAN, s.port) , "the gate must close when the session ends";
            assert not r.laptop("phone_status").fields()["listening"];
        } finally {
            r.close();
        }
    }
}

test "the gate lets through only the phone page and the phone endpoints" {
    with tempfile.TemporaryDirectory() as base {
        r = rig(base);
        try {
            s = start(r);
            page = request(s.host, s.port, "GET", "/phone");
            assert page.status == 200;
            scripts = re.findall(r'<script[^>]* src="([^"]+)"', page.text);
            assert scripts , page.text[:400];
            for src in scripts {
                assert request(s.host, s.port, "GET", src).status == 200 , f"the page's {src}";
            }
            for (method, path) in [
                ("GET", "/"),
                ("GET", "/docs"),
                ("GET", "/graph"),
                ("GET", "/admin"),
                ("GET", "/openapi.json"),
                ("GET", "/boundaries.json"),
                ("GET", "/healthz"),
                ("POST", "/user/register"),
                ("POST", "/user/login"),
                ("POST", "/function/phone_start"),
                ("POST", "/function/phone_push"),
                ("POST", "/function/answer_stream"),
                ("GET", "/static/../docs"),
                ("GET", "/static/%2e%2e/docs")
            ] {
                reply = request(
                    s.host, s.port, method, path, {} if method == "POST" else None
                );
                assert reply.status == 404 , f"{method} {path}: {reply.status} {reply.text[:120]}";
            }
        } finally {
            r.close();
        }
    }
}

test "a code pairs one device; a second device with it is refused" {
    with tempfile.TemporaryDirectory() as base {
        r = rig(base);
        try {
            s = start(r);
            assert device_token(s, s.code);
            again = pair(s, s.code);
            assert again.status == 403 , f"{again.status} {again.text[:200]}";
            assert pair(s, "made-up-code").status == 403;
            assert call(s.host, s.port, "phone_feed", {"token": ""}).status == 401;
            made_up = call(s.host, s.port, "phone_feed", {"token": "made-up"});
            assert made_up.status == 401;
        } finally {
            r.close();
        }
    }
}

test "an expired pairing code is refused" {
    with tempfile.TemporaryDirectory() as base {
        r = rig(base, pair_ttl=1);
        try {
            s = start(r);
            time.sleep(2.5);
            late = pair(s, s.code);
            assert late.status == 403 , f"{late.status} {late.text[:200]}";
        } finally {
            r.close();
        }
    }
}

test "a new device needs the laptop's approval, which revokes the first" {
    with tempfile.TemporaryDirectory() as base {
        r = rig(base);
        try {
            s = start(r);
            first = device_token(s, s.code);
            fresh = r.laptop("phone_new_code");
            code = urllib.parse.urlsplit(fresh.get("url")).fragment[len("pair="):];
            second = device_token(s, code);
            assert second != first;
            stale = call(s.host, s.port, "phone_feed", {"token": first});
            assert stale.status == 401 , f"{stale.status} {stale.text[:200]}";
        } finally {
            r.close();
        }
    }
}

"""Read SSE frames from the phone feed in a thread, into `frames`, until the stream closes."""
def read_feed(
    s: Session, token: str, frames: list[dict[str, object]], tls: bool = False
) {
    conn: http.client.HTTPConnection;
    if tls {
        context = ssl.create_default_context();
        context.check_hostname = False;
        context.verify_mode = ssl.CERT_NONE;
        conn = http.client.HTTPSConnection(s.host, s.port, timeout=30, context=context);
    } else {
        conn = http.client.HTTPConnection(s.host, s.port, timeout=30);
    }
    try {
        conn.request(
            "POST",
            "/function/phone_feed",
            body=json.dumps({"token": token}).encode(),
            headers={"Content-Type": "application/json"}
        );
        resp = conn.getresponse();
        while True {
            line = resp.readline();
            if not line {
                break;
            }
            text = line.decode().strip();
            if text.startswith("data: ") {
                frames.append(json.loads(text[6:]));
            }
        }
    } except (OSError, http.client.HTTPException) {} finally {
        conn.close();
    }
}

def wait_for(
    frames: list[dict[str, object]], kind: str, seconds: float = 10.0
) -> bool {
    deadline = time.monotonic() + seconds;
    while time.monotonic() < deadline {
        if any([f.get("type") == kind for f in frames]) {
            return True;
        }
        time.sleep(0.05);
    }
    return False;
}

test "the paired phone receives what the laptop sends, and ending the session cuts it off" {
    with tempfile.TemporaryDirectory() as base {
        r = rig(base);
        try {
            s = start(r);
            token = device_token(s, s.code);
            frames: list[dict[str, object]] = [];
            reader = threading.Thread(
                target=read_feed, args=(s, token, frames), daemon=True
            );
            reader.start();
            assert wait_for(frames, "paired") , frames;
            pushed = r.laptop("phone_push", {"text": "PR #12 merged the expiry fix."});
            assert pushed.result() is True;
            assert wait_for(frames, "message") , frames;
            texts = [
                f["text"]
                for f in frames
                if f["type"] == "message"
            ];
            assert texts == ["PR #12 merged the expiry fix."] , texts;
            r.laptop("phone_stop");
            reader.join(timeout=10);
            assert not reader.is_alive() , "the feed must end with the session";
            assert not accepts(LAN, s.port);
        } finally {
            r.close();
        }
    }
}

test "with tls the gate serves HTTPS with the certificate whose fingerprint the laptop shows" {
    with tempfile.TemporaryDirectory() as base {
        previous = os.environ.get("XDG_DATA_HOME");
        os.environ["XDG_DATA_HOME"] = os.path.join(base, "data");
        r = rig(base);
        try {
            s = start(r, tls=True);
            assert len(s.fingerprint.split(":")) == 32 , s.fingerprint;
            context = ssl.create_default_context();
            context.check_hostname = False;
            context.verify_mode = ssl.CERT_NONE;
            with socket.create_connection((s.host, s.port), timeout=10) as raw {
                with context.wrap_socket(raw) as tls_sock {
                    der = tls_sock.getpeercert(binary_form=True);
                }
            }
            assert der is not None;
            seen = hashlib.sha256(der).hexdigest().upper();
            assert seen == s.fingerprint.replace(":", "") , f"{seen} != {s.fingerprint}";
            assert request(s.host, s.port, "GET", "/phone", tls=True).status == 200;
            paired = call(s.host, s.port, "phone_pair", {"code": s.code}, tls=True);
            assert paired.status == 200 , f"{paired.status} {paired.text[:200]}";
            token = paired.get("token");
            frames: list[dict[str, object]] = [];
            reader = threading.Thread(
                target=read_feed, args=(s, token, frames, True), daemon=True
            );
            reader.start();
            assert wait_for(frames, "paired") , frames;
            r.laptop("phone_stop");
            reader.join(timeout=10);
            assert not reader.is_alive();
        } finally {
            r.close();
            if previous is None {
                os.environ.pop("XDG_DATA_HOME", None);
            } else {
                os.environ["XDG_DATA_HOME"] = previous;
            }
        }
    }
}
