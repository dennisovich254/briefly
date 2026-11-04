# Security policy

Briefly reads your Git repositories, your GitHub activity and, during a meeting, your questions and what is on your screen. Some of it is sent to Claude to answer you. Security reports are taken seriously.

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately through GitHub's [private vulnerability reporting](https://github.com/dennisovich254/briefly/security/advisories/new) (Security → Advisories → "Report a vulnerability"). Only the maintainer sees the report.

Please include what you found, the steps to reproduce it, and the impact you believe it has. Use synthetic repositories and test accounts, not real source code, tokens or meeting content.

Reports are acknowledged within 5 working days. We'll then agree a fix and a disclosure timeline with you.

## Scope

In scope: this repository's code, build and CI configuration, and the app's behaviour. That especially includes:
- anything that sends source code, questions, speech or screen content off the device without the user's permission;
- access to Briefly's local server from a web page or from another device on the network;
- token handling;
- prompt injection through repository or GitHub content.

Out of scope: vulnerabilities in third-party services and tools themselves (Anthropic, GitHub, speech-to-text providers, Jac). Report those to their vendors. If one affects Briefly, we still want to hear how.

## Supported versions

Briefly is in early development, and only the latest `main` is supported.

## Our safeguards

- The threat model and required controls are in [`docs/architecture.md`](docs/architecture.md) §14.1. They include loopback-only binding, exact Host and Origin checks, credentials in the OS keyring, and a payload preview before the first cloud call.
- Secrets never go in the repository. gitleaks scans every commit locally and the full history in CI, and GitHub secret scanning with push protection is on.
- GitHub Actions are pinned to full commit SHAs and kept current by Dependabot. Toolchain binaries are checksum-verified before they are installed.
- `main` only changes through pull requests that pass every CI check.
