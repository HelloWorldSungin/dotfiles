#!/usr/bin/env bash
# Behavioral tests for the no-mistakes and treehouse latest-stable policy rows and
# their install wiring.
#
# These drive the real pins file through the real installer in --dry-run against
# a stubbed GitHub API, so they prove the policy reaches the release-resolution
# decision rather than asserting that two files contain the same string. No
# network is used and nothing is installed.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PINS="$ROOT/config/dev-tools-versions.sh"
INSTALLER="$ROOT/bin/dev-tools-install-pinned"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/no-mistakes-pin-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

# shellcheck source=../config/dev-tools-versions.sh
# shellcheck disable=SC1091
source "$PINS"

expected_apply() {
  case "$1" in
    treehouse) printf 'report-only' ;;
    no-mistakes) printf 'attended-only' ;;
  esac
}
for tool in treehouse no-mistakes; do
  seen=0
  for row in "${GITHUB_TOOL_PINS[@]}"; do
    IFS='|' read -r name _cmd repo version install_policy apply_policy <<<"$row"
    [ "$name" = "$tool" ] || continue
    seen=1
    [ "$repo" = "kunchenguid/$tool" ] || fail "$tool repository is $repo"
    [ "$version" = latest ] || fail "$tool version selector is $version"
    [ "$install_policy" = latest-archive ] || fail "$tool install policy is $install_policy"
    # Attended-only keeps the guarded updater and any timer away from a binary
    # the shared daemon is running out of; treehouse stays report-only.
    [ "$apply_policy" = "$(expected_apply "$tool")" ] || fail "$tool apply policy is $apply_policy"
  done
  [ "$seen" -eq 1 ] || fail "GITHUB_TOOL_PINS has no $tool row"
done
pass 'treehouse and no-mistakes rows are latest-archive and keep their apply boundaries'

# The installer only reaches its resolution decision when the tool is absent, so
# this runs with a PATH and HOME that contain no no-mistakes or treehouse.
platform=
case "$(uname -s)" in Darwin) platform=darwin ;; Linux) platform=linux ;; *) fail "unsupported test platform $(uname -s)" ;; esac
case "$(uname -m)" in x86_64|amd64) platform="$platform-amd64" ;; arm64|aarch64) platform="$platform-arm64" ;;
  *) fail "unsupported test architecture $(uname -m)" ;;
esac

mkdir -p "$TMP_ROOT/home" "$TMP_ROOT/localbin" "$TMP_ROOT/npm" "$TMP_ROOT/fakebin"
cat >"$TMP_ROOT/fakebin/curl" <<'SH'
#!/usr/bin/env bash
set -eu
url=
for arg in "$@"; do case "$arg" in https://*) url=$arg ;; esac; done
printf '%s\n' "$url" >>"$TEST_CURL_LOG"
case "$url" in
  https://api.github.com/repos/kunchenguid/no-mistakes/releases/latest)
    jq -cn --arg tag "$TEST_NM_TAG" --argjson pre "${TEST_NM_PRERELEASE:-false}" '{draft:false,prerelease:$pre,tag_name:$tag}' ;;
  https://api.github.com/repos/kunchenguid/treehouse/releases/latest)
    jq -cn --arg tag "$TEST_TREE_TAG" '{draft:false,prerelease:false,tag_name:$tag}' ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TMP_ROOT/fakebin/curl"
jq_bin=$(command -v jq) || fail 'missing test dependency: jq'
ln -sf "$jq_bin" "$TMP_ROOT/fakebin/jq"

preview() {
  env PATH="$TMP_ROOT/fakebin:/usr/bin:/bin" HOME="$TMP_ROOT/home" \
    DEV_TOOLS_INSTALL_CURL_BIN="$TMP_ROOT/fakebin/curl" \
    DEV_TOOLS_INSTALL_LOCAL_BIN="$TMP_ROOT/localbin" \
    DEV_TOOLS_UPDATE_NPM_PREFIX="$TMP_ROOT/npm" \
    TEST_CURL_LOG="$TMP_ROOT/curl.log" TEST_NM_TAG="${TEST_NM_TAG:-v1.106.1}" TEST_TREE_TAG="${TEST_TREE_TAG:-v3.1.8}" \
    TEST_NM_PRERELEASE="${TEST_NM_PRERELEASE:-false}" \
    bash "$INSTALLER" --dry-run --only "$1" 2>&1
}

: >"$TMP_ROOT/curl.log"
out=$(preview no-mistakes) || { printf '%s\n' "$out" >&2; fail 'dry-run --only no-mistakes failed'; }
expected_url="https://github.com/kunchenguid/no-mistakes/releases/download/v1.106.1/no-mistakes-v1.106.1-${platform}.tar.gz"
printf '%s' "$out" | grep -qF "$expected_url" || { printf '%s\n' "$out" >&2; fail 'the preview does not name the resolved release archive'; }
printf '%s' "$out" | grep -qF 'releases/download/v1.106.1/checksums.txt' ||
  { printf '%s\n' "$out" >&2; fail 'the preview does not bind the resolved release checksums'; }
[ "$(grep -c . "$TMP_ROOT/curl.log")" -eq 1 ] || fail 'the preview contacted more than the one release lookup'
pass 'the installer resolves latest to the exact release archive and its publisher checksums'

out=$(preview treehouse)
printf '%s' "$out" | grep -qF "releases/download/v3.1.8/treehouse-v3.1.8-${platform}.tar.gz" ||
  { printf '%s\n' "$out" >&2; fail 'the treehouse preview does not name the resolved release archive'; }
pass 'the treehouse preview follows the same release-bound mechanism'

out=$(TEST_TREE_TAG=v3.2.0 preview treehouse)
printf '%s' "$out" | grep -qF "releases/download/v3.2.0/treehouse-v3.2.0-${platform}.tar.gz" ||
  { printf '%s\n' "$out" >&2; fail 'a newer stable treehouse release was not selected'; }
pass 'a newer stable release changes the selected archive'

# A later prerelease must never be selected; the stub answers as GitHub's
# releases/latest does, which only ever reports the latest stable release.
export TEST_NM_PRERELEASE=true
if out=$(preview no-mistakes 2>&1); then fail "a prerelease was selected: $out"; fi
unset TEST_NM_PRERELEASE
export TEST_NM_TAG=v1.107.0-preview.1
if out=$(preview no-mistakes 2>&1); then fail "a suffixed tag was selected: $out"; fi
unset TEST_NM_TAG
pass 'a prerelease or suffixed tag is refused'

# The preview must stay a preview: nothing installed.
[ -z "$(ls -A "$TMP_ROOT/localbin")" ] || fail '--dry-run wrote into the install directory'
pass '--dry-run installs nothing'

printf 'no-mistakes-pin tests passed\n'
