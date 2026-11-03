# Briefly — Implementation Plan

> **Status:** Draft v1 (2026-11-03), awaiting approval
> **Architecture reference:** `docs/architecture.md` v0.3.1 ("§n" below means a section of that document)
> **Stack:** Jac 0.39.0 (pinned), native Jac desktop target (WebKitGTK) plus a lean `jac run` profile, Jac graph on the embedded PostgreSQL, Claude via byLLM, cloud streaming speech-to-text, read-only GitHub
> **Effort:** about 5–8 engineer-weeks to the final evaluation report (§17), contingent on phase 1

---

## 1. Context

Briefly is an Ubuntu standup assistant. Before a meeting it builds a standup brief and likely follow-up questions with answers from local Git and GitHub history. During the meeting it listens to the other participants and shows short, evidence-backed answers privately on the developer's paired phone (§1).

The project has **two purposes of equal weight** (§1), and this plan delivers both:

1. **The product:** a standup assistant the owner uses in real standups.
2. **The evaluation:** a reproducible record of how well Jac builds a real desktop app. Every shortcoming becomes a JD-NNN finding with a repro, a canary test, measurements and a report (§21).

Three rules from the architecture shape every sub-phase:

- **Jac first (§21.2).** Use Jac's own way first: the desktop target, graph persistence, walkers, byLLM, the Jac client UI, `jac test`, `jac build`. A workaround comes only after its finding is logged, sits behind a named switch (`store=files`, `llm=sdk`, …), cites the finding ID in a comment, and keeps the Jac path buildable and covered by a canary.
- **4 GB laptop first (§3.1, §13).** Every feature is checked against the memory budget: about 300 MB idle and 600 MB in a meeting for the desktop profile, 200/500 MB for the lean profile.
- **Preparation is the main feature (§10.4).** The first milestone is *one repository → prepared brief and Q&A in the graph → typed question answered on the desktop window and the phone* (§17.1). Audio comes after that path is proven.

**Mapping to the architecture's delivery phases (§17).** The architecture's phase 0 is split into two phases here: tooling (phase 0) and spikes (phase 1). Its phase 1 (preparation) becomes phases 2–4, its phase 2 (live assistance) becomes phase 5, and its phase 3 (evaluation report) becomes phase 6.

---

## 2. How we work (applies to every sub-phase)

### 2.1 The loop: one sub-phase = one PR, merged before the next starts

```text
1. Branch      git switch -c feat/p<phase>.<sub>-<slug>       (e.g. feat/p3.1-git-collector)
2. RED         Write the sub-phase's tests (listed in this plan). Run scripts/test.sh → they FAIL for the right reason.
               Commit: "test(p3.1): snapshot retries on HEAD change"
3. GREEN       Implement the minimum to pass. scripts/test.sh → all green (new and all earlier tests).
4. REFACTOR    Clean up with tests green. `jac check` every new or changed .jac file.
5. GATE        Local: pre-commit and pre-push hooks pass. Manual gates for the sub-phase are run and their results committed.
6. PUSH + PR   git push -u origin <branch>; open a PR. Every required CI check must pass.
7. MERGE       The owner reviews and squash-merges; Claude never merges. Tick the box in this file in the same PR.
8. NEXT        Only after the merge: git switch main && git pull, then start the next sub-phase.
```

Until CI exists (sub-phase 0.6), step 6 relies on the local gates only. Spike sub-phases (phase 1) write their pass criteria as test or `bench/` scripts first; the RED step is a script that fails because the measurement or capability is not there yet.

A sub-phase that turns out too large is split into lettered parts (`3.3a`, `3.3b`), each with its own PR. The plan is updated in the first of them.

### 2.2 Definition of Done (per sub-phase)

- [ ] Every test in the sub-phase's **T** list exists and passes, and no earlier test regressed.
- [ ] `jac fmt --check .`, the lint script and `jac check` are clean (or within the warnings baseline from 0.5).
- [ ] **Jac evaluation:** every Jac capability the sub-phase touched has its row in the capability matrix (`docs/jac-findings/capability-matrix.md`, §21.3) updated with a verdict and the compiler version.
- [ ] **Jac evaluation:** every Jac problem hit is either logged as a JD finding meeting the entry criteria (§21.4: minimal repro in `~/jac-repros/JD-NNN/`, outside this repo) or noted in the PR as the project's own mistake. Time lost goes in the finding's **Cost** field.
- [ ] Every workaround cites its finding ID, sits behind a named switch, and has a canary in `tests/canaries/` (or a `bench/` check when it cannot be unit-tested) (§21.5).
- [ ] Non-Jac code added is either at a documented OS/SDK boundary (PipeWire, D-Bus portals, Secret Service, the speech-to-text SDK) or cites a finding ID (§6.3).
- [ ] Security-relevant behaviour (binding, auth, Origin checks, egress) is tested against a **running server over HTTP**, not only through function calls. This is the AfriCinemas P0.7 lesson: config-level tests passed while `/docs` and `/graph` stayed public.
- [ ] UI sub-phases: the flow is checked on the desktop window **and** the phone view (`jac browse` first, per Jac-first; see §2.3), with screenshots attached to the PR.
- [ ] Measured sub-phases: numbers recorded with the §21.6 protocol in `bench/results/`, without repository names, paths or source text (§15).
- [ ] Docs updated: this file's checkbox, plus an ADR in `docs/adr/` if a decision was made.

### 2.3 Test pyramid and where tests live

| Layer | Tool | Location | Runs in |
|---|---|---|---|
| Unit (attribution rules, policy, budgets, state machines, ranking, redaction) | `jac test`, `.test.jac` annexes | beside the module in `core/` | pre-push, CI |
| Collector contracts (Git fixture repos built per test in a temp dir) | `jac test` + fixture builder | `tests/collectors/` | pre-push, CI |
| GitHub contracts (recorded responses, pagination, rate limits, ETags) | `jac test` with a fake HTTP layer | `tests/github/` | CI; opt-in live run on a test repository |
| Server and security (loopback binding, auth, Host/Origin, pairing, single device) | real `jac run` server over HTTP | `tests/server/` | CI |
| AI (prompt building, answer contract, citation validation, cancellation) | byLLM `MockLLM` (no network, no key) | `tests/ai/` | CI |
| Evaluation set (30 questions, then 100) | scoring script against the owner's repositories | **outside this repo** (it is public); only scores are committed | manual, per phase |
| Canaries (one per open testable finding, `jd_NNN_*.jac`) | `jac test` | `tests/canaries/` | pre-push, CI |
| UI (desktop window and phone view) | `jac browse` first; Playwright only after a logged finding shows `jac browse` cannot do it | `tests/ui/` | CI where headless works; manual otherwise |
| Measurements (RSS per process, CPU, startup, build size) | shell scripts on the owner's laptop | `bench/` | manual gate, results committed |
| Packaging (clean-VM install, offline start) | scripted checklist | `bench/install_check.sh` | manual gate per phase |

Rules (from the Jac testing guide and AfriCinemas): never name files `test_*.jac`; each test builds its own data and temp directories; run tests through `scripts/test.sh`, which sets `JAC_TEST_STRICT=1` so a missing local import fails instead of being skipped (JI-001); never call a real Claude, speech-to-text or GitHub API in CI.

### 2.4 Conventions

- **Commits:** Conventional Commits (`feat|fix|test|refactor|docs|chore|ci|bench(scope): …`), enforced by a commit-msg hook and a PR-title check.
- **Branches:** `feat/…`, `fix/…`, `chore/…`, `docs/…`, `spike/…`. No direct commits to `main` from 0.5 on.
- **Decisions:** ADRs in `docs/adr/NNNN-title.md`. The proposed decisions A01–A17 (§18) are promoted, amended or rejected by the spike that validates them.
- **Findings:** `docs/jac-findings/JD-NNN-<slug>.md` using the §21.4 template, indexed in `docs/jac-findings/README.md`. Upstream issues are drafted in the entry and posted only after the owner reviews them.
- **Secrets:** Claude, speech-to-text and GitHub credentials live in the OS keyring (§14.3); for development, `.env` (git-ignored) with `.env.example` listing names only. Never in `jac.toml`.
- **Public repository:** the repo is public. Nothing from the owner's work repositories (names, paths, code, transcripts, evaluation questions) is committed. Fixtures are synthetic.

### 2.5 When a new Jac release appears

A compiler release interrupts the plan with one extra sub-phase, `chore/jac-<version>`, taken **between** sub-phases, never in the middle of one. It follows the upgrade protocol (§21.5): read the release notes, bump `.jac-version`, clear compiled caches, run `jac check` and the full suite with canaries, build and install the desktop artifact on the clean VM, run the measurements, update finding statuses and matrix verdicts, and write the release report. The owner decides whether to take the upgrade now or after the current phase.

---

## 3. Target repository layout

The layout follows §6.5. Exact entry-point names follow `jac create` output.

```text
briefly/
├── AGENTS.md                   # how to work in this repo (points at this plan and the Jac-first rule)
├── .jac-version                # pinned compiler version, single source of truth (0.1)
├── jac.toml                    # workspace: [apps.desktop] (kind desktop) and [apps.lean] (kind web-app), switches
├── main.jac
├── core/                       # shared domain: workspace/ collectors/ evidence/ retrieval/ sessions/ ai/
│                               #   audio/ relevance/ screen/ privacy/ observability/
├── adapters/                   # .py modules at OS/SDK boundaries only (PipeWire, portals, keyring, STT SDK)
├── ui/                         # onboarding, preparation, laptop status page, settings
├── ui/companion/               # phone view and pairing
├── hosts/desktop/  hosts/lean/ # profile wiring only
├── tests/  collectors/ github/ server/ ai/ ui/ canaries/ support/
├── bench/                      # measurement scripts and results/ (§21.6)
├── packaging/ubuntu/
├── scripts/                    # doctor.sh, install_jac.sh, test.sh, lint and hook helpers
├── docs/  architecture.md  IMPLEMENTATION_PLAN.md  adr/  runbooks/
│   └── jac-findings/  README.md  capability-matrix.md  JD-NNN-*.md  reports/
└── .github/  workflows/ci.yml · CODEOWNERS · PULL_REQUEST_TEMPLATE.md · dependabot.yml
```

---

## 4. Phases and sub-phases

Legend: **T** = tests written first (RED), **I** = implementation, **✓** = exit gate. Each sub-phase names the requirement IDs (§2) and sections it implements.

### Phase 0 — Toolchain, scaffold, quality gates (about 3–4 days)

- [x] **0.1 Toolchain doctor and compiler pin**
  - **I:** `.jac-version` = `0.39.0`. `scripts/install_jac.sh` downloads `jac-<version>-linux-x86_64` from the `jaseci-labs/jaseci` release and **requires** its `.sha256` (adapted from AfriCinemas; `jac update --self` does not work for this install). Unlike the AfriCinemas script, it checks the downloaded binary's version *before* replacing the installed one. `scripts/doctor.sh` checks the pinned Jac version, that the bun Jac uses runs on this CPU (the owner's Celeron N4020 has no AVX2, so `JAC_BUN` points at bun's baseline build: JI-002, re-tested in 1.1), Python, Git identity and remote, `.env` ignored, `pre-commit`, `gitleaks` and an authenticated `gh`. `.gitignore` added.
  - **T:** `scripts/toolchain_selftest.sh` (11 checks, offline: releases served from a local directory through `JAC_RELEASE_BASE_URL`, a fake `jac` on PATH): installs on a matching checksum; refuses a mismatched or missing checksum or a binary reporting another version, and installs nothing then; the doctor passes on the pinned version and fails on a wrong or missing `.jac-version`. Mutation-checked: disabling the checksum comparison fails exactly the two checksum tests.
  - **✓** `scripts/doctor.sh` exits 0 on the owner's laptop; a real-network install of 0.39.0 verifies its checksum.
- [ ] **0.2 Findings log and capability matrix** (EV-01, §21.3, §21.4)
  - **I:** `docs/jac-findings/README.md` (index by severity, with status), `TEMPLATE.md` (the §21.4 entry template), `capability-matrix.md` (every §21.3 row, verdict column per compiler version, all "not yet exercised"), `reports/`. The `~/jac-repros/JD-NNN/` convention is documented in the README.
  - **T:** `scripts/check_findings.sh` checks that every `JD-*.md` has the required fields (version, found, category/severity, capability, status, cost) and a valid status; that every *open* finding marked testable has a matching `tests/canaries/jd_NNN_*` file; and that every matrix row is one of the §21.3 verdicts. It runs on a fixture finding (RED: missing fields fail) and on the real empty log (GREEN).
  - **✓** The check passes and is wired into pre-commit in 0.5.
- [ ] **0.3 Scaffold the two-profile workspace** (FR-11, FR-16, FR-17, §6.1)
  - **I:** `jac create briefly --kind desktop` in a temp directory, moved into the repo. Then `jac create --app lean --kind web-app` so both profiles share `core/` and `ui/` (workspace per `jac-project-kinds`). If one workspace cannot hold both kinds over the same UI, that is a finding and the fallback is recorded in an ADR. A `core/health.jac` endpoint returns the app version and active profile. `AGENTS.md` describes the workflow in §2.
  - **T:** a health test through the server; `jac check` on the whole workspace.
  - **✓** `jac check` passes for both apps (warnings in generated code counted, not hidden), `jac test` is green, `jac run lean` serves the page, and `jac run desktop` opens the native window. Template lint issues are logged against JI-009 if they still hold.
- [ ] **0.4 Test harness and fixtures**
  - **I:** `scripts/test.sh` (strict mode, one worker locally, `auto` on CI, `--quick` for pre-push). `tests/support/git_fixtures.jac`: builds throwaway Git repositories in temp directories with a scripted history (commits, branches, worktrees, renames, a detached HEAD, staged and unstaged changes, untracked files, co-authored commits). `core/clock.jac`: domain code uses `clock.now()`, never the system clock directly, so reporting windows are testable. A `MockLLM` fixture for byLLM.
  - **T:** harness self-tests: each fixture repo has the expected `git log`/`git status` output; temp directories are removed; the clock can be frozen and advanced only in tests; a missing local import makes `scripts/test.sh` fail.
  - **✓** Green on two consecutive runs with no temp directories left behind.
- [ ] **0.5 Pre-commit hooks**
  - **I:** `.pre-commit-config.yaml`: whitespace and end-of-file fixers, YAML/TOML/JSON checks, merge-conflict and large-file checks, detect-private-key, `no-commit-to-branch` (`main`), gitleaks (with `pass_filenames: false`, the AfriCinemas fix), `jac fmt --check`, a lint script that fails on any finding (`jac check --lint` exits 0 on findings: JI-010, re-test), `scripts/check_findings.sh`; commit-msg: conventional commits; pre-push: warnings baseline (can only go down) and `scripts/test.sh --quick`.
  - **T:** `scripts/hooks_selftest.sh` builds a throwaway repo and asserts that each gate rejects bad input and accepts clean input.
  - **✓** `pre-commit run --all-files` and the pre-push stage pass.
- [ ] **0.6 GitHub Actions CI**
  - **I:** `.github/workflows/ci.yml` on PRs and pushes to `main`, `permissions: contents: read`, concurrency cancel-in-progress, every action pinned to a full commit SHA, Jac installed by `scripts/install_jac.sh`. Jobs: `pr-title`, `quality` (the pre-commit hooks), `test` (strict, canaries included), `build-desktop` (system packages for the WebKitGTK host cached; JI-005 re-tested), `build-lean`, `security` (gitleaks over history, dependency review). Docs-only PRs skip tests and builds.
  - **T:** the first PR's checks are the test; a deliberately failing commit on a scratch branch shows each required job fails.
  - **✓** All checks green on the PR. **Branch protection:** once the job names are final, Claude shows the owner the exact ruleset and, after the owner approves, applies it with `gh api` (repository ruleset on `main`: PR required, the required checks, linear history, no force-push or deletion; repository settings: squash merges only, delete head branches). Verified by reading the ruleset back and by a direct push to `main` being refused.
- [ ] **0.7 Repository governance files**
  - **I:** `CONTRIBUTING.md` (setup, the §2.1 loop, the Jac-first rule), `SECURITY.md`, `.github/PULL_REQUEST_TEMPLATE.md` (summary, findings touched, screenshots; the Definition of Done stays in this plan), `CODEOWNERS`, `.editorconfig`, `.env.example` (names only), `dependabot.yml` (GitHub Actions only).
  - **T:** `scripts/check_governance.sh`: files exist, `.env.example` names every variable used without values, `.env`, `.claude/` and `bench/private/` are git-ignored. Runs in the `quality` job.
  - **✓** Green in CI.

### Phase 1 — Jac baseline and feasibility spikes (about 1–1.5 weeks)

Each spike writes its pass criteria (§17.1) as a test or `bench/` script first, records the result in an ADR, and logs a finding for anything Jac fails. A failed spike is not a blocker: it switches to the named fallback the same day (§19).

- [ ] **1.1 S0: re-test known inputs** (EV-01, EV-02, §3.2, §17.1)
  - **I:** In `~/jac-repros/`, reproduce on 0.39.0: JI-002 (bundled bun needs AVX2), JI-005 (desktop client build needs sudo), JI-009 (scaffold not lint-clean), JI-019 (mobile pins React 18), JI-033 (binary responses serialised as text), JI-045 (`take` breaks sealing), JI-054 (WebSockets cannot target one client), plus JI-001 (test runner skips missing modules), JI-042 (write after commit re-runs the request; 0.39.0's #10459 may fix it) and the stale prepared-cache note (#10425/#10426 may fix it). Also settle the JacPython question from §3.2: does server code run on JacPython, and does a C-extension package load on its `cpython-314` ABI?
  - **T:** one canary per input that still holds, in `tests/canaries/`; a `bench/` check for the ones that cannot be unit-tested (JI-002, JI-005).
  - **✓** Each input is classified still-holding or fixed in the matrix; still-holding ones have JD entries linking the JI entry, and canaries.
- [ ] **1.2 S1a: desktop artifact and clean install** (FR-16, §16.3)
  - **I:** `jac build desktop` with graph persistence on. A clean Ubuntu 24.04 VM (no checkout, no venv, no compiler). `bench/install_check.sh` installs the artifact, launches it, checks that the window opens, the graph persists across a restart, and the app starts offline; it records every manual step, privilege prompt, missing package and size.
  - **T:** `bench/install_check.sh` fails on the VM before the artifact exists, then passes or reports the exact failing step.
  - **✓** Install steps and sizes recorded; every deviation from "Jac's artifact just works" is a finding.
- [ ] **1.3 S1b: memory, CPU and window SDK** (NFR-01, §13, §21.6)
  - **I:** `bench/mem.sh` measures RSS per process (host, WebKit, embedded server, PostgreSQL) for both profiles, idle and during a 15-minute replayed call with Meet and VS Code open, five runs, median and range, after a reboot. Window SDK checks: size, fullscreen, always-on-top, second window, close/restore (§21.3). Optionally the same measurement with `[desktop] engine = "cef"` for comparison. Confirm that the planned OS adapter packages (D-Bus/portal bindings, keyring client, the STT SDK candidates) install and import under Jac.
  - **T:** `bench/mem.sh` writes a results file and exits non-zero when a §13 budget is missed.
  - **✓** Numbers committed. ADR (A02, A07): which profile is used for daily standups, and whether the lean profile needs `store=files`. A miss is a performance finding with the per-process breakdown.
- [ ] **1.4 S4: byLLM and real-time delivery** (FR-10, §10.1, §11.3)
  - **I:** A spike endpoint that streams a byLLM answer from the configured Claude model to the desktop window and to a browser tab. Check, through byLLM: streaming, cancellation, timeouts, token usage, image input, structured output. Delivery, in the §11.3 order: native desktop-host events, targeted WebSockets, an authenticated response stream. Verify the Claude model IDs available to the owner's key.
  - **T:** `tests/ai/` contract tests with `MockLLM` for structured output and cancellation; a manual `bench/stream_latency.sh` measuring time to first readable sentence over 20 runs.
  - **✓** ADR (A05): which calls stay on byLLM and which move behind `llm=sdk` (each with a finding); the delivery mechanism chosen. Must show the four-second first-useful-output target is reachable or log why not.
- [ ] **1.5 S7: phone link** (FR-08, §5.6)
  - **I:** A spike page served on the LAN only while a flag is on, paired by QR code with a one-time code, on home Wi-Fi and on the phone hotspot; a self-signed HTTPS certificate tried on the owner's phone browser.
  - **T:** server-over-HTTP tests: the listener is loopback-only when no session is active, a second device is refused, an expired code is refused.
  - **✓** ADR (A03): HTTPS practical or hotspot-only rule.
- [ ] **1.6 S3: speech-to-text** (FR-07, §9.3, §9.6)
  - **I:** Capture the meeting-output stream and the microphone as separate PipeWire streams; stream a recorded test call to two or three cloud services and one local small model; feed a vocabulary list. Confirm whether Claude's API accepts live audio.
  - **T:** `bench/stt_score.sh` scores a fixed, consented recording for question-critical entities and WER; capture tests confirm the two streams stay separate.
  - **✓** ADR (A04, A12): default service, with latency, accuracy on names and code terms, retention terms and price recorded.
- [ ] **1.7 S5: screen reading** (FR-15, §9.4)
  - **I:** One frame through the XDG Screenshot portal on GNOME Wayland, downscaled, sent to Claude with a question.
  - **T:** a scripted run on saved frames of code and error text finds the smallest legible size.
  - **✓** ADR (A13): size and latency recorded; portal behaviour logged.
- [ ] **1.8 Baseline report** (EV-03, EV-04, §21.7)
  - **I:** `docs/jac-findings/reports/baseline-0.39.0.md`: matrix verdicts, findings so far, measurement table, profile decision. ADRs A01–A17 promoted, amended or rejected.
  - **✓** The owner reviews the report. **Phase 1 exit gate (§17):** memory, companion display, speech and streaming demonstrated, or findings logged and a daily-use profile chosen.

Spike S2 (screen privacy) is covered by 4.7 for the phone companion; laptop-window modes (FR-08a) are tested only if they are wanted. S6 (evidence fixture) becomes the tests in 3.4.

### Phase 2 — Foundations: graph model, local security, workspaces (about 4–5 days)

- [ ] **2.1 Graph model** (§6.4, §8.1)
  - **I:** `node` archetypes for Workspace, Repository/Worktree, PersonIdentity, Snapshot, Evidence, Commit, PR, Review, Issue, Change, Session, Question, Answer, Claim, Consent/AuditEvent; typed `edge` archetypes (`CONTAINS`, `CHANGES`, `AUTHORED_BY`, `REVIEWED_BY`, `ASSOCIATED_WITH_PR`, `ADDRESSES_ISSUE`, `VERIFIED_AT_SHA`, `DERIVED_FROM`, `SUPPORTED_BY`). The storage interface for `store=files` only if 1.3 required it.
  - **T:** create, traverse and delete along each edge type; persistence across a server restart; a field added to a node with existing data (the first schema-evolution check, a deliberate source of findings).
  - **✓** Green; persistence and migration rows in the matrix have verdicts.
- [ ] **2.2 Local server security** (NFR-02, §11.3, §14.1)
  - **I:** loopback-only binding outside sessions, per-launch credential for the laptop page, exact Host and Origin checks, rejection of untrusted CORS preflights, credentials never in URLs, docs and graph routes off.
  - **T (server over HTTP):** a request with a foreign Origin or a rebinding Host is refused; reads and writes without the credential are refused; `/docs` and `/graph` return 404; a second instance focuses the first instead of opening the database (§15).
  - **✓** Green. Gaps in Jac's endpoint protection are findings.
- [ ] **2.3 Workspace manager** (FR-02, §7.1, §14.2)
  - **I:** approve a root, resolve the repository and Git common directory, identify the worktree, stable internal IDs, exclusion policy (dependencies, build outputs, large binaries, user-denied paths, 1 MiB per-file limit), `local_only` / `claude_allowed` policy per repository, explicit GitHub remote association.
  - **T:** path and symlink escapes are refused; separate worktrees get separate IDs; a source path never counts as permission; with several remotes nothing is associated until the user chooses.
  - **✓** Green.
- [ ] **2.4 Credentials in the OS keyring** (§14.3)
  - **I:** `adapters/keyring.py` over the Secret Service, called from Jac. Locked or missing keyring → session-only credentials or the integration stays off; never plaintext.
  - **T:** a fake Secret Service in tests: store, read, delete; locked keyring path; no credential reaches logs, UI view models or URLs.
  - **✓** Green.
- [ ] **2.5 Onboarding and settings shell** (§12.1)
  - **I:** onboarding screens (select repositories with exclusion preview, cloud policy, Claude key, GitHub token) and a settings page, in both profiles.
  - **T (UI, desktop and lean):** a repository can be approved, its exclusions are previewed, the policy is saved and survives a restart.
  - **✓** Screenshots of both profiles on the PR.

### Phase 3 — Context collection and evidence (about 1 week)

- [ ] **3.1 Git collector** (FR-02, §7.1)
  - **I:** immutable snapshots: HEAD before and after, branch or detached state, upstream, merge/rebase state, recent commits with author and committer, `HEAD → index` and `index → saved files` changes, eligible untracked files after inclusion. Fixed read-only Git argument arrays, `--` separation, NUL-delimited output, bounded output and time, optional locks off, external diff/textconv and fsmonitor disabled.
  - **T (fixture repos from 0.4):** worktrees, rebases, renames, deletions, detached HEAD, untracked files; a HEAD change during collection retries, then marks the snapshot incomplete; a repository hook or textconv helper is never executed (a planted hook writes a marker file that must not appear).
  - **✓** Green.
- [ ] **3.2 Evidence excerpts** (§6.4, §8.2)
  - **I:** evidence stored with repository ID, commit SHA, path, line range and content hash; citations resolve to captured bytes; deleted evidence leaves an unavailable marker.
  - **T:** each §8.2 invariant has a test, including "a citation still resolves after the working tree changes" and "evidence from a denied repository cannot be cited".
  - **✓** Green.
- [ ] **3.3 GitHub connector** (FR-04, §7.3)
  - **I:** fine-grained token from the keyring; serial request queue, pagination, conditional requests with ETags, jittered backoff, rate-limit headers honoured; PRs, reviews, comments, issues, optional checks; `source_updated_at`, `fetched_at` and pagination completeness recorded; refresh at preparation plus manual refresh.
  - **T (recorded responses):** pagination to the end; a 304 reuses the cache; a 403 rate limit waits for reset; a truncated file list produces a coverage warning; a revoked token stops sync and cloud use of the cache; no mutating endpoint is ever called (a fake that fails on any non-GET). One opt-in live test against a synthetic test repository.
  - **✓** Green.
- [ ] **3.4 Identity and attribution** (FR-05, FR-12, §8.4; spike S6)
  - **I:** owner-confirmed identity aliases; roles kept separate (authored, co-authored, reviewed, merged by, assigned, present in worktree); reporting window "since last standup" in the selected timezone; retrieval expansion as a walker over the graph edges.
  - **T (the S6 fixture):** a dirty worktree, a co-authored commit, a squash-merged PR, stale GitHub data and a PR comment with injected instructions. Uncommitted lines are never attributed to the user; email similarity alone never establishes ownership; the injected comment stays data.
  - **✓** Green; walker rows in the matrix have verdicts.
- [ ] **3.5 Secret filter and egress preview** (NFR-02, §14.1, §14.2)
  - **I:** secret-pattern and entropy checks on every outgoing payload, rechecked after cache retrieval; an example-payload preview before the first cloud call; `local_only` repositories never leave the device.
  - **T:** planted secret canaries in fixture repos are never present in any payload built by the AI layer; a `local_only` repository never appears in a payload.
  - **✓** Zero planted secrets transmitted.

### Phase 4 — Preparation and typed Q&A: the first milestone (about 1.5 weeks)

- [ ] **4.1 Claude adapter and budgets** (FR-10, NFR-04, §10.1, §10.5)
  - **I:** byLLM for every call (or `llm=sdk` per the 1.4 ADR); fast and strong model profiles; model IDs verified at setup and recorded with each answer; usage tracked per category (uncached input, cache writes, cache reads, output); daily and monthly caps; cost reserved before dispatch; prices from configuration.
  - **T (MockLLM):** a request over the cap is refused before dispatch; concurrent requests cannot overspend; usage is reconciled; no silent provider substitution.
  - **✓** Green.
- [ ] **4.2 Standup brief** (FR-05, §10.2, §10.4)
  - **I:** collect evidence for the reporting window, generate done / in progress / blockers (user-provided) / next (user-provided) with the strong profile, validate the §10.2 answer contract, save to the graph with the HEAD SHA and GitHub fetch time.
  - **T:** every factual claim has evidence IDs that resolve and are permitted; an unsupported claim is removed or surfaced as an unknown; blockers and next steps are labelled user-provided and never invented.
  - **✓** Green with MockLLM; one real brief generated on a synthetic repository.
- [ ] **4.3 Prepared Q&A and invalidation** (FR-05a, §10.4)
  - **I:** about ten likely follow-up questions per brief item with grounded answers; edit, remove, add before the meeting; a new commit, index change or GitHub update marks affected answers Stale.
  - **T:** a matching question is served from the cache without a Claude call; a commit touching an item's evidence marks only that item's answers stale.
  - **✓** Green.
- [ ] **4.4 Retrieval pipeline** (§8.3)
  - **I:** the eight §8.3 steps: prepared match first, policy filter before search, brief search, `git grep` / `git log --grep` limited to the brief's commits and files, bounded walker expansion, ranking, dedupe and redaction, a token-bounded pack (6,000 of 12,000 tokens) with a coverage manifest.
  - **T:** the pack never exceeds its budget; denied repositories are never searched; exact symbol questions find their hunk. **Bench:** p95 local retrieval ≤ 200 ms on the fixture repositories.
  - **✓** Green and within budget.
- [ ] **4.5 Typed questions with streaming** (FR-06, §10.3, §10.5)
  - **I:** submit, stream as **Draft**, validate citations, then final; generation IDs; cancellation on a new question, correction, revoked scope or Stop; deadlines (4 s target, delayed state at 8 s, abort at 12 s); at most one retry before visible content.
  - **T (MockLLM with scripted streams):** late events from an old generation never change the current answer; text from two retries is never combined; an interrupted stream is labelled interrupted; a cancelled request emits nothing more.
  - **✓** Green; first-readable-sentence latency measured with the real model.
- [ ] **4.6 Preparation and answer UI on the laptop** (FR-12, FR-13, §12)
  - **I:** preparation screen (brief, prepared Q&A to review and edit, freshness, cost estimate), answer view, evidence drawer, the evidence states (Supported, Inference, Conflicting sources, Missing context, Draft, Stale), Markdown export of approved notes with citations.
  - **T (UI, both profiles):** prepare → review → ask a typed question → open the evidence → export; export contains citations and status labels.
  - **✓** Screenshots on the PR; desktop-UI rows in the matrix have verdicts.
- [ ] **4.7 Phone companion** (FR-08, §5.6)
  - **I:** the phone route and pairing from the 1.5 ADR: QR code, one-time code, per-session token in page memory only, a single paired device, LAN listener only during a session, the HTTPS or hotspot rule. Phone shows one answer at a time with Prepared/Draft/final labels; the laptop status page shows no answer content in companion mode.
  - **T (server over HTTP and UI):** a second device is refused until approved on the laptop; ending the session revokes the token and closes the LAN listener; the laptop page contains no answer text while the phone is paired (asserted on the rendered DOM); a phone disconnect leaves the laptop concealed.
  - **✓** Green; a full-screen share of the laptop during a test call shows no assistant content (spike S2, companion mode).
- [ ] **4.8 First milestone and phase report** (§16, §17.1)
  - **I:** the 30-question evaluation set built from the owner's real repositories, kept outside this repo; scores committed.
  - **✓** **One repository → prepared brief and Q&A in the graph → typed question answered in the desktop window and on the phone**, used in one real standup. Phase report in `docs/jac-findings/reports/`.

### Phase 5 — Live assistance (about 1.5–2 weeks)

- [ ] **5.1 Session state machine and privacy state** (§11.1)
  - **I:** the §11.1 states and transitions; privacy visibility (`concealed`, `preflight_required`, `checked_scope_visible`) as an independent state; Stop closes audio, cancels generation and clears volatile buffers; lock, suspend or lost heartbeat pauses.
  - **T:** every allowed transition, every invalid one refused; a successful network response never changes the privacy state; recovery after Stop requires an explicit resume.
  - **✓** Green.
- [ ] **5.2 Audio capture with source tagging** (FR-07, §9.2, §9.6, §9.7)
  - **I:** `adapters/pipewire.py`: meeting-output stream as "others", microphone as "me", device selector with scope disclosure, source meter and five-second test, a ~30 s in-memory ring buffer, no audio on disk.
  - **T:** with recorded PCM fed through a fake source: streams stay separate; device removal pauses listening; no file is written during a session.
  - **✓** Green; capture CPU and memory measured during a real call.
- [ ] **5.3 Speech-to-text adapter** (§9.3, §9.7)
  - **I:** the service chosen in 1.6; stream opened at session start and closed on Pause/Stop; vocabulary from the brief; partial and final transcript revisions; lag over two seconds shown with a gap marker; an unreachable service offers the other option or typed input, never a silent switch.
  - **T:** a fake streaming service: revisions replace partials; a lag spike produces a gap marker; audio is never sent outside a session.
  - **✓** Green.
- [ ] **5.4 Relevance detection** (§9.5)
  - **I:** local rules on "others" final utterances (question shape, the developer's name, terms from the brief); a tiny Claude check only for ambiguous ones; mentions bring up the brief entry; "me" utterances mark a question answered; Answer this and Ignore recorded as local evaluation data.
  - **T:** a labelled utterance set: precision and recall reported; the developer's own questions are not answered; most utterances make no Claude call.
  - **✓** Green.
- [ ] **5.5 Live answer path end to end** (§10.4, §11.2, §13.1)
  - **I:** detected question → prepared-answer match → else retrieval and Claude → phone; HEAD/index check before each live answer.
  - **T:** the §11.2 sequence with fakes for speech and Claude. **Bench:** prepared answer shown p95 ≤ 1.5 s; voice first useful draft p50 ≤ 3 s, p95 ≤ 6 s (measured with the real services, §13.2).
  - **✓** Green; numbers committed.
- [ ] **5.6 On-demand screen reading** (FR-15, §9.4)
  - **I:** hotkey or phone button → one portal frame → downscale (size from 1.7) → thumbnail with Send/Discard on the phone → sent with the question → discarded after the answer.
  - **T:** portal denial disables the feature for the session; nothing is sent before Send; the frame is not retained.
  - **✓** Green.
- [ ] **5.7 Cost estimate and reconciliation** (NFR-04, §10.6)
  - **I:** per-standup estimate before the session from configured prices; actual usage after it; caps apply to both speech-to-text and Claude.
  - **T:** the §10.6 formula on fixed inputs; a session stops new AI calls at the cap.
  - **✓** Green; measured volumes from three real standups replace the planning volumes in §10.6.
- [ ] **5.8 Controls: conceal, stop, shortcuts, window SDK** (§5.3, §21.3)
  - **I:** conceal and Stop on the laptop and phone; global shortcuts through the GlobalShortcuts portal where available (the binding the backend returns is shown); the window SDK exercised for the laptop window (size, always-on-top, second window).
  - **T:** conceal blanks content within 100 ms (p95); shortcut denial is handled; notifications never contain content.
  - **✓** Window SDK and shortcut rows in the matrix have verdicts.
- [ ] **5.9 Personal pilot gate and phase report** (§16)
  - **✓** The personal-pilot tier passes in real standups: attribution, policy and cancellation tests; the 30-question set; secret canaries; memory budget measured in a real standup; phone pairing and companion-only display verified. Phase report written.

### Phase 6 — Evaluation report (about 3–5 days)

- [ ] **6.1 Upgrade-protocol run on the latest compiler** (§21.5): the §2.5 procedure on whatever Jac release is current.
- [ ] **6.2 Full measurement protocol** (§21.6): every measure in both profiles, project-level measures (findings by category and severity, hours lost, workaround lines, share of non-Jac code, guide accuracy), and optionally the reference app built **outside** this repo.
- [ ] **6.3 Final evaluation report** (§21.7): answers the six §21.1 questions with links to findings and numbers, states the evaluation conditions, and includes upstream issue drafts for the owner to review before posting.
  - **✓** Every open finding has a repro and a status.

### Phase 7 — Sharing with others (when wanted)

Not planned in detail until the owner wants to share Briefly. It covers the "before others use it" tier (§16): the 100-question evaluation set and thresholds (§16.2), the full security suite, laptop-window capture matrix if FR-08a is wanted (§5.4), retention (§14.4), diagnostics export, signed releases and SBOM (§16.3), runbooks.

### Phase 8 — Expansion (based on pilot evidence)

VS Code bridge (FR-03, §7.2), semantic retrieval (FR-14), local speech model for 8 GB+ machines, GitHub App authorization. Each needs its own trust and performance review (§17).

---

## 5. Schedule and risk

| Weeks | Phases | Risk / mitigation |
|---|---|---|
| 1 | P0, start P1 | A scaffold or CI problem stalls tooling → log it, apply the smallest workaround, keep going |
| 2 | P1 | **The desktop profile may not fit 4 GB** (1.3) → daily use moves to the lean profile; the desktop stays the evaluation target |
| 3 | P2, P3 | GitHub edge cases (squash merges, force pushes) grow → keep ambiguous attribution ambiguous; do not chase perfect matching |
| 4–5 | P4 | byLLM streaming gaps (1.4) → `llm=sdk` for that path only, with its finding |
| 6–7 | P5 | Speech accuracy on accents and code terms → typed questions and prepared answers keep the product useful |
| 8 | P6 | New Jac releases mid-project → take them between sub-phases (§2.5), at most one per phase unless a blocker is fixed |

Time spent diagnosing Jac problems is tracked in each finding's Cost field so the final report can state it (§17).

## 6. Verification (end to end, at each phase gate)

1. `scripts/doctor.sh && pre-commit run --all-files && jac check && scripts/test.sh` → all green locally.
2. CI on `main`: every required check green.
3. The desktop artifact installs and runs on the clean VM (`bench/install_check.sh`).
4. Measurements re-run and compared with the previous report (`bench/`).
5. From phase 4: the first-milestone flow works in a real standup on the phone. From phase 5: a full standup with live listening, with the laptop showing no content during a full-screen share.
6. The phase report is written and reviewed by the owner.

## 7. Open items (decide by the sub-phase noted)

- **Decided 2026-11-03:** the owner merges every PR; Claude opens PRs and never merges them.
- **At the end of 0.6:** the owner approves the branch-protection ruleset Claude proposes (Claude applies it with `gh`).
- **Before 1.2:** a clean Ubuntu 24.04 VM for install tests; an 8 GB+ VM for comparison numbers if available (§3.1).
- **Before 1.4:** a Claude API key with a budget for spikes, and which models it can access.
- **Before 1.6:** a consented test recording; which speech-to-text services to trial and keys for them.
- **Before 3.3:** a synthetic GitHub repository for the opt-in live tests, and a fine-grained token for it.
- **Before 4.8:** whether sending meeting audio, screen frames and source excerpts to cloud providers is acceptable at the owner's company (§19); which repositories may use `claude_allowed`.
- **Before 4.7:** is the phone companion acceptable as the main private display (§19)?
- **Before 5.9:** retention periods for notes and evidence (§14.4).
