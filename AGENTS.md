# Working in Briefly

Briefly is an AI standup assistant for Ubuntu built in [Jac](https://www.jaseci.org/), and a rigorous evaluation of how well Jac builds desktop apps. Read these first:

- `docs/architecture.md`: what is being built and why ("§n" in code and docs means a section of it).
- `docs/IMPLEMENTATION_PLAN.md`: phases, sub-phases, the workflow and the Definition of Done.
- `docs/jac-findings/README.md`: how Jac shortcomings are logged.

## Workflow

One sub-phase = one branch = one PR (plan §2.1): write the tests first and see them fail, implement, refactor, run the gates, push, open the PR. **The owner merges every PR**; the next sub-phase starts only after the merge. Never commit to `main` directly.

## The Jac-first rule

Use Jac's own way first for every concern (architecture §21.2). When it fails: reduce it to a minimal repro outside this repo (`~/jac-repros/JD-NNN/`), log a `JD-NNN` finding, then add the smallest workaround, citing the finding ID, behind a named switch where it touches product code, with a canary test. Do not avoid a Jac feature in advance.

## Layout

| Path | What |
|---|---|
| `main.jac` | Lean profile entry (`jac run lean`); at the root because of JD-002 |
| `hosts/desktop/main.jac` | Desktop profile entry (`jac run desktop`, `jac build desktop`) |
| `ui/` | The UI shared by both profiles |
| `core/` | Server-side domain code |
| `tests/`, `tests/canaries/` | `jac test` suites; one canary per open testable finding |
| `bench/` | Measurement scripts and canaries that cannot be unit tests |
| `scripts/` | `doctor.sh`, `install_jac.sh`, `check_findings.jac`, workaround scripts |

## Commands

- `scripts/doctor.sh`: checks the toolchain. On a CPU without AVX2, run `scripts/swap_bundled_bun.sh` after each Jac upgrade (JD-001).
- `scripts/test.sh` (or `--quick`, which skips the canaries): the test suite, strict so a missing local import fails instead of being skipped. Domain code reads the time from `core/clock.jac`, and Git-history tests build repositories with `tests/support/git_fixtures.jac`.
- `pre-commit install` once per clone: installs the pre-commit, commit-msg (Conventional Commits) and pre-push hooks from `.pre-commit-config.yaml`. Do not run `jac precommit --install`: it replaces them (JD-008). `scripts/hooks_selftest.sh` checks every gate.
- `jac precommit <files>`: applies Jac's formatting and auto-fixable lint fixes, which the commit hook requires. Review its diff: it can move comments (JD-009).
- `scripts/jac_lint.sh [files]`: lint that fails on any violation (`jac check --lint` exits 0 on them: JD-006).
- `scripts/check_warnings.sh`: type-checks the apps and every tracked file (a bare `jac check` skips files no app imports: JD-005); 0 errors and warnings at or below `.jac-warnings-baseline`. Runs on pre-push.
- `jac run lean` / `jac run desktop`: run a profile. `jac browse` QAs the UI.
- `jac run scripts/check_findings.jac`: checks the findings log.
- `jac run bench/mem.jac [desktop|lean|both]`: memory (PSS, RSS) and CPU per process group against the §13 budgets; writes `bench/results/` and fails on a miss. Build the artifact first. `bench/window_sdk.sh` checks the desktop window API.
- `scripts/check_governance.sh`: checks the governance files, and that `.env.example` lists every variable the app reads (names only). Name the app's variables `BRIEFLY_*`.
- CI (`.github/workflows/ci.yml`) runs the same gates on every PR: `pr-title`, `quality` (the hooks, the ratchet, the hook self-test), `test` (the full suite), `build-lean` (`jac build lean` plus `scripts/smoke_lean.sh`), `build-desktop`, `security`. Pin every action to a full commit SHA with its release in a comment. `scripts/install_gitleaks.sh` and `scripts/install_actionlint.sh` install the hook binaries, checksum-verified.

## Jac reference guides

Jac's syntax is easily confused with Python or JSX. Before writing `.jac`, consult the guides bundled with the pinned compiler: `jac guide` lists them, `jac guide jac-essentials` is the start, `jac guide <name> --sections` / `--section <slug>` retrieve parts. Compiler diagnostics link to the relevant guide.
