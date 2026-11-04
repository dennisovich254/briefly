import os;
import tempfile;
import from datetime { datetime, timezone }
import from jaclang.testing.testing { JacTestClient, TestResponse }
import from core.clock { freeze, reset }

glob T0: datetime = datetime(2026, 3, 2, 9, 30, tzinfo=timezone.utc);

def open_client(base: str) -> JacTestClient {
    return JacTestClient.from_file(
        os.path.join(os.getcwd(), "main.jac"), base_path=base
    );
}

def call(client: JacTestClient, name: str) -> dict[str, object] {
    resp: TestResponse = client.post(f"/function/{name}", json={});
    assert resp.ok , f"{name}: {resp.status_code} {resp.text}";
    return resp.data["result"];
}

test "before the first open the app reports no opens" {
    with tempfile.TemporaryDirectory() as base {
        client = open_client(base);
        try {
            opens = call(client, "app_opens");
            assert opens["count"] == 0 and opens["first_opened"] is None , opens;
        } finally {
            client.close();
        }
    }
}

test "each open is counted and the first one is remembered" {
    with tempfile.TemporaryDirectory() as base {
        client = open_client(base);
        try {
            freeze(T0);
            first = call(client, "record_open");
            second = call(client, "record_open");
            assert first["count"] == 1 and second["count"] == 2 , (first, second);
            assert first["first_opened"] == T0.isoformat() , first;
            assert second["first_opened"] == T0.isoformat() , second;
            assert call(client, "app_opens")["count"] == 2;
        } finally {
            reset();
            client.close();
        }
    }
}

test "the opens survive a restart of the server" {
    with tempfile.TemporaryDirectory() as base {
        client = open_client(base);
        try {
            call(client, "record_open");
        } finally {
            client.close();
        }
        restarted = open_client(base);
        try {
            assert call(restarted, "app_opens")["count"] == 1;
            assert call(restarted, "record_open")["count"] == 2;
        } finally {
            restarted.close();
        }
    }
}
