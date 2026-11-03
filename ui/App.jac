"""The Briefly UI root, shared by the desktop and lean profiles (architecture §6.1)."""

import from core.app_info { AppInfo, app_info }

def:pub App(profile: str) -> JsxElement {
    has info: AppInfo | None = None;
    has failed: bool = False;

    async can with entry {
        try {
            info = await app_info();
        } except Exception {
            failed = True;
        }
    }

    <main style={{"padding": "2rem", "fontFamily": "system-ui, sans-serif"}}>
        <h1>Briefly</h1>
        {(<p>Version {info.version}, {profile} profile</p>)
            if info
            else (
                <p>
                    {"Could not reach the Briefly server." if failed else "Starting…"}
                </p>
            )}
    </main>
}
