#!/usr/bin/env bash
# srcapp smoke test — covers install_tar (the tar path, not cmd).
# Every path derives from $HOME, so this never touches the real catalog.
# Usage: bash test/smoke.sh [path/to/srcapp]
set -uo pipefail

SRCAPP=${1:-"$(cd "$(dirname "$0")/.." && pwd)/srcapp"}
[ -x "$SRCAPP" ] || { echo "FAIL: srcapp is not executable: $SRCAPP" >&2; exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
FAKE="$WORK/home"; mkdir -p "$FAKE"

fails=0
ok()   { echo "  ok — $1"; }
fail() { echo "  FAIL — $1" >&2; fails=$((fails+1)); }

# fixture: a tarball holding one binary that answers --version
make_pkg() {
    local ver="$1"
    local d="$WORK/pkg-$ver"
    mkdir -p "$d/bin"
    printf '#!/usr/bin/env bash\necho "demo %s"\n' "$ver" > "$d/bin/demo"
    chmod +x "$d/bin/demo"
    tar -czf "$WORK/demo-$ver.tar.gz" -C "$d" .
}

echo "0. list on an empty catalog must exit 0"
HOME="$FAKE" "$SRCAPP" list >/dev/null 2>&1 && ok "empty catalog exits 0" || fail "empty catalog exits non-zero (breaks 'srcapp list && ...')"

echo "1. add tar (version 1.0.0)"
make_pkg 1.0.0
HOME="$FAKE" "$SRCAPP" add tar demo "$WORK/demo-1.0.0.tar.gz" demo >/dev/null || fail "add tar failed"
STAGE="$FAKE/.local/share/srcapp/demo"
[ "$(cat "$STAGE/CURRENT")" = "demo-1.0.0" ] && ok "CURRENT = demo-1.0.0" || fail "CURRENT: $(cat "$STAGE/CURRENT" 2>&1)"
[ -L "$FAKE/.local/bin/demo" ] && ok "symlink ~/.local/bin/demo exists" || fail "symlink missing"

echo "2. add tar again with the SAME version (regression: <slug>/x/ and a symlink to the stale binary)"
HOME="$FAKE" "$SRCAPP" add tar demo "$WORK/demo-1.0.0.tar.gz" demo >/dev/null || fail "second add tar failed"
[ -d "$STAGE/demo-1.0.0/x" ] && fail "archive nested as demo-1.0.0/x/ (the rm -rf guard is missing)" || ok "no nesting"
n=$(find "$STAGE" -type f -name demo | wc -l)
[ "$n" = 1 ] && ok "only 1 demo binary in the install root" || fail "found $n demo binaries (find | head -1 can pick the stale one)"
ln -sfn "$(find "$STAGE" -type f -name demo | head -1)" "$FAKE/.local/bin/demo" 2>/dev/null
[ "$(readlink -f "$FAKE/.local/bin/demo")" = "$STAGE/demo-1.0.0/bin/demo" ] \
    && ok "symlink points at the active version" || fail "wrong symlink target: $(readlink "$FAKE/.local/bin/demo")"

echo "3. add tar version 2.0.0 (the old slug must be dropped)"
make_pkg 2.0.0
HOME="$FAKE" "$SRCAPP" add tar demo "$WORK/demo-2.0.0.tar.gz" demo >/dev/null || fail "add tar 2.0.0 failed"
[ ! -d "$STAGE/demo-1.0.0" ] && ok "old slug removed" || fail "old slug still there (space cleanup failed)"
[ "$(cat "$STAGE/CURRENT")" = "demo-2.0.0" ] && ok "CURRENT = demo-2.0.0" || fail "CURRENT: $(cat "$STAGE/CURRENT")"

echo "4. add cmd + list + remove"
HOME="$FAKE" "$SRCAPP" add cmd hello 'echo halo' 'rm -f /tmp/srcapp-smoke-should-not-exist' --ver 'echo v1' >/dev/null || fail "add cmd failed"
HOME="$FAKE" "$SRCAPP" list hello | grep -q 'ver=v1' && ok "list shows the version" || fail "list does not show the version"
HOME="$FAKE" "$SRCAPP" update hello >/dev/null || fail "update cmd failed"
HOME="$FAKE" "$SRCAPP" remove demo >/dev/null || fail "remove failed"
[ ! -e "$FAKE/.config/srcapp/demo.conf" ] && ok "conf gone after remove" || fail "conf still there"
[ ! -d "$STAGE" ] && ok "install root gone after remove" || fail "install root still there"
[ -e "$FAKE/.local/bin/demo" ] && fail "symlink ~/.local/bin/demo still there" || ok "symlink gone after remove"

[ "$fails" = 0 ] && { echo "ALL PASSED"; exit 0; }
echo "$fails check(s) failed" >&2; exit 1
