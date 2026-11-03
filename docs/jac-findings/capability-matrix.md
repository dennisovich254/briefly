# Capability matrix

Each row is a Jac capability Briefly exercises (architecture §21.3). Each compiler release gets a verdict column: **Works**, **Works with workaround**, **Fails**, **Missing**, **Not documented**, or **Not yet exercised**. The **Findings** column links the JD entries behind a verdict. Add a column when the pinned compiler changes (upgrade protocol, §21.5); keep the old columns so the report can show what changed.

| Jac capability | Where the app exercises it | What is checked | Known inputs | 0.39.0 | Findings |
|---|---|---|---|---|---|
| Scaffolding (`jac create`) | S0 | Template builds, passes `jac check` and lint, sensible defaults | JI-009 | Works | JI-009 no longer holds: the `--kind desktop` scaffold is lint-clean and formatted |
| Client UI (JSX components, state, routing) | All screens, desktop and phone | Compile errors, runtime behaviour, hot reload, stale compiled cache | Stale prepared cache note | Works | |
| Native desktop host and window SDK | Desktop window | Size, fullscreen, always-on-top, second window, focus, close/restore, global shortcuts, capture exclusion | Guide documents only title/size/fullscreen/terminate | Works | [JD-003](JD-003-desktop-identifier-gets-another-apps-name.md); window opens and renders (0.3); window SDK not yet exercised (1.3) |
| Desktop SDK (dialogs, backend selection) | Export, onboarding | Positional-argument rule, error messages | Upstream #6675 | Not yet exercised | |
| Server endpoints (`walker:pub`, `def:pub`) | Every command (§11.3) | Auth, input validation, error shapes, binary/text serialisation | JI-033 | Works | |
| Graph persistence and walkers | Evidence model (§8), sessions | Correctness, transactions, schema evolution during development, memory, startup | JI-042 | Not yet exercised | |
| Real-time delivery (host events, WebSockets, streams) | Live answers, transcript | Targeted delivery to one client, latency, reconnect | JI-054 | Not yet exercised | |
| byLLM | Every Claude call (§10) | Streaming, cancellation, timeouts, usage, image input, structured output, errors | | Not yet exercised | `MockLLM` works offline (0.4) but needs litellm and friends installed (+300 MB venv); live calls in 1.4 |
| Codespace placement (server, client, native inference) | Every module (added in 0.4; not in architecture §21.3) | Where modules are placed, whether that matches the guide, correctness of native code | | Works with workaround | [JD-004](JD-004-native-module-crashes-on-optional-datetime.md) |
| Python interoperability | Audio, portals, speech-to-text SDK, keyring | Async and streaming libraries, threads, dependency packaging, C extensions on the embedded runtime | JacPython (#10299) | Not yet exercised | |
| Background and concurrent work | Preparation, audio loop | Long-running tasks, cancellation, not blocking the UI | | Not yet exercised | |
| Several clients of one app | Desktop window plus phone | Per-client auth, LAN binding configuration | | Not yet exercised | |
| Test runner (`jac test`) | Unit, integration, canaries | Strict mode, fixtures, async tests, CI exit codes | JI-001 | Works with workaround | [JD-002](JD-002-test-client-nested-entry.md); JI-001 still holds (a missing local import is a skip with exit 0 unless `JAC_TEST_STRICT=1`, which `scripts/test.sh` sets) |
| Tooling (`jac check`, `jac fmt`, `jac browse`, editor support) | Daily development | Diagnostic quality, formatter safety, browser QA on the desktop UI | `--lintfix` mangling note, JI-045 | Not yet exercised | |
| Build and packaging (`jac build`) | S1, clean VM, every phase | Privilege prompts, CPU requirements, artifact size, launcher, offline start | JI-002, JI-005 | Works with workaround | [JD-001](JD-001-jac-bun-is-ignored.md); JI-005 still holds: the desktop build needs `sudo apt-get install pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev` (re-tested formally in 1.1) |
| Bundled guides | Every phase | Each guide claim used by the project is checked against behaviour | | Not yet exercised | |
| Upgrades | Every new release | Breaking changes, migration of graph data, cache invalidation | | Not yet exercised | |
