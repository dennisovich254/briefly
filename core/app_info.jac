"""Basic facts about the running app, for the UI and smoke tests."""

glob APP_NAME: str = "Briefly";
glob APP_VERSION: str = "0.1.0";

obj AppInfo {
    has name: str;
    has version: str;
}

def:pub app_info -> AppInfo {
    return AppInfo(name=APP_NAME, version=APP_VERSION);
}
