"""The phone's way in: a listener on the LAN address that exists only while a session is active (§5.6).

A Jac server listens on one address for its whole life, and the desktop host only on loopback
(JD-035), so Briefly cannot open and close a LAN listener through Jac. The gate is that listener: it
accepts on the LAN address, lets through only what the phone needs (its page, the page's bundle and
the phone endpoints), and forwards each request to the loopback server with `Connection: close`.
Everything else, Jac's own surfaces included (`/user/register`, `/docs`, `/graph`, `/admin`), gets
404 from the gate and never reaches the server. Stopping the gate closes the listener and cuts every
open connection, a streaming one included. With a TLS context it serves HTTPS on the LAN side only.

Behind the `BRIEFLY_PHONE_LISTENER` switch (core/phone/link.jac): `gate` (default) or `jac`.
"""
import re;
import socket;
import ssl;
import threading;

glob MAX_HEAD_BYTES: int = 16384,
     MAX_BODY_BYTES: int = 65536,
     IO_TIMEOUT: float = 30.0,
     PHONE_ENDPOINTS: list[str] = ["/function/phone_pair", "/function/phone_feed"],
     # The page's bundle: under /static/ when served from a .jab, a root-level hashed file such as
     # /client.vPIDIAF_.js when served from source or by the desktop host.
     STATIC_PATH: re.Pattern[str] = re.compile(
         r"^/static/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$"
     ),
     BUNDLE_FILE: re.Pattern[str] = re.compile(
         r"^/[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*\.(js|css)$"
     ),
     # Hop-by-hop headers, and the ones a client must not choose for the server (forwarding).
     DROPPED_HEADERS: list[str] = [
         "connection",
         "keep-alive",
         "proxy-connection",
         "te",
         "trailer",
         "upgrade",
         "forwarded",
         "x-forwarded-for",
         "x-forwarded-host",
         "x-forwarded-proto",
         "x-real-ip"
     ];

"""Whether the gate lets a request through: the phone page, its bundle, and the phone endpoints."""
def allowed(method: str, target: str) -> bool {
    path = target.split("?", 1)[0];
    if ".." in path or "%" in path or "\\" in path {
        return False;
    }
    if method == "GET" {
        return (
            path == "/phone"
            or STATIC_PATH.match(path) is not None
            or BUNDLE_FILE.match(path) is not None
        );
    }
    return method == "POST" and path in PHONE_ENDPOINTS;
}

obj Head {
    has method: str,
        target: str,
        version: str,
        headers: list[tuple[str, str]],
        rest: bytes;
}

"""Read a request head (up to the blank line); None if it is malformed, too long or never arrives."""
def read_head(conn: socket.socket) -> Head | None {
    buf = b"";
    while b"\r\n\r\n" not in buf {
        if len(buf) > MAX_HEAD_BYTES {
            return None;
        }
        chunk = conn.recv(4096);
        if not chunk {
            return None;
        }
        buf = buf + chunk;
    }
    (head, rest) = buf.split(b"\r\n\r\n", 1);
    lines = head.decode("latin-1").split("\r\n");
    parts = lines[0].split(" ");
    if len(parts) != 3 or not parts[2].startswith("HTTP/1.") {
        return None;
    }
    headers: list[tuple[str, str]] = [];
    for line in lines[1:] {
        if ":" not in line {
            return None;
        }
        (name, value) = line.split(":", 1);
        headers.append((name.strip(), value.strip()));
    }
    return Head(
        method=parts[0], target=parts[1], version=parts[2], headers=headers, rest=rest
    );
}

def header_value(head: Head, name: str) -> str | None {
    for (key, value) in head.headers {
        if key.lower() == name {
            return value;
        }
    }
    return None;
}

def refuse(conn: socket.socket, status: str) {
    body = status.encode("latin-1");
    conn.sendall(
        b"HTTP/1.1 "
            + body
            + b"\r\nContent-Type: text/plain\r\nContent-Length: "
            + str(len(body)).encode("latin-1")
            + b"\r\nConnection: close\r\n\r\n"
            + body
    );
}

obj Gate {
    has host: str,
        upstream_port: int,
        port: int = 0,
        tls: ssl.SSLContext | None = None,
        _sock: socket.socket | None = None,
        _conns: set[socket.socket] = set(),
        _lock: threading.Lock = threading.Lock(),
        _acceptor: threading.Thread | None = None,
        _open: bool = False;

    """Listen on host:port (0 picks a free port); returns the bound port."""
    def start -> int {
        sock = socket.create_server((self.host, self.port), reuse_port=False);
        sock.settimeout(0.5);
        self._sock = sock;
        self._open = True;
        self.port = sock.getsockname()[1];
        self._acceptor = threading.Thread(target=self._accept_loop, daemon=True);
        self._acceptor.start();
        return self.port;
    }

    """Close the listener and cut every open connection; returns once nothing listens."""
    def stop {
        self._open = False;
        if self._sock is not None {
            # A close alone leaves the socket listening until a pending accept() returns: shut it
            # down first, which wakes that accept(), then wait for the accept loop to end.
            try {
                self._sock.shutdown(socket.SHUT_RDWR);
            } except OSError {}
            self._sock.close();
            self._sock = None;
        }
        if self._acceptor is not None {
            self._acceptor.join(timeout=5);
            self._acceptor = None;
        }
        with self._lock {
            conns = list(self._conns);
            self._conns.clear();
        }
        for conn in conns {
            try {
                conn.shutdown(socket.SHUT_RDWR);
            } except OSError {}
            conn.close();
        }
    }

    def is_open -> bool {
        return self._open;
    }

    def _accept_loop {
        while self._open and self._sock is not None {
            try {
                (conn, _) = self._sock.accept();
            } except TimeoutError {
                continue;
            } except OSError {
                return;
            }
            threading.Thread(target=self._serve, args=(conn, ), daemon=True).start();
        }
    }

    def _track(conn: socket.socket) -> bool {
        with self._lock {
            if not self._open {
                return False;
            }
            self._conns.add(conn);
            return True;
        }
    }

    def _forget(conn: socket.socket) {
        with self._lock {
            self._conns.discard(conn);
        }
        try {
            conn.close();
        } except OSError {}
    }

    def _serve(raw: socket.socket) {
        raw.settimeout(IO_TIMEOUT);
        conn = raw;
        if not self._track(raw) {
            raw.close();
            return;
        }
        upstream: socket.socket | None = None;
        try {
            if self.tls is not None {
                conn = self.tls.wrap_socket(raw, server_side=True);
                self._track(conn);
            }
            head = read_head(conn);
            if head is None {
                refuse(conn, "400 Bad Request");
                return;
            }
            if not allowed(head.method, head.target) {
                refuse(conn, "404 Not Found");
                return;
            }
            if header_value(head, "transfer-encoding") is not None {
                refuse(conn, "411 Length Required");
                return;
            }
            length = int(header_value(head, "content-length") or "0");
            if length < 0 or length > MAX_BODY_BYTES {
                refuse(conn, "413 Content Too Large");
                return;
            }
            body = head.rest;
            while len(body) < length {
                chunk = conn.recv(min(65536, length - len(body)));
                if not chunk {
                    return;
                }
                body = body + chunk;
            }
            lines = [f"{head.method} {head.target} HTTP/1.1"];
            for (name, value) in head.headers {
                if name.lower() not in DROPPED_HEADERS {
                    lines.append(f"{name}: {value}");
                }
            }
            lines.append("Connection: close");
            upstream = socket.create_connection(
                ("127.0.0.1", self.upstream_port), timeout=IO_TIMEOUT
            );
            self._track(upstream);
            upstream.sendall(
                ("\r\n".join(lines) + "\r\n\r\n").encode("latin-1") + body[:length]
            );
            # A stream (SSE) may stay quiet for long stretches: wait on it without a deadline.
            upstream.settimeout(None);
            while True {
                chunk = upstream.recv(65536);
                if not chunk {
                    break;
                }
                conn.sendall(chunk);
            }
        } except (OSError, ValueError, ssl.SSLError) {} finally {
            if upstream is not None {
                self._forget(upstream);
            }
            self._forget(conn);
            if conn is not raw {
                self._forget(raw);
            }
        }
    }
}
