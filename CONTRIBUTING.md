# Contributing to Briefly

Briefly is an AI standup assistant for Ubuntu, built in [Jac](https://www.jaseci.org/). The project has two equal goals: the app itself, and an honest record of how well Jac builds desktop apps. Every Jac shortcoming we hit is logged with a reproduction. Start with:

- [`docs/architecture.md`](docs/architecture.md): what is being built and why. "§n" in code and docs refers to a section of it.
- [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md): the phases and sub-phases, the workflow and the Definition of Done.
- [`docs/jac-findings/`](docs/jac-findings/README.md): the Jac findings log and the capability matrix.

## Setup (Ubuntu, x86-64)

1. **Jac**, at the version pinned in `.jac-version`: `scripts/install_jac.sh`. It downloads the official release and refuses to install it unless the SHA-256 matches. The same script upgrades Jac (`jac update --self` does not work for this kind of install).
2. **CPUs without AVX2** (for example Celeron and older Pentium chips): run `scripts/swap_bundled_bun.sh` after every Jac install or upgrade. Jac's bundled bun needs AVX2 and ignores `JAC_BUN` (JD-001).
3. **Project dependencies:** `jac install`.
4. **Desktop build only:** `sudo apt-get install pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev`. To *run* a built desktop artifact on another machine, only `sudo apt-get install libwebkit2gtk-4.1-0` is needed (JD-026); the `clean-install` CI job checks that on a fresh Ubuntu 24.04.
5. **Hooks:** install [pre-commit](https://pre-commit.com/), then run `scripts/install_gitleaks.sh`, `scripts/install_actionlint.sh` and `pre-commit install`. That installs the pre-commit, commit-msg and pre-push hooks. Do not run `jac precommit --install`: it replaces them (JD-008).
6. **Check:** `scripts/doctor.sh` checks all of the above and prints a fix for anything missing.

Run the app with `jac run lean` (in a browser) or `jac run desktop` (in a native window). Build it with `jac build lean` or `jac build desktop`.

## How work is done

One sub-phase of the plan is one branch and one pull request (plan §2.1):

1. Branch from `main`: `feat/…`, `fix/…`, `chore/…`, `docs/…` or `spike/…`.
2. **RED:** write the tests first and watch them fail.
3. **GREEN:** write the code that makes them pass, then refactor.
4. Run the gates. The hooks run them on commit and push. `scripts/test.sh` runs the full suite, canaries included.
5. Push and open a pull request using the template.
6. The owner reviews and merges. Pull requests are **squash**-merged, so the PR title becomes the commit message on `main`. The next sub-phase starts after the merge.

`main` is protected: changes reach it only through a pull request with every CI check green.

## The Jac-first rule

For every concern, use Jac's own way first (architecture §21.2). When it fails:

1. Reduce the problem to a minimal reproduction outside this repository.
2. Log a `JD-NNN` finding in `docs/jac-findings/` using its template, and add a canary test that fails when Jac's behaviour changes.
3. Only then add the smallest workaround, citing the finding ID.

Do not avoid a Jac feature in advance. `jac run scripts/check_findings.jac` checks the log.

## Conventions

- **Commits and PR titles:** [Conventional Commits](https://www.conventionalcommits.org/) with the types `feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `ci` and `bench`, for example `feat(2.3): pair the phone companion`. A hook checks commit messages, and CI checks PR titles.
- **Jac code:** `jac precommit <files>` applies Jac's formatting and lint fixes. Review its diff before committing. `scripts/jac_lint.sh` and `scripts/check_warnings.sh` must pass (0 errors, and warnings at or below the baseline).
- **Tests:** never name files `test_*.jac`. Each test builds its own data in a temporary directory. Never call a real Claude, speech-to-text or GitHub API in tests.
- **Environment variables:** variables Briefly reads are named `BRIEFLY_*`, and each is listed in `.env.example` (names only). `scripts/check_governance.sh` enforces this.
- **Secrets:** never commit them. Credentials live in the OS keyring. For development, use `.env`, which is git-ignored. gitleaks runs on every commit, and CI scans the full history.
- **Public repository:** commit nothing from private work repositories, such as names, paths, code or transcripts. Test fixtures are synthetic.

## Reporting a security problem

See [SECURITY.md](SECURITY.md). Please don't open a public issue for it.
