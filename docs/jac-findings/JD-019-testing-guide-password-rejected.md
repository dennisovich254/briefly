# JD-019: The testing guide's `JacTestClient` example registers a password the auth policy rejects, and the failure is silent

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 1 / 1.1 S0 (while re-testing JI-042)
- **Category / severity:** Documentation gap or error / Minor
- **Capability:** Test runner (`jac test`)
- **Status:** open
- **Related:** upstream searched 2026-11-04: no matching issue
- **Cost:** 0.5 h (requests came back 401 with no hint why); workaround: use a strong fixture password and assert `register_user` succeeded
- **Canary:** tests/canaries/jd_019_testing_guide_password_rejected.jac

## Behaviour

`jac guide jac-testing`, section "In-process endpoint tests: JacTestClient", shows:

```jac
client.register_user("testuser", "password123");
resp = client.post("/walker/CreateTask", json={"title": "My Task"});
assert resp.ok and resp.status_code == 200;
```

On 0.39.0 the server rejects that password: `register_user` returns `400 POLICY_VIOLATION`, "Rejected by the auth policy: the password is too common". It does not raise, so the next request runs unauthenticated and gets `401 Unauthorized`, which looks like an auth bug in the code under test rather than a rejected fixture.

## Expected

The guide's example works as written (a password the default policy accepts), and `register_user` raises, or the guide shows checking its response, when registration fails.

## Repro

A `def:protect hello` function and a `JacTestClient`: `register_user("testuser", "password123")` returns 400 with `POLICY_VIOLATION`; the following `post("/function/hello")` returns 401. With `"Fixture-Pass-7319-xq"` registration returns 201 and the client is authenticated. (`~/jac-repros/JD-019/commit_tests.jac` is the test where it was found.)

## Analysis

The default auth policy now rejects common passwords, but the guide's example predates that. Anyone copying it gets confusing 401s.

## Workaround

Briefly's tests will use a fixture password the policy accepts and assert that `register_user` returned success before going on.

## Canary

`tests/canaries/jd_019_testing_guide_password_rejected.jac`: the guide's call; asserts a 400 policy violation and an unauthenticated client. Mutation-checked: with a strong password the canary fails.

## Upstream issue draft

(For the owner to review before posting.)

> **`jac-testing` JacTestClient example uses a password the default auth policy rejects; `register_user` fails silently**
>
> jac 0.39.0. The guide's `client.register_user("testuser", "password123")` returns `400 POLICY_VIOLATION` ("the password is too common"), and `register_user` doesn't raise, so the example's next request gets 401. Suggest a policy-compliant password in the example, and having `register_user` raise (or the guide assert its response) when registration fails.
