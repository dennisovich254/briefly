# JD-013: The mobile scaffold pins React 18 for the whole project, so every app in a workspace runs React 18

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64 (Briefly has no mobile app)
- **Found:** 2026-11-04, phase 1 / 1.1 S0 (re-test of JI-019)
- **Category / severity:** Defect / Minor
- **Capability:** Scaffolding (`jac create`)
- **Status:** open
- **Related:** JI-019 (AfriCinemas), still holding on 0.39.0; upstream searched 2026-11-04: no matching issue
- **Cost:** 0.5 h; workaround: none needed (Briefly has no mobile app); otherwise bump the pins by hand
- **Canary:** tests/canaries/jd_013_mobile_scaffold_pins_react_18.jac

## Behaviour

`jac create mob --kind mobile` writes, under the project-level `[dependencies.npm]`:

```toml
react = "^18.2.0"
react-dom = "^18.2.0"
react-native-web = "^0.19.13"
```

After `jac create --app web --kind web-app` in the same project and `jac install`, the workspace's single install has `react` and `react-dom` **18.3.1**, so the web app also runs on React 18. Nothing in the build or `jac check` warns.

## Expected

The client runtime moved to React 19 so components receive `ref` (the release notes; AfriCinemas saw Radix `asChild` focus break under React 18). The mobile template should pin React 19 and `react-native-web` ≥ 0.21, or the workspace install should warn when one app's pin downgrades a runtime dependency the others rely on.

## Repro

`~/jac-repros/JD-013/mob/`: the mobile scaffold plus a web app; `jac install`; `.jac/client/node_modules/react/package.json` reports 18.3.1.

## Analysis

Unchanged since JI-019 (0.37.18). Briefly's phone companion is served as a web page by the desktop app, not built with the mobile kind (architecture §5.6), so the project is not affected today. Adding a mobile app later would silently downgrade the desktop UI's React.

## Workaround

None needed. If a mobile app is ever added: pin `react`/`react-dom` `^19.2.0` and `react-native-web` `^0.21.2` (AfriCinemas' fix).

## Canary

`tests/canaries/jd_013_mobile_scaffold_pins_react_18.jac`: `jac create --kind mobile --skip` (offline, about a second); asserts the project-level `react` pin starts with `^18`. Mutation-checked: with `--kind web-app` the canary fails.

## Upstream issue draft

(For the owner to review before posting.)

> **Mobile scaffold pins React 18 project-wide; in a workspace every app installs React 18.3.1**
>
> jac 0.39.0. `jac create mob --kind mobile` writes `react = "^18.2.0"`, `react-dom = "^18.2.0"`, `react-native-web = "^0.19.13"` under the project-level `[dependencies.npm]`. Adding a web app (`jac create --app web --kind web-app`) and running `jac install` gives one install with React 18.3.1 for both apps, undoing the client runtime's React 19 (`ref` forwarding). Suggest pinning React 19 and `react-native-web` ^0.21 in the template, or warning when one app's pin downgrades a runtime dependency.
