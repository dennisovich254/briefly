#!/usr/bin/env bash
# Self-test for scripts/install_jac.sh and scripts/doctor.sh. Runs offline:
# releases are served from a local directory through JAC_RELEASE_BASE_URL=file://...,
# and a fake `jac` on PATH stands in for the compiler.
# Usage: scripts/toolchain_selftest.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The throwaway repositories must not inherit GIT_DIR and friends from a calling hook.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
passed=0; failed=0

check() {  # check <description> <command...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then passed=$((passed + 1)); printf '  ok    %s\n' "$desc"
    else failed=$((failed + 1)); printf '  FAIL  %s\n' "$desc"; fi
}
refuses() { ! "$@"; }

pinned="$(tr -d '[:space:]' < "$ROOT/.jac-version" 2>/dev/null)"
[[ -n "$pinned" ]] || pinned="0.0.0-missing"
platform="linux-x86_64"
asset="jac-${pinned}-${platform}"

# A fake release: an executable that reports a version, plus its checksum file.
make_release() {  # make_release <dir> <reported version> <checksum mode: good|bad|missing>
    local dir="$1/v${pinned}"; mkdir -p "$dir"
    printf '#!/usr/bin/env bash\necho "jac %s  (Linux x86_64)"\n' "$2" > "$dir/$asset"
    case "$3" in
        good) (cd "$dir" && sha256sum "$asset" > "$asset.sha256") ;;
        bad)  echo "0000000000000000000000000000000000000000000000000000000000000000  $asset" > "$dir/$asset.sha256" ;;
        missing) ;;
    esac
}

install_into() {  # install_into <release dir> <dest>
    JAC_RELEASE_BASE_URL="file://$1" JAC_INSTALL_DIR="$2" "$ROOT/scripts/install_jac.sh"
}

echo "install_jac.sh"
make_release "$tmp/good" "$pinned" good
check "installs the pinned version when the checksum matches" install_into "$tmp/good" "$tmp/bin-good"
check "the installed binary reports the pinned version" grep -q "jac $pinned" <("$tmp/bin-good/jac" --version)

make_release "$tmp/bad" "$pinned" bad
check "refuses a checksum mismatch" refuses install_into "$tmp/bad" "$tmp/bin-bad"
check "installs nothing after a checksum mismatch" test ! -e "$tmp/bin-bad/jac"

make_release "$tmp/nosum" "$pinned" missing
check "refuses a release without a checksum file" refuses install_into "$tmp/nosum" "$tmp/bin-nosum"
check "installs nothing without a checksum file" test ! -e "$tmp/bin-nosum/jac"

make_release "$tmp/wrongver" "9.9.9" good
check "refuses a binary that reports another version" refuses install_into "$tmp/wrongver" "$tmp/bin-wrongver"

echo "doctor.sh"
# A fake jac that reports the pinned version and answers the doctor's runtime probe with a fake
# runtime, whose bundled bun either runs or crashes like an AVX2 build on an older CPU (exit 132).
mkdir -p "$tmp/doctor-bin" "$tmp/rt/jaclang/client/_bun" "$tmp/other-bun"
cat > "$tmp/doctor-bin/jac" <<EOF
#!/usr/bin/env bash
case "\$1" in
    --version) echo "jac $pinned  (Linux x86_64)" ;;
    run) echo "$tmp/rt/jaclang/__init__.py" ;;
esac
EOF
printf '#!/usr/bin/env bash\necho 1.3.11\n' > "$tmp/other-bun/bun"
chmod +x "$tmp/doctor-bin/jac" "$tmp/other-bun/bun"
bundled_bun() {  # bundled_bun runs|crashes
    if [[ "$1" == runs ]]; then printf '#!/usr/bin/env bash\necho 1.3.11\n'; else printf '#!/usr/bin/env bash\nexit 132\n'; fi > "$tmp/rt/jaclang/client/_bun/bun"
    chmod +x "$tmp/rt/jaclang/client/_bun/bun"
}

# A throwaway repo holding only the doctor and a .jac-version, with the fake jac first on PATH.
# Git's repository-local variables (GIT_DIR and friends, which Git exports to hooks) are dropped
# first: inherited from a hook run in a linked worktree, GIT_DIR made `git init` reinitialise the
# real repository and set core.bare=true.
doctor_with() {  # doctor_with <.jac-version content>; prints the doctor's output
    local repo="$tmp/repo-$RANDOM"
    mkdir -p "$repo/scripts" && cp "$ROOT/scripts/doctor.sh" "$repo/scripts/"
    (
        # shellcheck disable=SC2046
        unset $(git rev-parse --local-env-vars)
        git -C "$repo" init -q
        [[ -n "$1" ]] && echo "$1" > "$repo/.jac-version"
        PATH="$tmp/doctor-bin:$PATH" NO_COLOR=1 "$repo/scripts/doctor.sh" 2>&1
    )
}
bundled_bun runs
out_ok="$(doctor_with "$pinned")"
out_wrong="$(doctor_with "0.0.1")"
out_none="$(doctor_with "")"
check "passes the Jac check when jac matches .jac-version" grep -q "PASS  jac $pinned" <<<"$out_ok"
check "fails the Jac check when jac differs from .jac-version" grep -q "FAIL  jac version $pinned != pinned 0.0.1" <<<"$out_wrong"
check "fails when .jac-version is missing" grep -q "FAIL  pinned Jac version in .jac-version" <<<"$out_none"
check "exits non-zero when a check fails" refuses doctor_with "0.0.1"
check "passes the bun check when the runtime's bundled bun runs" grep -q "PASS  bun 1.3.11 runs (bundled in the active Jac runtime)" <<<"$out_ok"
bundled_bun crashes
out_crash="$(JAC_BUN="$tmp/other-bun/bun" doctor_with "$pinned")"
check "fails the bun check when the bundled bun crashes, even with JAC_BUN set (JD-001)" grep -q "FAIL  Jac's bundled bun does not run on this CPU" <<<"$out_crash"
# A hook run in a linked worktree inherits GIT_DIR=<repo>/.git/worktrees/<name>.
bundled_bun runs
outer="$tmp/outer-repo"
git init -q "$outer"
git -C "$outer" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed
git -C "$outer" worktree add -q "$tmp/outer-worktree" HEAD 2>/dev/null
GIT_DIR="$(git -C "$tmp/outer-worktree" rev-parse --absolute-git-dir)" doctor_with "$pinned" >/dev/null
check "leaves the caller's repository alone when a hook's GIT_DIR is inherited" test "$(git -C "$outer" config --get core.bare)" = false

echo
echo "$passed passed, $failed failed"
(( failed == 0 ))
