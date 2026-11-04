# JD-016: `jac build` prints raw `[cyan]` markup and a `Run with: .//…` path

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 1 / 1.1 S0 (candidates noted in 0.3 and 0.6)
- **Category / severity:** Defect / Cosmetic
- **Capability:** Build and packaging (`jac build`)
- **Status:** open
- **Related:** upstream #7102 (item 5, a Rich markup leak; closed as not planned 2026-09-04, still reproducing)
- **Cost:** 0.1 h; workaround: none needed
- **Canary:** tests/canaries/jd_016_build_output_markup.jac

## Behaviour

Every `jac build` ends with the markup tags printed literally:

```
✔ Built [cyan]dist/briefly.jab[/cyan] (825,912 bytes)
```

A build that produces a native binary also prints the path to run with an extra `./` in front of an absolute path:

```
Binary written to /tmp/takerepro-seal-vsr29szp/takerepro/.jac/native/x86_64-unknown-linux-gnu/main (1719328 bytes).
Run with: .//tmp/takerepro-seal-vsr29szp/takerepro/.jac/native/x86_64-unknown-linux-gnu/main
```

That path points into a temporary seal directory, so the command it suggests does not work after the build either.

## Expected

`✔ Built dist/briefly.jab (825,912 bytes)` (coloured, or plain), and either no "Run with" line for an intermediate binary or a usable path.

## Repro

Any `jac build`. `~/jac-repros/JD-016/build.log` is a CLI-kind project with a native entry, which shows both.

## Analysis

Cosmetic, but the `Run with` line is misleading: it points at a seal directory that is gone after the build, while the real artifact is `dist/<name>.jab`, shown on the next line.

## Workaround

None needed.

## Canary

`tests/canaries/jd_016_build_output_markup.jac`: builds a two-function CLI project and asserts both strings appear in the output.

## Upstream issue draft

(For the owner to review before posting.)

> **`jac build` prints `[cyan]…[/cyan]` literally and `Run with: .//<abs path>` into a temp seal dir**
>
> jac 0.39.0. The last line of every build is `✔ Built [cyan]dist/<name>.jab[/cyan] (N bytes)`. A build with a native entry also prints `Run with: .//tmp/<name>-seal-XXXX/<name>/.jac/native/<triple>/main`, an absolute path with `./` prepended, inside a temporary directory. Item 5 of #7102 reported a similar markup leak; that issue was closed as not planned.
