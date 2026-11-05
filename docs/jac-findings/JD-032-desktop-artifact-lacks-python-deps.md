# JD-032: The desktop artifact does not carry the project's Python dependencies, so an installed app cannot make a byLLM call

- **Version:** jaclang 0.39.1, Ubuntu 26.04, x86-64, desktop profile
- **Found:** 2026-11-05, phase 1 / 1.4 S4 (measuring what byLLM adds to the artifact)
- **Category / severity:** Packaging/install / Major
- **Capability:** Build and packaging (`jac build`)
- **Status:** open
- **Related:** JD-026 (the artifact's undeclared system packages); 1.3's note on the launcher's `../../../venv` path; upstream: [jaseci-labs/jac#9947](https://github.com/jaseci-labs/jac/issues/9947) reports the same launcher path (closed 2026-10-21 by an inactivity bot, as not planned, with no fix); [#9528](https://github.com/jaseci-labs/jac/issues/9528) / [PR #9532](https://github.com/jaseci-labs/jac/pull/9532) (merged 2026-09-29) added Jac packages and `jac.lock`, but vendoring Python dependencies stays behind `--fat`, which the desktop build does not use
- **Cost:** 1 h; workaround: ship the venv's `site-packages` in the artifact and set `JAC_DESKTOP_DEPS` (verified; +323 MB unless trimmed)
- **Canary:** bench/jd_032_desktop_artifact_lacks_python_deps.sh

## Behaviour

Declaring byLLM (`[byllm.model]`) makes `jac install` put litellm, openai, tiktoken, tokenizers, pillow and their dependencies into `.jac/venv` (323 MB). `jac build desktop` copies none of them: the artifact is 270 MB with or without byLLM, and contains no `litellm`. The generated `briefly-launch.sh` instead adds `../../../venv/lib/python*/site-packages` to `JAC_DESKTOP_DEPS`, which in the build tree is the project's own `.jac/venv`.

So the same artifact behaves differently by location. Calling the `answer_stream` endpoint, with no API key so that nothing is billed:

| Where the artifact runs | Result |
|---|---|
| in the build tree (`.jac/client/desktop/desktop/`) | the call reaches the provider: `AuthenticationError` |
| a copy elsewhere, as an installed app is | `ModuleNotFoundError` before any request |
| that copy, with the venv's `site-packages` copied beside it and `JAC_DESKTOP_DEPS` set to it | `AuthenticationError`: it works |

The clean-install job (1.3) did not see this because the app made no byLLM call then.

## Expected

The desktop guide calls the output "**relocatable** … Ship the whole directory", and lists the launcher as "launcher that wires in the project venv". A relocatable artifact should carry the Python packages the app imports (as it carries its own PostgreSQL), or the guide should say that it does not and how to ship them.

## Repro

`bench/jd_032_desktop_artifact_lacks_python_deps.sh`: copies the built artifact out of the project, starts it under Xvfb with no key, registers, calls `answer_stream`, and reads the error frame's `detail`.

## Analysis

Every desktop app that uses byLLM, or any `[dependencies.pypi]` package, works on its developer's machine and fails once installed. For Briefly this blocks every Claude call in the shipped desktop profile until the workaround is in the build. Upstream #9947 traces the same cause in the compiler source: the release launcher exports `JAC_DESKTOP_DEPS` as a relative path back to the project's `.jac/venv`, and `--fat` (vendoring dependencies) is not wired into the desktop build. Our 0.39.1 reproduction confirms the issue still holds after its closure. The C-extension packages in the venv are built for the same `cpython-314` ABI the host embeds (S0), which is why copying them works.

## Workaround

Verified by hand: copy `.jac/venv/lib/python3.14/site-packages` into the artifact (`python-deps/`) and start the app with `JAC_DESKTOP_DEPS` pointing there (the launcher appends to an existing value). To do in the packaging work (phase 8, or 1.3's job once Briefly makes byLLM calls at runtime): a build step that copies only what the app needs, a wrapper launcher that sets the variable, and the clean-install job calling `answer_stream` with no key to check for `ModuleNotFoundError`.

## Canary

`bench/jd_032_desktop_artifact_lacks_python_deps.sh`: exit 0 while the installed copy fails with `ModuleNotFoundError`. It sends no key, so it never reaches a provider.

## Upstream issue draft

(For the owner to review before posting.) #9947 already reports this, so this is a comment on it asking to reopen, not a new issue.

> Still reproduces on jac 0.39.1, so please reopen. With `[byllm.model]` declared, `.jac/venv` holds litellm and its dependencies (323 MB), but `jac build desktop`'s output contains none of them, and `<app>-launch.sh` adds `../../../venv/lib/python*/site-packages` to `JAC_DESKTOP_DEPS`. In the build tree a `by llm()` call works; the same directory copied elsewhere fails with `ModuleNotFoundError: litellm` before any request. Copying the venv's site-packages beside the binary and setting `JAC_DESKTOP_DEPS` works, which suggests wiring `--fat` (or an equivalent vendoring step) into the desktop build.
