#!/usr/bin/env bash
# Hermetic fresh-machine installation tests. No real tool or service is touched.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/bin/dev-tools-install-pinned"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dev-tools-install-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

sha256sum() {
  if type -P sha256sum >/dev/null 2>&1; then command sha256sum "$@"; else shasum -a 256 "$@"; fi
}
sha512sum() {
  if type -P sha512sum >/dev/null 2>&1; then command sha512sum "$@"; else shasum -a 512 "$@"; fi
}

case "$(uname -s)" in Darwin) HOST_OS=darwin ;; Linux) HOST_OS=linux ;; *) fail 'unsupported test operating system' ;; esac
case "$(uname -m)" in x86_64|amd64) HOST_ARCH=amd64 ;; arm64|aarch64) HOST_ARCH=arm64 ;; *) fail 'unsupported test architecture' ;; esac
HOST_PLATFORM="$HOST_OS-$HOST_ARCH"
case "$HOST_PLATFORM" in
  linux-amd64) HOST_HERDR_TARGET=linux-x86_64; HOST_AGY_SUFFIX=linux-x64/cli_linux_x64.tar.gz ;;
  linux-arm64) HOST_HERDR_TARGET=linux-aarch64; HOST_AGY_SUFFIX=linux-arm/cli_linux_arm64.tar.gz ;;
  darwin-amd64) HOST_HERDR_TARGET=macos-x86_64; HOST_AGY_SUFFIX=darwin-x64/cli_mac_x64.tar.gz ;;
  darwin-arm64) HOST_HERDR_TARGET=macos-aarch64; HOST_AGY_SUFFIX=darwin-arm/cli_mac_arm64.tar.gz ;;
esac

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

make_binary "$ASSETS/treehouse/treehouse" treehouse 3.1.8
make_binary "$ASSETS/no-mistakes/no-mistakes" no-mistakes 1.106.1
make_binary "$ASSETS/herdr" herdr 0.9.0
mkdir -p "$ASSETS/antigravity-dir"
make_binary "$ASSETS/antigravity-dir/antigravity" agy 1.1.28
tar -czf "$ASSETS/treehouse.tar.gz" -C "$ASSETS/treehouse" treehouse
tar -czf "$ASSETS/no-mistakes.tar.gz" -C "$ASSETS/no-mistakes" no-mistakes
tar -czf "$ASSETS/antigravity.tar.gz" -C "$ASSETS/antigravity-dir" antigravity
TREE_SHA=$(sha256sum "$ASSETS/treehouse.tar.gz" | awk '{print $1}')
NM_SHA=$(sha256sum "$ASSETS/no-mistakes.tar.gz" | awk '{print $1}')
OTHER_SHA=$(printf 'another platform archive' | sha256sum | awk '{print $1}')
RELEASE_LOG="$FIXTURE/release.log"
: >"$RELEASE_LOG"
HERDR_SHA=$(sha256sum "$ASSETS/herdr" | awk '{print $1}')
AGY_SHA=$(sha512sum "$ASSETS/antigravity.tar.gz" | awk '{print $1}')

for repo_name in firstmate baby-menu; do
  repo_path="$ASSETS/$repo_name-repo"
  git -C "$ASSETS" init -q -b main "$repo_name-repo"
  printf '%s\n' "$repo_name" >"$repo_path/version"
  git -C "$repo_path" add version
  git -C "$repo_path" commit -qm "seed $repo_name"
  [ "$repo_name" = baby-menu ] && git -C "$repo_path" tag baby-menu-v0.1.24
  git -C "$repo_path" config uploadpack.allowFilter true
done
FIRSTMATE_TEST_REV=$(git -C "$ASSETS/firstmate-repo" rev-parse HEAD)
BABY_MENU_TEST_REV=$(git -C "$ASSETS/baby-menu-repo" rev-parse HEAD)
DEMO_BODY='demo archive'
DEMO_INTEGRITY=$(node -e 'process.stdout.write("sha512-" + require("node:crypto").createHash("sha512").update(process.argv[1]).digest("base64"))' "$DEMO_BODY")

PINS="$FIXTURE/pins.sh"
cat >"$PINS" <<EOF
TOOLCHAIN_VERIFIED_AT=2026-09-09
HERDR_LATEST_MANIFEST_URL=https://herdr.dev/latest.json
ANTIGRAVITY_MANIFEST_URL_PREFIX=https://antigravity-cli-auto-updater.invalid/manifests
CURSOR_AGENT_OBSERVED_VERSION=2026.09.08-test
CURSOR_INSTALLER_URL=https://cursor.invalid/install
CURSOR_INSTALLER_SHA256=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
NPM_TOOL_PINS=(
  'demo|demo|demo-package|1.2.3|$DEMO_INTEGRITY|yes|default'
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
  [ "${TEST_REGISTRY_FAIL:-0}" = 1 ] && exit 1
  integrity=$TEST_DEMO_INTEGRITY
  [ "${TEST_BAD_INTEGRITY:-0}" = 1 ] && integrity=sha512-different
  if [ "$2" = demo-package@latest ]; then
    integrity=${TEST_LATEST_INTEGRITY:-$TEST_DEMO_INTEGRITY}
  fi
  jq -cn --arg v "${TEST_LATEST_VERSION:-1.2.3}" --arg i "$integrity" '{version:$v,"dist.integrity":$i}'
  exit 0
fi
if [ "$1" = pack ]; then
  [ "$2" = demo-package@1.2.3 ] && [ "$3" = --json ] && [ "$4" = --pack-destination ] || exit 1
  body=$TEST_DEMO_BODY
  [ "${TEST_PACK_TAMPERED:-0}" = 1 ] && body="$body tampered"
  printf '%s' "$body" >"$5/demo-package-1.2.3.tgz"
  jq -cn '[{name:"demo-package",version:"1.2.3",filename:"demo-package-1.2.3.tgz"}]'
  exit 0
fi
if [ "$1" = install ]; then
  [ -f "$3" ] && [ "$(cat "$3")" = "$TEST_DEMO_BODY" ] || exit 1
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
  https://api.github.com/repos/kunchenguid/baby-menu/releases/latest)
    jq -cn --arg tag "${TEST_BABY_TAG:-baby-menu-v0.1.24}" '{draft:false,prerelease:false,tag_name:$tag}'
    ;;
  https://api.github.com/repos/kunchenguid/treehouse/releases/latest|https://api.github.com/repos/kunchenguid/no-mistakes/releases/latest)
    [ "${TEST_RELEASE_API_FAIL:-0}" = 1 ] && exit 1
    case "$url" in
      */treehouse/*) tag=v3.1.8 ;;
      *) tag=v1.106.1 ;;
    esac
    printf '%s\n' "$url" >>"$TEST_RELEASE_LOG"
    jq -cn --arg tag "${TEST_RELEASE_TAG:-$tag}" --argjson pre "${TEST_RELEASE_PRERELEASE:-false}" --argjson draft "${TEST_RELEASE_DRAFT:-false}" \
      '{draft:$draft,prerelease:$pre,tag_name:$tag}'
    ;;
  https://github.com/kunchenguid/*/releases/download/*/checksums.txt)
    [ "${TEST_CHECKSUMS_FAIL:-0}" = 1 ] && exit 1
    printf '%s\n' "$url" >>"$TEST_RELEASE_LOG"
    release_tag=${url#*/download/}
    release_tag=${release_tag%%/*}
    tree_name=treehouse-${release_tag}-${TEST_PLATFORM}.tar.gz
    nm_name=no-mistakes-${release_tag}-${TEST_PLATFORM}.tar.gz
    case "$url" in
      */treehouse/*) printf '%s  %s\n' "${TEST_TREE_SHA}" "$tree_name" "${TEST_OTHER_SHA}" "treehouse-${release_tag}-windows-amd64.zip" ;;
      *) printf '%s  %s\n' "${TEST_NM_SHA}" "$nm_name" "${TEST_OTHER_SHA}" "no-mistakes-${release_tag}-windows-amd64.zip" ;;
    esac | { if [ "${TEST_CHECKSUMS_MISSING_ENTRY:-0}" = 1 ]; then grep -v "$TEST_PLATFORM" || true; else cat; fi; } >"$output"
    ;;
  https://github.com/kunchenguid/treehouse/releases/download/*) printf '%s\n' "$url" >>"$TEST_RELEASE_LOG"; cp "$TEST_ASSETS/treehouse.tar.gz" "$output" ;;
  https://github.com/kunchenguid/no-mistakes/releases/download/*) printf '%s\n' "$url" >>"$TEST_RELEASE_LOG"; cp "$TEST_ASSETS/no-mistakes.tar.gz" "$output" ;;
  https://herdr.dev/latest.json)
    [ "${TEST_MANIFEST_FAIL:-0}" = 1 ] && exit 1
    jq -cn --arg sha "${TEST_MANIFEST_SHA:-$TEST_HERDR_SHA}" --arg v "${TEST_HERDR_VERSION:-0.9.0}" --arg t "$TEST_HERDR_TARGET" '{version:$v,assets:{($t):("https://github.com/herdrdev/herdr/releases/download/v"+$v+"/herdr-"+$t)},sha256:{($t):$sha}}'
    ;;
  *herdr*) cp "$TEST_ASSETS/herdr" "$output" ;;
  *antigravity-cli-auto-updater*)
    [ "${TEST_AGY_MANIFEST_FAIL:-0}" = 1 ] && exit 1
    jq -cn --arg sha "${TEST_AGY_SHA:-$TEST_AGY_SHA_DEFAULT}" --arg v "${TEST_AGY_VERSION:-1.1.28}" \
      --arg suffix "$TEST_AGY_SUFFIX" '{version:$v,url:("https://storage.googleapis.com/antigravity-public/antigravity-cli/"+$v+"-test/"+$suffix),sha512:$sha}'
    ;;
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
    TEST_HERDR_SHA="$HERDR_SHA" TEST_HERDR_TARGET="$HOST_HERDR_TARGET" TEST_PLATFORM="$HOST_PLATFORM" TEST_AGY_SUFFIX="$HOST_AGY_SUFFIX" TEST_TREE_SHA="${TEST_TREE_SHA_OVERRIDE:-$TREE_SHA}" TEST_NM_SHA="$NM_SHA" TEST_OTHER_SHA="$OTHER_SHA" TEST_RELEASE_LOG="$RELEASE_LOG" TEST_AGY_SHA_DEFAULT="$AGY_SHA" TEST_NPM_LOG="$NPM_LOG" TEST_ASSETS="$ASSETS" TEST_CURSOR_FETCHED="$FIXTURE/cursor-fetched" \
    TEST_BAD_INTEGRITY="${TEST_BAD_INTEGRITY:-0}" TEST_DEMO_BODY="$DEMO_BODY" TEST_DEMO_INTEGRITY="$DEMO_INTEGRITY" TEST_PACK_TAMPERED="${TEST_PACK_TAMPERED:-0}" TEST_REAL_GIT="$(command -v git)" "$INSTALLER" "$@"
}

run_installer --only demo >/dev/null
[ -x "$PREFIX/bin/demo" ] || fail 'exact npm tool was not installed'
grep -Fxq 'view demo-package@1.2.3 version dist.integrity --json' "$NPM_LOG" || fail 'npm artifact version and integrity were not re-verified'
grep -Eq 'install -g .*/demo-package-1\.2\.3\.tgz$' "$NPM_LOG" || fail 'npm install did not use the verified local archive'
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

export TEST_PACK_TAMPERED=1
: >"$NPM_LOG"
if run_installer --only demo >/dev/null 2>&1; then fail 'mutated publisher archive was accepted'; fi
[ ! -e "$PREFIX/bin/demo" ] || fail 'mutated publisher archive installed a tool'
! grep -Fq 'install -g' "$NPM_LOG" || fail 'mutated publisher archive reached npm install'
unset TEST_PACK_TAMPERED
pass 'fresh install refuses archive bytes that differ from selected integrity'

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
for command_name in treehouse no-mistakes herdr agy; do [ -x "$LOCAL_BIN/$command_name" ] || fail "$command_name artifact was not installed"; done
! grep -Eq 'herdr (update|server|setup|restart|reload|stop|start)' "$FIXTURE/tool-calls.log" || fail 'Herdr lifecycle was driven'
! grep -Eq 'no-mistakes (daemon|update|setup|restart|reload|stop|start)' "$FIXTURE/tool-calls.log" || fail 'no-mistakes daemon lifecycle was driven'
pass 'publisher-checksummed releases install binaries without lifecycle actions'

# Latest-stable GitHub archives: the release is resolved once, and its checksums
# and archive are both bound to that one result.
for tool in treehouse no-mistakes; do
  case "$tool" in treehouse) repo=treehouse; ver=3.1.8 ;; *) repo=no-mistakes; ver=1.106.1 ;; esac
  rm -f "$LOCAL_BIN/$tool"
  : >"$RELEASE_LOG"
  run_installer --only "$tool" >"$FIXTURE/$tool.out"
  [ "$(grep -c "api.github.com/repos/kunchenguid/$repo/releases/latest" "$RELEASE_LOG")" -eq 1 ] || fail "$tool resolved its release more than once"
  grep -Fxq "https://github.com/kunchenguid/$repo/releases/download/v$ver/checksums.txt" "$RELEASE_LOG" || fail "$tool did not fetch the resolved release checksums"
  grep -Fxq "https://github.com/kunchenguid/$repo/releases/download/v$ver/$tool-v$ver-$HOST_PLATFORM.tar.gz" "$RELEASE_LOG" || fail "$tool archive was not bound to the resolved release"
  grep -Fq "installed $tool $ver" "$FIXTURE/$tool.out" || fail "$tool did not report the resolved version"
done
pass 'treehouse and no-mistakes resolve latest once and bind checksums and archive to it'

# Installed commands never trigger discovery.
: >"$RELEASE_LOG"
run_installer --only treehouse >"$FIXTURE/skip.out"
[ ! -s "$RELEASE_LOG" ] || fail 'an installed treehouse still triggered release discovery'
grep -Fq 'skip treehouse' "$FIXTURE/skip.out" || fail 'installed treehouse was not skipped'
pass 'installed latest-archive tools are skipped without discovery'

# Dry run discovers read-only and installs nothing.
rm -f "$LOCAL_BIN/treehouse"
: >"$RELEASE_LOG"
run_installer --dry-run --only treehouse >"$FIXTURE/tree-dry.out"
[ ! -e "$LOCAL_BIN/treehouse" ] || fail 'treehouse dry-run installed a client'
grep -Fq 'would install treehouse 3.1.8' "$FIXTURE/tree-dry.out" || fail 'treehouse dry-run did not name the resolved release'
[ "$(grep -c 'releases/download' "$RELEASE_LOG")" -eq 0 ] || fail 'treehouse dry-run downloaded release artifacts'
pass 'latest-archive dry-run resolves read-only and downloads nothing'

# Fail closed: every refusal leaves no binary behind.
for mode in api prerelease draft tag checksums missing mismatch version; do
  rm -f "$LOCAL_BIN/treehouse"
  case "$mode" in
    api) export TEST_RELEASE_API_FAIL=1 ;;
    prerelease) export TEST_RELEASE_PRERELEASE=true ;;
    draft) export TEST_RELEASE_DRAFT=true ;;
    tag) export TEST_RELEASE_TAG=nightly ;;
    checksums) export TEST_CHECKSUMS_FAIL=1 ;;
    missing) export TEST_CHECKSUMS_MISSING_ENTRY=1 ;;
    mismatch) export TEST_TREE_SHA_OVERRIDE=$OTHER_SHA ;;
    version) export TEST_RELEASE_TAG=v3.1.9 ;;
  esac
  if run_installer --only treehouse >"$FIXTURE/$mode-refusal.out" 2>&1; then fail "latest-archive install accepted $mode"; fi
  [ ! -e "$LOCAL_BIN/treehouse" ] || fail "latest-archive $mode refusal installed a client"
  if [ "$mode" = version ]; then
    grep -Fq "archive reports version '3.1.8' != resolved release 3.1.9" "$FIXTURE/$mode-refusal.out" || fail 'version mismatch did not reach the archive version check'
  fi
  unset TEST_RELEASE_API_FAIL TEST_RELEASE_PRERELEASE TEST_RELEASE_DRAFT TEST_RELEASE_TAG TEST_CHECKSUMS_FAIL TEST_CHECKSUMS_MISSING_ENTRY TEST_TREE_SHA_OVERRIDE
done
rm -f "$LOCAL_BIN/treehouse"
run_installer --only treehouse >/dev/null
pass 'latest-archive installs refuse API failure, prerelease, draft, non-numeric tags, missing or mismatched checksums and version drift'

# macOS ships neither sha256sum nor sha512sum, only `shasum`. Rebuild the
# fixture PATH without the coreutils checksum tools and reinstall both
# checksummed artifacts over it.
NO_COREUTILS_SHA_BIN="$FIXTURE/no-coreutils-sha-bin"
mkdir -p "$NO_COREUTILS_SHA_BIN"
for command_name in awk bash cat chmod cp dirname env grep gzip head install ln mkdir mktemp mv rm sed tar uname jq; do
  resolved=$(type -P "$command_name") || fail "missing test dependency: $command_name"
  ln -sf "$resolved" "$NO_COREUTILS_SHA_BIN/$command_name"
done
if resolved=$(type -P shasum); then
  ln -sf "$resolved" "$NO_COREUTILS_SHA_BIN/shasum"
else
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
fi
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

# Moving npm policy uses the publisher's default tag, then verifies the exact
# artifact again. Existing commands never trigger source discovery.
SAFE_PINS=$PINS
PINS="$FIXTURE/stable-pins.sh"
sed "s@|1.2.3|$DEMO_INTEGRITY|@|latest|publisher|@" "$SAFE_PINS" >"$PINS"
rm -f "$PREFIX/bin/demo"
: >"$NPM_LOG"
run_installer --dry-run --only demo >/dev/null
[ ! -e "$PREFIX/bin/demo" ] || fail 'stable preview installed a package'
grep -Fq 'view demo-package@latest' "$NPM_LOG" || fail 'stable preview did not resolve publisher tag'
run_installer --only demo >/dev/null
grep -Eq 'install -g .*/demo-package-1\.2\.3\.tgz$' "$NPM_LOG" || fail 'stable install did not use the verified local archive'
before=$(wc -l <"$NPM_LOG")
run_installer --only demo >/dev/null
[ "$(wc -l <"$NPM_LOG")" -eq "$before" ] || fail 'installed stable tool triggered discovery'
rm -f "$PREFIX/bin/demo"
for mode in prerelease integrity drift network; do
  case "$mode" in
    prerelease) export TEST_LATEST_VERSION=1.2.3-beta.1 ;;
    integrity) export TEST_LATEST_INTEGRITY=invalid ;;
    drift) export TEST_LATEST_INTEGRITY=sha512-Y2hhbmdlZA== ;;
    network) export TEST_REGISTRY_FAIL=1 ;;
  esac
  if run_installer --only demo >/dev/null 2>&1; then fail "stable npm accepted $mode"; fi
  [ ! -e "$PREFIX/bin/demo" ] || fail "stable npm $mode refusal installed a tool"
  unset TEST_LATEST_VERSION TEST_LATEST_INTEGRITY TEST_REGISTRY_FAIL
done
PINS=$SAFE_PINS
pass 'moving npm selection verifies exact integrity, skips installed tools and fails closed'

# The stable dist-tag is not a supported moving selector. Claude uses the
# default latest tag for this reason; a stable channel must fail closed.
PINS="$FIXTURE/stable-channel-pins.sh"
sed "s/|default'/|stable'/" "$FIXTURE/stable-pins.sh" >"$PINS"
rm -f "$PREFIX/bin/demo"
if run_installer --only demo >/dev/null 2>&1; then fail 'moving npm accepted the stable dist-tag channel'; fi
[ ! -e "$PREFIX/bin/demo" ] || fail 'stable-channel refusal installed a tool'
PINS=$SAFE_PINS
pass 'moving npm selection refuses the stable dist-tag channel'

# Antigravity follows the production manifest. An installed binary is never
# replaced, and bad metadata or checksums install nothing.
prior_agy_sha=$(sha256sum "$LOCAL_BIN/agy")
export TEST_AGY_MANIFEST_FAIL=1
run_installer --only agy >/dev/null
[ "$(sha256sum "$LOCAL_BIN/agy")" = "$prior_agy_sha" ] || fail 'installed Antigravity client was replaced'
rm -f "$LOCAL_BIN/agy"
if run_installer --only agy >/dev/null 2>&1; then fail 'Antigravity accepted manifest failure'; fi
unset TEST_AGY_MANIFEST_FAIL
for mode in prerelease checksum malformed; do
  case "$mode" in
    prerelease) export TEST_AGY_VERSION=1.2.0-beta.1 ;;
    checksum) export TEST_AGY_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
    malformed) export TEST_AGY_VERSION=1.1.28; export TEST_AGY_SHA=invalid ;;
  esac
  if run_installer --only agy >/dev/null 2>&1; then fail "Antigravity accepted $mode"; fi
  [ ! -e "$LOCAL_BIN/agy" ] || fail "Antigravity $mode refusal installed a client"
  unset TEST_AGY_VERSION TEST_AGY_SHA
done
run_installer --only agy >/dev/null
[ -x "$LOCAL_BIN/agy" ] || fail 'Antigravity manifest install did not restore the client'
pass 'Antigravity manifest selection skips installed clients and fails closed'

# Herdr never replaces an installed client, even if discovery is unavailable.
make_binary "$LOCAL_BIN/herdr" herdr 0.8.2
prior_client_sha=$(sha256sum "$LOCAL_BIN/herdr")
export TEST_MANIFEST_FAIL=1
run_installer --only herdr >/dev/null
[ "$(sha256sum "$LOCAL_BIN/herdr")" = "$prior_client_sha" ] || fail 'installed compatible Herdr client was replaced'
rm -f "$LOCAL_BIN/herdr"
if run_installer --only herdr >/dev/null 2>&1; then fail 'Herdr accepted manifest failure'; fi
unset TEST_MANIFEST_FAIL
for mode in prerelease checksum malformed; do
  case "$mode" in
    prerelease) export TEST_HERDR_VERSION=0.10.0-beta.1 ;;
    checksum) export TEST_MANIFEST_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
    malformed) export TEST_MANIFEST_SHA=invalid ;;
  esac
  if run_installer --only herdr >/dev/null 2>&1; then fail "Herdr accepted $mode"; fi
  [ ! -e "$LOCAL_BIN/herdr" ] || fail "Herdr $mode refusal replaced client"
  unset TEST_HERDR_VERSION TEST_MANIFEST_SHA
done
run_installer --dry-run --only herdr >/dev/null
[ ! -e "$LOCAL_BIN/herdr" ] || fail 'Herdr preview installed a client'
run_installer --only herdr >/dev/null
! grep -Ev '^--version (herdr|no-mistakes|treehouse)$' "$FIXTURE/tool-calls.log" | grep -q herdr || fail 'Herdr invoked a lifecycle operation'
rm -f "$LOCAL_BIN/herdr"
make_binary "$ASSETS/herdr" herdr 0.10.0
HERDR_SHA=$(sha256sum "$ASSETS/herdr" | awk '{print $1}')
export TEST_HERDR_VERSION=0.10.0
run_installer --only herdr >"$FIXTURE/herdr-new-stable.out"
grep -Fq 'installed herdr 0.10.0' "$FIXTURE/herdr-new-stable.out" || fail 'Herdr remained version locked'
unset TEST_HERDR_VERSION
pass 'stable Herdr discovery refuses invalid metadata and checksum failures without lifecycle or replacement'

run_installer --only firstmate >/dev/null
run_installer --only baby-menu >/dev/null
[ "$(git -C "$FIXTURE/home/firstmate" rev-parse HEAD)" = "$FIRSTMATE_TEST_REV" ] || fail 'Firstmate clone did not use the exact commit'
[ "$(git -C "$FIXTURE/home/baby-menu" rev-parse HEAD)" = "$BABY_MENU_TEST_REV" ] || fail 'Baby Menu clone did not use the exact release commit'
[ "$(git -C "$FIXTURE/home/firstmate" symbolic-ref --short HEAD)" = main ] || fail 'Firstmate exact clone did not preserve the guarded-update branch'
printf 'new\n' >>"$ASSETS/firstmate-repo/version"
git -C "$ASSETS/firstmate-repo" commit -qam newer
FIRSTMATE_NEW_REV=$(git -C "$ASSETS/firstmate-repo" rev-parse HEAD)
printf 'new\n' >>"$ASSETS/baby-menu-repo/version"
git -C "$ASSETS/baby-menu-repo" commit -qam newer
git -C "$ASSETS/baby-menu-repo" tag baby-menu-v0.1.25
BABY_MENU_NEW_REV=$(git -C "$ASSETS/baby-menu-repo" rev-parse HEAD)
rm -rf "$FIXTURE/home/firstmate" "$FIXTURE/home/baby-menu"
run_installer --only firstmate >/dev/null
TEST_BABY_TAG=baby-menu-v0.1.25 run_installer --only baby-menu >/dev/null
[ "$(git -C "$FIXTURE/home/firstmate" rev-parse HEAD)" = "$FIRSTMATE_NEW_REV" ] || fail 'Firstmate fresh install did not select the current upstream main'
[ "$(git -C "$FIXTURE/home/baby-menu" rev-parse HEAD)" = "$BABY_MENU_NEW_REV" ] || fail 'Baby Menu fresh install did not select the newer stable release'
git -C "$FIXTURE/home/firstmate" -c user.email=tests@example.invalid -c user.name=tests commit -qm 'local commit' --allow-empty
local_head=$(git -C "$FIXTURE/home/firstmate" rev-parse HEAD)
run_installer --only firstmate >/dev/null
[ "$(git -C "$FIXTURE/home/firstmate" rev-parse HEAD)" = "$local_head" ] || fail 'Firstmate install discarded a local commit'
pass 'source repositories install exact commits atomically and idempotently and do not discard local commits'

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
