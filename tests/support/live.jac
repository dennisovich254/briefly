"""A JacTestClient's app on a real loopback port, and plain HTTP calls to it.

JacTestClient answers requests in-process, with no port and no Host header. The phone link needs
both: the LAN gate forwards to the server's port, and `phone_start` reads that port from the Host
header. So this serves the client's own app (the same endpoints and module state) on 127.0.0.1, as
Jac's testkit does for WebSockets (`ServingTestClient._ensure_live_server`).
"""
import http.client;
import json;
import socket;
import ssl;
import from jaclang.server.serving.server { ServingServer }
import from jaclang.testing.testing { JacTestClient }

glob PASSWORD: str = "Fixture-Pass-7319-xq";

obj Reply {
    has status: int,
        text: str;

    """The function's result (`data.result`), or the whole `data` when there is none."""
    def result -> object {
        data = json.loads(self.text)["data"];
        return data["result"] if "result" in data else data;
    }

    def fields -> dict[str, object] {
        found = self.result();
        return found if isinstance(found, dict) else {};
    }

    def get(name: str) -> str {
        return str(self.fields().get(name, ""));
    }
}

"""Serve the client's app on a free loopback port; returns the port and a stop function."""
def live_server(client: JacTestClient) -> tuple[int, Callable[[], None]] {
    client.get("/healthz");
    server = ServingServer(app=client._app, host="127.0.0.1", port=0);
    stop = server.serve_background();
    return (server.bound_port, stop);
}

"""One HTTP request; TLS without verification when `tls` (the phone's self-signed certificate)."""
def request(
    host: str,
    port: int,
    method: str,
    path: str,
    body: dict[str, object] | None = None,
    token: str = "",
    tls: bool = False
) -> Reply {
    conn: http.client.HTTPConnection;
    if tls {
        context = ssl.create_default_context();
        context.check_hostname = False;
        context.verify_mode = ssl.CERT_NONE;
        conn = http.client.HTTPSConnection(host, port, timeout=120, context=context);
    } else {
        conn = http.client.HTTPConnection(host, port, timeout=120);
    }
    headers = {"Content-Type": "application/json"};
    if token {
        headers["Authorization"] = f"Bearer {token}";
    }
    try {
        conn.request(
            method,
            path,
            body=json.dumps(body).encode() if body is not None else None,
            headers=headers
        );
        resp = conn.getresponse();
        return Reply(
            status=resp.status, text=resp.read().decode("utf-8", errors="replace")
        );
    } finally {
        conn.close();
    }
}

"""Call a function endpoint."""
def call(
    host: str,
    port: int,
    name: str,
    body: dict[str, object] | None = None,
    token: str = "",
    tls: bool = False
) -> Reply {
    return request(host, port, "POST", f"/function/{name}", body or {}, token, tls);
}

"""Register a user over HTTP and return its token."""
def sign_up(port: int, username: str) -> str {
    reply = request(
        "127.0.0.1",
        port,
        "POST",
        "/user/register",
        {
            "identities": [{"type": "username", "value": username}],
            "credential": {"type": "password", "password": PASSWORD}
        }
    );
    if reply.status >= 300 {
        raise RuntimeError(f"register failed: {reply.status} {reply.text[:200]}");
    }
    return reply.get("token");
}

"""Whether anything accepts a TCP connection on host:port."""
def accepts(host: str, port: int) -> bool {
    try {
        socket.create_connection((host, port), timeout=2).close();
        return True;
    } except OSError {
        return False;
    }
}
