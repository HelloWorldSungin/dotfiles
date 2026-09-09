#!/usr/bin/env bash
# Hermetic fresh-machine installation tests. No real tool or service is touched.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/bin/dev-tools-install-pinned"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dev-tools-install-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

FIXTURE="$TMP_ROOT/fixture"
ASSETS="$FIXTURE/assets"
FAKEBIN="$FIXTURE/fakebin"
PREFIX="$FIXTURE/npm-prefix"
LOCAL_BIN="$FIXTURE/local-bin"
mkdir -p "$ASSETS/treehouse" "$ASSETS/no-mistakes" "$FAKEBIN" "$PREFIX/bin" "$LOCAL_BIN"

make_binary() {
  local path=$1 name=$2 version=$3
  mkdir -p "$(dirname "$path")"
  printf '#!/usr/bin/env bash\nprintf "%%s %s\\n" "$*" >>"%s"\nprintf "%s %s\\n"\n' \
    "$name" "$FIXTURE/tool-calls.log" "$name" "$version" >"$path"
  chmod +x "$path"
}

make_binary "$ASSETS/treehouse/treehouse" treehouse 2.3.0
make_binary "$ASSETS/no-mistakes/no-mistakes" no-mistakes 1.70.1
make_binary "$ASSETS/herdr" herdr 0.9.0
mkdir -p "$ASSETS/antigravity-dir"
make_binary "$ASSETS/antigravity-dir/antigravity" agy 1.1.28
tar -czf "$ASSETS/treehouse.tar.gz" -C "$ASSETS/treehouse" treehouse
tar -czf "$ASSETS/no-mistakes.tar.gz" -C "$ASSETS/no-mistakes" no-mistakes
tar -czf "$ASSETS/antigravity.tar.gz" -C "$ASSETS/antigravity-dir" antigravity
TREE_SHA=$(sha256sum "$ASSETS/treehouse.tar.gz" | awk '{print $1}')
NM_SHA=$(sha256sum "$ASSETS/no-mistakes.tar.gz" | awk '{print $1}')
HERDR_SHA=$(sha256sum "$ASSETS/herdr" | awk '{print $1}')
AGY_SHA=$(sha512sum "$ASSETS/antigravity.tar.gz" | awk '{print $1}')

for repo_name in firstmate baby-menu; do
  repo_path="$ASSETS/$repo_name-repo"
  git -C "$ASSETS" init -q -b main "$repo_name-repo"
  printf '%s\n' "$repo_name" >"$repo_path/version"
  git -C "$repo_path" add version
  git -C "$repo_path" commit -qm "seed $repo_name"
  git -C "$repo_path" config uploadpack.allowFilter true
done
FIRSTMATE_TEST_REV=$(git -C "$ASSETS/firstmate-repo" rev-parse HEAD)
BABY_MENU_TEST_REV=$(git -C "$ASSETS/baby-menu-repo" rev-parse HEAD)

PINS="$FIXTURE/pins.sh"
cat >"$PINS" <<EOF
TOOLCHAIN_VERIFIED_AT=2026-09-09
TREEHOUSE_VERSION=2.3.0
NO_MISTAKES_VERSION=1.70.1
HERDR_VERSION=0.9.0
ANTIGRAVITY_VERSION=1.1.28
CURSOR_AGENT_OBSERVED_VERSION=2026.09.08-test
CURSOR_INSTALLER_URL=https://cursor.invalid/install
CURSOR_INSTALLER_SHA256=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
FIRSTMATE_REV=$FIRSTMATE_TEST_REV
BABY_MENU_REV=$BABY_MENU_TEST_REV
NPM_TOOL_PINS=(
  'demo|demo|demo-package|1.2.3|sha512-ZGV0ZXJtaW5pc3RpYw==|yes|default'
)
RELEASE_SHA256_PINS=(
  'linux-amd64|$TREE_SHA|$NM_SHA|$HERDR_SHA'
)
ANTIGRAVITY_ASSET_PINS=(
  'linux-amd64|https://publisher.invalid/antigravity.tar.gz|$AGY_SHA'
)
EOF

NPM_LOG="$FIXTURE/npm.log"
: >"$NPM_LOG"
: >"$FIXTURE/tool-calls.log"
cat >"$FAKEBIN/npm" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$TEST_NPM_LOG"
if [ "$1" = view ]; then
  integrity=sha512-ZGV0ZXJtaW5pc3RpYw==
  [ "${TEST_BAD_INTEGRITY:-0}" = 1 ] && integrity=sha512-different
  jq -cn --arg v 1.2.3 --arg i "$integrity" '{version:$v,"dist.integrity":$i}'
  exit 0
fi
if [ "$1" = install ]; then
  mkdir -p "$NPM_CONFIG_PREFIX/bin"
  cat >"$NPM_CONFIG_PREFIX/bin/demo" <<'TOOL'
#!/usr/bin/env bash
printf 'demo 1.2.3\n'
TOOL
  chmod +x "$NPM_CONFIG_PREFIX/bin/demo"
  exit 0
fi
exit 1
SH

cat >"$FAKEBIN/curl" <<'SH'
#!/usr/bin/env bash
set -eu
url= output= previous=
for arg in "$@"; do
  [ "$previous" = -o ] && output=$arg
  case "$arg" in https://*) url=$arg ;; esac
  previous=$arg
done
case "$url" in
  *treehouse*) cp "$TEST_ASSETS/treehouse.tar.gz" "$output" ;;
  *no-mistakes*) cp "$TEST_ASSETS/no-mistakes.tar.gz" "$output" ;;
  *herdr*) cp "$TEST_ASSETS/herdr" "$output" ;;
  *antigravity*) cp "$TEST_ASSETS/antigravity.tar.gz" "$output" ;;
  *cursor*) touch "$TEST_CURSOR_FETCHED"; printf '#!/usr/bin/env bash\nexit 0\n' >"$output" ;;
  *) exit 1 ;;
esac
SH

cat >"$FAKEBIN/git" <<'SH'
#!/usr/bin/env bash
set -eu
args=("$@")
for index in "${!args[@]}"; do
  case "${args[$index]}" in
    https://github.com/kunchenguid/firstmate.git) args[$index]="file://$TEST_ASSETS/firstmate-repo" ;;
    https://github.com/kunchenguid/baby-menu.git) args[$index]="file://$TEST_ASSETS/baby-menu-repo" ;;
  esac
done
exec "$TEST_REAL_GIT" "${args[@]}"
SH
chmod +x "$FAKEBIN"/*

run_installer() {
  env HOME="$FIXTURE/home" PATH="${TEST_PATH:-$FAKEBIN:/usr/bin:/bin}" DEV_TOOLS_PINS_FILE="$PINS" \
    DEV_TOOLS_INSTALL_CURL_BIN="$FAKEBIN/curl" DEV_TOOLS_INSTALL_NPM_BIN="$FAKEBIN/npm" \
    DEV_TOOLS_INSTALL_GIT_BIN="$FAKEBIN/git" \
    DEV_TOOLS_INSTALL_LOCAL_BIN="$LOCAL_BIN" DEV_TOOLS_UPDATE_NPM_PREFIX="$PREFIX" \
    TEST_NPM_LOG="$NPM_LOG" TEST_ASSETS="$ASSETS" TEST_CURSOR_FETCHED="$FIXTURE/cursor-fetched" \
    TEST_BAD_INTEGRITY="${TEST_BAD_INTEGRITY:-0}" TEST_REAL_GIT="$(command -v git)" "$INSTALLER" "$@"
}

run_installer --only demo >/dev/null
[ -x "$PREFIX/bin/demo" ] || fail 'exact npm tool was not installed'
grep -Fxq 'view demo-package@1.2.3 version dist.integrity --json' "$NPM_LOG" || fail 'npm artifact version and integrity were not re-verified'
grep -Fxq 'install -g demo-package@1.2.3' "$NPM_LOG" || fail 'npm install did not use the exact version'
before=$(wc -l <"$NPM_LOG")
run_installer --only demo >/dev/null
[ "$(wc -l <"$NPM_LOG")" -eq "$before" ] || fail 'install-if-absent was not idempotent'
pass 'npm fresh install re-verifies integrity and installs the exact version idempotently'

rm -f "$PREFIX/bin/demo"
TEST_BAD_INTEGRITY=1
if run_installer --only demo >/dev/null 2>&1; then fail 'registry integrity drift was accepted'; fi
[ ! -e "$PREFIX/bin/demo" ] || fail 'integrity refusal still installed the tool'
unset TEST_BAD_INTEGRITY
pass 'npm registry integrity drift is refused'

: >"$NPM_LOG"
SAFE_PINS=$PINS
PINS="$FIXTURE/prerelease-pins.sh"
sed 's/|1.2.3|/|1.2.3-beta.1|/' "$SAFE_PINS" >"$PINS"
if run_installer --only demo >/dev/null 2>&1; then fail 'prerelease pin was accepted'; fi
PINS=$SAFE_PINS
[ ! -s "$NPM_LOG" ] || fail 'prerelease pin reached the registry'
pass 'prerelease and moving install versions are refused before source access'

: >"$NPM_LOG"
run_installer --dry-run --only demo >"$FIXTURE/dry-run.out"
grep -Fq 'demo-package@1.2.3' "$FIXTURE/dry-run.out" || fail 'dry-run omitted the exact npm pin'
[ ! -s "$NPM_LOG" ] || fail 'dry-run contacted npm or installed a package'
[ ! -e "$PREFIX/bin/demo" ] || fail 'dry-run created the command'
pass 'dry-run previews exact installation without mutation'

run_installer --only treehouse >/dev/null
run_installer --only no-mistakes >/dev/null
run_installer --only herdr >/dev/null
run_installer --only agy >/dev/null
for command_name in treehouse no-mistakes herdr agy; do [ -x "$LOCAL_BIN/$command_name" ] || fail "$command_name exact artifact was not installed"; done
! grep -Eq 'herdr (update|server|setup|restart|reload|stop|start)' "$FIXTURE/tool-calls.log" || fail 'Herdr lifecycle was driven'
! grep -Eq 'no-mistakes (daemon|update|setup|restart|reload|stop|start)' "$FIXTURE/tool-calls.log" || fail 'no-mistakes daemon lifecycle was driven'
pass 'publisher-checksummed releases install exact binaries without lifecycle actions'

# macOS ships neither sha256sum nor sha512sum, only `shasum`. Rebuild the
# fixture PATH without the coreutils checksum tools and reinstall both
# checksummed artifacts over it.
NO_COREUTILS_SHA_BIN="$FIXTURE/no-coreutils-sha-bin"
mkdir -p "$NO_COREUTILS_SHA_BIN"
for command_name in awk bash cat chmod cp dirname env grep gzip head install ln mkdir mktemp mv rm sed tar uname jq; do
  resolved=$(type -P "$command_name") || fail "missing test dependency: $command_name"
  ln -sf "$resolved" "$NO_COREUTILS_SHA_BIN/$command_name"
done
cat >"$NO_COREUTILS_SHA_BIN/shasum" <<SHASUM
#!/usr/bin/env bash
set -eu
bits=\$2
shift 2
case "\$bits" in
  256) exec $(type -P sha256sum) "\$@" ;;
  512) exec $(type -P sha512sum) "\$@" ;;
esac
exit 1
SHASUM
chmod +x "$NO_COREUTILS_SHA_BIN/shasum"
( PATH="$FAKEBIN:$NO_COREUTILS_SHA_BIN"; ! type -P sha256sum >/dev/null && ! type -P sha512sum >/dev/null ) \
  || fail 'the shasum-only fixture PATH still exposes the coreutils checksum tools'

rm -f "$LOCAL_BIN/herdr" "$LOCAL_BIN/agy"
TEST_PATH="$FAKEBIN:$NO_COREUTILS_SHA_BIN"
run_installer --only herdr >/dev/null || fail 'sha256 verification broke without coreutils checksum tools'
run_installer --only agy >/dev/null || fail 'sha512 verification broke without coreutils checksum tools'
unset TEST_PATH
[ -x "$LOCAL_BIN/herdr" ] || fail 'herdr was not installed on a shasum-only platform'
[ -x "$LOCAL_BIN/agy" ] || fail 'agy was not installed on a shasum-only platform'
pass 'publisher checksums verify on platforms that ship only shasum'

run_installer --only firstmate >/dev/null
run_installer --only baby-menu >/dev/null
[ "$(git -C "$FIXTURE/home/firstmate" rev-parse HEAD)" = "$FIRSTMATE_TEST_REV" ] || fail 'Firstmate clone did not use the exact commit'
[ "$(git -C "$FIXTURE/home/baby-menu" rev-parse HEAD)" = "$BABY_MENU_TEST_REV" ] || fail 'Baby Menu clone did not use the exact release commit'
[ "$(git -C "$FIXTURE/home/firstmate" symbolic-ref --short HEAD)" = main ] || fail 'Firstmate exact clone did not preserve the guarded-update branch'
run_installer --only firstmate >/dev/null
pass 'source repositories install exact commits atomically and idempotently'

if run_installer --only cursor-agent >/dev/null 2>&1; then fail 'unpinable Cursor install was accepted'; fi
[ ! -e "$FIXTURE/cursor-fetched" ] || fail 'moving Cursor installer was fetched or executed'
pass 'unpinable Cursor channel refuses automated installation without side effects'

run_installer >"$FIXTURE/full-run.out"
[ ! -e "$FIXTURE/cursor-fetched" ] || fail 'the unattended fresh-machine run fetched the moving Cursor installer'
[ ! -e "$LOCAL_BIN/cursor-agent" ] || fail 'the unattended fresh-machine run installed cursor-agent'
grep -Fq 'skip cursor-agent' "$FIXTURE/full-run.out" || fail 'the unattended run did not report Cursor as skipped'
pass 'the unattended fresh-machine run skips the unsupported moving Cursor installer'

set +e
run_installer --only unknown-source >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || fail 'unknown install source did not fail closed with usage status'
pass 'unknown installation source is refused'

printf '\nall dev-tools-install-pinned tests passed\n'
