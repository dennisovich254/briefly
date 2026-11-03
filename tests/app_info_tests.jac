import os;
import tempfile;
import tomllib;
import from jaclang.testing.testing { JacTestClient }
import from core.app_info { AppInfo, APP_NAME, APP_VERSION, app_info }

test "app_info reports the app name and version" {
    info: AppInfo = app_info();
    assert info.name == "Briefly";
    assert info.version == APP_VERSION;
}

test "the version in code matches jac.toml" {
    with open(os.path.join(os.getcwd(), "jac.toml"), "rb") as fh {
        project = tomllib.load(fh)["project"];
    }
    toml_version = project["version"];
    assert APP_VERSION == toml_version , f"{APP_VERSION} != jac.toml {toml_version}";
    assert APP_NAME.lower() == project["name"];
}

test "app_info is served over HTTP by the lean profile" {
    with tempfile.TemporaryDirectory() as base {
        client = JacTestClient.from_file(
            os.path.join(os.getcwd(), "main.jac"), base_path=base
        );
        try {
            resp = client.post("/function/app_info", json={});
            assert resp.ok , f"{resp.status_code}: {resp.text}";
            assert resp.data["result"]["name"] == "Briefly" , resp.data;
            assert resp.data["result"]["version"] == APP_VERSION , resp.data;
        } finally {
            client.close();
        }
    }
}
