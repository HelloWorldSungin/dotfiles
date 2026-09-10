#!/usr/bin/env bash
# Behavioral tests for the no-mistakes exact pin and its install wiring.
#
# These drive the real pins file through the real installer in --dry-run, so
# they prove the recorded version and publisher checksum actually reach the
# fetch decision, rather than asserting that two files contain the same string.
# No network is used and nothing is installed.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PINS="$ROOT/config/dev-tools-versions.sh"
DOC="$ROOT/docs/dev-tool-versions.md"
INSTALLER="$ROOT/bin/dev-tools-install-pinned"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/no-mistakes-pin-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

# shellcheck source=../config/dev-tools-versions.sh
# shellcheck disable=SC1091
source "$PINS"

[ -n "${NO_MISTAKES_VERSION:-}" ] || fail 'NO_MISTAKES_VERSION is unset'
case "$NO_MISTAKES_VERSION" in
  *[Aa]lpha*|*[Bb]eta*|*[Rr]c*|*preview*|*nightly*|*snapshot*)
    fail "NO_MISTAKES_VERSION $NO_MISTAKES_VERSION is not a stable version" ;;
esac
pass "NO_MISTAKES_VERSION $NO_MISTAKES_VERSION carries no prerelease suffix"

row_version=
for row in "${GITHUB_TOOL_PINS[@]}"; do
  IFS='|' read -r name _cmd repo version install_policy apply_policy <<<"$row"
  [ "$name" = no-mistakes ] || continue
  row_version=$version
  [ "$repo" = kunchenguid/no-mistakes ] || fail "no-mistakes repository is $repo"
  [ "$install_policy" = exact-archive ] || fail "no-mistakes install policy is $install_policy"
  # Attended-only is what keeps the guarded updater and any timer from ever
  # touching a binary the shared daemon is running out of.
  [ "$apply_policy" = attended-only ] || fail "no-mistakes apply policy is $apply_policy"
done
[ -n "$row_version" ] || fail 'GITHUB_TOOL_PINS has no no-mistakes row'
[ "$row_version" = "$NO_MISTAKES_VERSION" ] ||
  fail "GITHUB_TOOL_PINS says $row_version but NO_MISTAKES_VERSION says $NO_MISTAKES_VERSION"
pass 'the release-pin row agrees with NO_MISTAKES_VERSION and stays attended-only'

platforms=0
for row in "${RELEASE_SHA256_PINS[@]}"; do
  IFS='|' read -r key _tree nm _herdr <<<"$row"
  case "$key" in darwin-amd64|darwin-arm64|linux-amd64|linux-arm64) ;;
    *) fail "unexpected release platform $key" ;;
  esac
  printf '%s' "$nm" | grep -qE '^[0-9a-f]{64}$' ||
    fail "no-mistakes checksum for $key is not a sha256 digest"
  platforms=$((platforms + 1))
done
[ "$platforms" -eq 4 ] || fail "expected 4 release platforms, found $platforms"
# Distinct per-platform digests: a copy-paste that reused one platform's value
# would silently make three platforms unverifiable.
distinct=$(for row in "${RELEASE_SHA256_PINS[@]}"; do IFS='|' read -r _k _t nm _h <<<"$row"; printf '%s\n' "$nm"; done | sort -u | wc -l)
[ "$distinct" -eq 4 ] || fail "the four platform checksums are not distinct ($distinct unique)"
pass 'all four platforms carry distinct sha256 no-mistakes checksums'

doc_row=$(grep -E '^\| no-mistakes \|' "$DOC") || fail 'docs/dev-tool-versions.md has no no-mistakes row'
doc_version=$(printf '%s' "$doc_row" | awk -F'|' '{gsub(/ /,"",$3); print $3}')
[ "$doc_version" = "$NO_MISTAKES_VERSION" ] ||
  fail "docs/dev-tool-versions.md says $doc_version but the pin says $NO_MISTAKES_VERSION"
printf '%s' "$doc_row" | grep -q 'Attended only' ||
  fail 'docs/dev-tool-versions.md no longer records no-mistakes as attended only'
# A row that still names the pinned version as excluded would contradict itself.
if printf '%s' "$doc_row" | grep -q "$NO_MISTAKES_VERSION prerelease"; then
  fail "docs/dev-tool-versions.md excludes $NO_MISTAKES_VERSION as a prerelease while pinning it"
fi
pass 'the documented inventory row agrees with the pin and its apply boundary'

# The installer only reaches its fetch decision when the tool is absent, so this
# runs with a PATH and HOME that contain no no-mistakes.
platform=
case "$(uname -s)" in Darwin) platform=darwin ;; Linux) platform=linux ;; *) fail "unsupported test platform $(uname -s)" ;; esac
case "$(uname -m)" in x86_64|amd64) platform="$platform-amd64" ;; arm64|aarch64) platform="$platform-arm64" ;;
  *) fail "unsupported test architecture $(uname -m)" ;;
esac
expected_sha=
for row in "${RELEASE_SHA256_PINS[@]}"; do
  IFS='|' read -r key _tree nm _herdr <<<"$row"
  [ "$key" = "$platform" ] && expected_sha=$nm
done
[ -n "$expected_sha" ] || fail "no release checksum row for $platform"

mkdir -p "$TMP_ROOT/home" "$TMP_ROOT/localbin" "$TMP_ROOT/npm"
preview=$(env PATH=/usr/bin:/bin HOME="$TMP_ROOT/home" \
  DEV_TOOLS_INSTALL_LOCAL_BIN="$TMP_ROOT/localbin" \
  DEV_TOOLS_UPDATE_NPM_PREFIX="$TMP_ROOT/npm" \
  bash "$INSTALLER" --dry-run --only no-mistakes 2>&1) ||
  fail 'dev-tools-install-pinned --dry-run --only no-mistakes failed'

expected_url="https://github.com/kunchenguid/no-mistakes/releases/download/v${NO_MISTAKES_VERSION}/no-mistakes-v${NO_MISTAKES_VERSION}-${platform}.tar.gz"
printf '%s' "$preview" | grep -qF "$expected_url" ||
  { printf '%s\n' "$preview" >&2; fail 'the installer preview does not name the pinned release archive'; }
printf '%s' "$preview" | grep -qF "sha256 $expected_sha" ||
  { printf '%s\n' "$preview" >&2; fail 'the installer preview does not name the pinned publisher checksum'; }
pass 'the installer resolves the pin to the exact release archive and publisher checksum'

# The preview must stay a preview: nothing installed, no network artifacts left.
[ -z "$(ls -A "$TMP_ROOT/localbin")" ] || fail '--dry-run wrote into the install directory'
pass '--dry-run installs nothing'

printf 'no-mistakes-pin tests passed\n'
