"""The Briefly UI root, shared by the desktop and lean profiles (architecture §6.1).

`/phone` is the phone companion page (§5.6), the only page the phone's LAN gate serves; every other
path is the laptop's.
"""

import from "@jac/runtime" { Router, Routes, Route }
import from core.app_info { AppInfo, app_info }
import from core.app_opens { AppOpens, record_open }
import from ui.Phone { Phone }

def:pub App(profile: str) -> JsxElement {
    <Router>
        <Routes>
            <Route path="/phone" element={<Phone/>}/>
            <Route path="*" element={<Home profile={profile}/>}/>
        </Routes>
    </Router>
}

def:pub Home(profile: str) -> JsxElement {
    has info: AppInfo | None = None,
        opens: AppOpens | None = None,
        failed: bool = False;

    async can with entry {
        try {
            info = await app_info();
            opens = await record_open();
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
        {(<p>Opened {opens.count} times since {opens.first_opened}</p>)
            if opens
            else None}
    </main>
}
