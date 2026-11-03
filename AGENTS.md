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
- `jac check`: type-checks both apps. Lint with explicit files: `jac check --lint $(git ls-files '*.jac')`.
- `jac fmt --check <files>`: formatting. Review what `jac fmt` changes; do not use `--lintfix` blindly.
- `jac run lean` / `jac run desktop`: run a profile. `jac browse` QAs the UI.
- `jac run scripts/check_findings.jac`: checks the findings log.

## Jac reference guides

Jac's syntax is easily confused with Python or JSX. Before writing `.jac`, consult the guides bundled with the pinned compiler: `jac guide` lists them, `jac guide jac-essentials` is the start, `jac guide <name> --sections` / `--section <slug>` retrieve parts. Compiler diagnostics link to the relevant guide.
