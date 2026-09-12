#!/usr/bin/env bash
# Isolated end-to-end tests for reviewed Kun loader and Matt skills updates.
# Nothing in this suite writes a real Claude, Pi, or generic skill store.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PACKAGED=$(nix build --no-link --print-out-paths --impure --expr "
  let config = (builtins.getFlake \"$ROOT\").homeConfigurations.\"sungin@ct110\".config;
  in builtins.head (builtins.filter (p: (p.name or \"\") == \"skill-reviewed-updates\") config.home.packages)")
UPDATER="$PACKAGED/bin/skill-reviewed-updates"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/skill-reviewed-updates-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v jq >/dev/null 2>&1 || fail 'missing test dependency: jq'
command -v tar >/dev/null 2>&1 || fail 'missing test dependency: tar'
[ -x "$UPDATER" ] || fail 'skill-reviewed-updates is not executable'

WORK="$TMP_ROOT/repo"
mkdir -p "$WORK/config" "$WORK/skills/kun" "$WORK/tests" "$WORK/docs" "$WORK/bin"
cp "$ROOT/config/dev-tools-versions.sh" "$WORK/config/"
cp "$ROOT/skills/kun/SKILL.md" "$WORK/skills/kun/"
cp "$ROOT/tests/kun-skill.test.sh" "$WORK/tests/"
cp "$ROOT/docs/agents.md" "$WORK/docs/"
printf '# project memory\n' >"$WORK/AGENTS.md"
git -C "$WORK" init -q

# shellcheck source=../config/dev-tools-versions.sh
# shellcheck disable=SC1091
source "$WORK/config/dev-tools-versions.sh"

LIVE="$TMP_ROOT/home/.claude"
mkdir -p "$LIVE/skills" "$LIVE/plugins/cache/mattpocock/mattpocock-skills/1.2.3"
printf 'live-claude\n' >"$LIVE/skills/SKILL.md"
printf 'live-plugin\n' >"$LIVE/plugins/cache/mattpocock/mattpocock-skills/1.2.3/SKILL.md"
LIVE_BEFORE=$(find "$LIVE" -type f -exec sha256sum {} \; | sort | sha256sum | awk '{print $1}')

PI_BIN=$(command -v pi) || fail 'missing test dependency: pi'
FAKEBIN="$TMP_ROOT/bin"
STAGING="$TMP_ROOT/staging"
RECEIPTS="$TMP_ROOT/receipts"
CLAUDE="$TMP_ROOT/claude"
mkdir -p "$FAKEBIN" "$STAGING" "$RECEIPTS" "$CLAUDE/plugins"
ln -s "$PI_BIN" "$FAKEBIN/pi"
ln -s "$(command -v node)" "$FAKEBIN/node"

CANDIDATE_KUN="$TMP_ROOT/candidate-kun.md"
{
  cat "$WORK/skills/kun/SKILL.md"
  printf '\n<!-- reviewed-candidate-marker -->\n'
} >"$CANDIDATE_KUN"

PLUGIN_SRC="$TMP_ROOT/plugin-src"
mkdir -p "$PLUGIN_SRC/.claude-plugin" \
  "$PLUGIN_SRC/skills/productivity/grilling" \
  "$PLUGIN_SRC/skills/engineering/domain-modeling" \
  "$PLUGIN_SRC/skills/productivity/ask-matt"
printf 'MIT License\n' >"$PLUGIN_SRC/LICENSE"
printf '%s\n' '{"name":"mattpocock-skills","version":"1.2.4","license":"MIT"}' >"$PLUGIN_SRC/.claude-plugin/plugin.json"
printf '%s\n' '---' 'name: grilling' 'description: Test skill' '---' '# grilling' >"$PLUGIN_SRC/skills/productivity/grilling/SKILL.md"
printf '%s\n' '---' 'name: domain-modeling' 'description: Test skill' '---' '# domain-modeling' >"$PLUGIN_SRC/skills/engineering/domain-modeling/SKILL.md"
printf '%s\n' '---' 'name: ask-matt' 'description: Test skill' '---' '# ask-matt' >"$PLUGIN_SRC/skills/productivity/ask-matt/SKILL.md"
ARCHIVE="$TMP_ROOT/matt.tgz"
tar -czf "$ARCHIVE" -C "$PLUGIN_SRC" .

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
  *raw.githubusercontent.com/*/skills/kun/SKILL.md)
    if [ -n "$output" ]; then cat "$TEST_KUN_CANDIDATE" >"$output"; else cat "$TEST_KUN_CANDIDATE"; fi
    exit 0
    ;;
  *api.github.com/repos/kunchenguid/kun)
    case "${TEST_KUN_LICENSE:-none-declared}" in
      transport) exit 1 ;;
      malformed) printf 'not-json' ;;
      missing) printf '{}' ;;
      none-declared) jq -cn '{license:null}' ;;
      *) jq -cn --arg license "$TEST_KUN_LICENSE" '{license:{spdx_id:$license}}' ;;
    esac
    exit 0
    ;;
  *api.github.com/repos/mattpocock/skills/releases/latest)
    jq -cn '{draft:false,prerelease:false,tag_name:"v1.2.4"}'
    exit 0
    ;;
  *api.github.com/repos/mattpocock/skills)
    jq -cn '{license:{spdx_id:"MIT"}}'
    exit 0
    ;;
  *github.com/mattpocock/skills/archive/refs/tags/v1.2.4.tar.gz)
    if [ -n "$output" ]; then cat "$TEST_MATT_ARCHIVE" >"$output"; else cat "$TEST_MATT_ARCHIVE"; fi
    exit 0
    ;;
esac
exit 1
SH
chmod +x "$FAKEBIN/curl"

cat >"$FAKEBIN/git" <<'SH'
#!/usr/bin/env bash
set -eu
[ "${1:-}" = ls-remote ] || exit 1
printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\tHEAD\n'
SH
chmod +x "$FAKEBIN/git"

cat >"$FAKEBIN/fm-design-skills.sh" <<'SH'
#!/usr/bin/env bash
set -eu
[ "${1:-}" = check ] || exit 2
registry=${FM_MATTPOCOCK_PLUGIN_REGISTRY:-}
[ -f "$registry" ] || { echo 'error: registry missing' >&2; exit 1; }
path=$(jq -er '.plugins["mattpocock-skills@mattpocock"][0].installPath' "$registry")
for required in grilling domain-modeling ask-matt; do
  found=0
  for candidate in "$path/skills/"*"/$required/SKILL.md"; do
    [ -f "$candidate" ] || continue
    found=1
  done
  [ "$found" -eq 1 ] || { echo "error: missing $required" >&2; exit 1; }
done
version=$(jq -er '.plugins["mattpocock-skills@mattpocock"][0].version' "$registry")
printf 'mattpocock design skills ready: version=%s updated=1970-01-01T00:00:00Z path=%s\n' "$version" "$path"
SH
chmod +x "$FAKEBIN/fm-design-skills.sh"

jq -n --arg version "$MATTPOCOCK_SKILLS_VERSION" '{version:2,plugins:{"mattpocock-skills@mattpocock":[{
  installPath:"/forbidden/live/plugin",version:$version,lastUpdated:"2026-01-02T00:00:00Z"}]}}' \
  >"$CLAUDE/plugins/installed_plugins.json"
jq -n '{extraKnownMarketplaces:{mattpocock:{autoUpdate:true}}}' >"$CLAUDE/settings.json"

TEST_PINS_FILE="$WORK/config/dev-tools-versions.sh"
run_updater() {
  env HOME="$TMP_ROOT/home" \
    SKILL_UPDATES_ROOT="$WORK" \
    DEV_TOOLS_PINS_FILE="$TEST_PINS_FILE" \
    SKILL_UPDATES_STAGING_DIR="$STAGING" \
    SKILL_UPDATES_RECEIPT_DIR="$RECEIPTS" \
    DEV_TOOLS_CLAUDE_CONFIG_DIR="$CLAUDE" \
    DEV_TOOLS_UPDATE_CURL_BIN="$FAKEBIN/curl" \
    DEV_TOOLS_UPDATE_GIT_BIN="$FAKEBIN/git" \
    SKILL_UPDATES_FIRSTMATE_DESIGN_SKILLS="$FAKEBIN/fm-design-skills.sh" \
    TEST_KUN_LICENSE="${TEST_KUN_LICENSE:-none-declared}" \
    TEST_KUN_CANDIDATE="$CANDIDATE_KUN" \
    TEST_MATT_ARCHIVE="$ARCHIVE" \
    PATH="$FAKEBIN:/usr/bin:/bin" \
    "$UPDATER" "$@"
}

assert_live_untouched() {
  local now
  now=$(find "$LIVE" -type f -exec sha256sum {} \; | sort | sha256sum | awk '{print $1}')
  [ "$now" = "$LIVE_BEFORE" ] || fail 'a live skill store was written'
  [ "$(cat "$LIVE/skills/SKILL.md")" = live-claude ] || fail 'the planted Claude skill store changed'
  [ "$(cat "$LIVE/plugins/cache/mattpocock/mattpocock-skills/1.2.3/SKILL.md")" = live-plugin ] \
    || fail 'the planted Matt plugin cache changed'
}

mkdir -p "$TMP_ROOT/home"
if env -u SKILL_UPDATES_ROOT -u DEV_TOOLS_PINS_FILE HOME="$TMP_ROOT/home" \
  "$UPDATER" --json adopt >"$TMP_ROOT/store-refusal" 2>&1; then
  fail 'packaged defaults allowed store mutation'
fi
grep -Fq 'immutable store mutation target' "$TMP_ROOT/store-refusal" || fail 'store default failed for an unrelated reason'
TEST_PINS_FILE=
json=$(run_updater --json check)
jq -e --arg pin "$KUN_LOADER_SHA256" '.tools[] | select(.name == "kun-loader") | .current == $pin' <<<"$json" >/dev/null \
  || fail 'explicit checkout did not supply its loader'
cp "$WORK/config/dev-tools-versions.sh" "$WORK/config/selected-pins.sh"
TEST_PINS_FILE="$WORK/config/selected-pins.sh"
sed 's/^MATTPOCOCK_SKILLS_VERSION=.*/MATTPOCOCK_SKILLS_VERSION=0.0.0/' "$TEST_PINS_FILE" >"$TMP_ROOT/pins"
mv "$TMP_ROOT/pins" "$TEST_PINS_FILE"
json=$(run_updater --json check)
jq -e '.tools[] | select(.name == "mattpocock-skills") | .pinned == "0.0.0"' <<<"$json" >/dev/null \
  || fail 'packaged wrapper ignored explicit pins selection'
rm "$TEST_PINS_FILE"
TEST_PINS_FILE=
pass 'built wrapper honors checkout and pins selection and refuses immutable defaults'

json=$(run_updater --json check)
[ "$(printf '%s' "$json" | jq -r '.native_matt_writer')" = claude-marketplace-autoupdate ] \
  || fail 'check did not establish native Claude marketplace autoUpdate as the live Matt writer'
assert_live_untouched
pass 'check records native marketplace autoUpdate ownership without touching live stores'

json=$(run_updater --json --dry-run stage)
[ "$(printf '%s' "$json" | jq -r '.status')" = would_stage ] || fail 'dry-run stage wrote or failed to report would_stage'
[ ! -e "$STAGING/kun/SKILL.md" ] || fail 'dry-run stage wrote staging'
assert_live_untouched
pass 'dry-run stage writes nothing'

json=$(run_updater --json stage)
[ "$(printf '%s' "$json" | jq -r '.status')" = ok ] || fail "stage failed: $json"
[ -f "$STAGING/kun/SKILL.md" ] || fail 'stage did not write a Kun candidate'
[ -f "$STAGING/mattpocock-skills/tree/skills/productivity/grilling/SKILL.md" ] \
  || fail 'stage did not write a Matt candidate tree'
grep -Fq 'reviewed-candidate-marker' "$STAGING/kun/SKILL.md" || fail 'staged Kun candidate was not the upstream loader'
[ "$(cat "$WORK/skills/kun/SKILL.md" | grep -c reviewed-candidate-marker || true)" -eq 0 ] \
  || fail 'stage replaced the current Kun loader'
assert_live_untouched
pass 'stage snapshots candidates without replacing current versions'

for TEST_KUN_LICENSE in transport malformed missing MIT; do
  run_updater --json stage >"$TMP_ROOT/license-stage"
  if [ "$TEST_KUN_LICENSE" = MIT ]; then
    expected_license=MIT
    expected_reason='Kun license changed to MIT; adoption requires license review'
  else
    expected_license=unknown
    expected_reason='Kun license status is unknown; adoption requires a successful license read'
  fi
  [ "$(cat "$STAGING/kun/license")" = "$expected_license" ] || fail 'license observation lost uncertainty'
  if run_updater --json --dry-run adopt >"$TMP_ROOT/license-refusal"; then
    fail 'adoption accepted an unresolved license state'
  fi
  jq -e --arg reason "$expected_reason" '.tools[] | select(.name == "kun-loader") | .status == "failed" and .detail == $reason' \
    "$TMP_ROOT/license-refusal" >/dev/null || fail 'license refusal reported an unrelated failure'
  cmp "$ROOT/skills/kun/SKILL.md" "$WORK/skills/kun/SKILL.md" || fail 'license refusal changed the loader'
  assert_live_untouched
done
TEST_KUN_LICENSE=none-declared
run_updater --json stage >"$TMP_ROOT/license-stage"
pass 'packaged adoption distinguishes unknown license reads and unresolved license changes'


json=$(run_updater --json verify) || fail "verify failed: $json"
[ "$(printf '%s' "$json" | jq -r '.status')" = ok ] || fail "verify failed: $json"
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name=="mattpocock-skills") | .detail')" \
  = 'Firstmate design-skills check accepted the staged plugin' ] \
  || fail 'verify did not run the Firstmate integration check'
assert_live_untouched
pass 'verify accepts a staged loader and plugin against Firstmate contracts'

printf 'broken loader without living urls\n' >"$STAGING/kun/SKILL.md"
json=$(run_updater --json verify) && fail 'verify accepted a broken Kun loader'
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name=="kun-loader") | .status')" = failed ] \
  || fail 'verify did not preserve failure evidence for the Kun loader'
cp "$CANDIDATE_KUN" "$STAGING/kun/SKILL.md"
assert_live_untouched
pass 'verify refuses a candidate that drops living Kun document URLs'

for live_path in "$TMP_ROOT/home/.agents/skills" "$TMP_ROOT/home/.pi/agent/skills" "$CLAUDE/skills"; do
  mkdir -p "$live_path/kun"
  ln -s "$WORK/skills/kun/SKILL.md" "$live_path/kun/SKILL.md"
  before=$(sha256sum "$WORK/skills/kun/SKILL.md")
  if run_updater --json adopt >"$TMP_ROOT/refusal" 2>&1; then
    fail 'adopt accepted a live-linked checkout'
  fi
  [ "$(sha256sum "$WORK/skills/kun/SKILL.md")" = "$before" ] || fail 'refusal modified live loader'
  rm "$live_path/kun/SKILL.md"
done
pass 'adoption refuses every supported live-linked checkout before mutation'

cp "$STAGING/kun/SKILL.md" "$TMP_ROOT/valid-loader"
sed 's/name: kun/name: invalid-name/' "$TMP_ROOT/valid-loader" >"$STAGING/kun/SKILL.md"
if run_updater --json verify >"$TMP_ROOT/invalid-worker"; then
  fail 'verify accepted a candidate unavailable under its worker skill name'
fi
cp "$TMP_ROOT/valid-loader" "$STAGING/kun/SKILL.md"
jq -e '.tools[] | select(.name == "kun-loader") | .status == "failed" and (.detail | contains("missing discovered skill: kun"))' \
  "$TMP_ROOT/invalid-worker" >/dev/null || fail 'candidate failed for an unrelated reason'
pass 'worker discovery rejects a candidate with an incompatible command name'

sed '/^description:/,/^user-invocable:/{ /^user-invocable:/!d; }' "$TMP_ROOT/valid-loader" >"$STAGING/kun/SKILL.md"
if run_updater --json verify >"$TMP_ROOT/missing-description"; then
  fail 'discovery accepted a candidate missing its required description'
fi
jq -e '.tools[] | select(.name == "kun-loader") | .status == "failed" and (.detail | contains("missing discovered skill: kun"))' \
  "$TMP_ROOT/missing-description" >/dev/null || fail 'missing-description candidate failed for an unrelated reason'
cp "$TMP_ROOT/valid-loader" "$STAGING/kun/SKILL.md"
pass 'worker discovery refuses missing metadata and excludes the malformed control'

json=$(run_updater --json --dry-run adopt)
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name=="kun-loader") | .status')" = would_adopt ] \
  || fail 'dry-run adopt did not report would_adopt for Kun'
grep -Fq 'reviewed-candidate-marker' "$WORK/skills/kun/SKILL.md" && fail 'dry-run adopt mutated the loader'
grep -Fq "MATTPOCOCK_SKILLS_VERSION=1.2.3" "$WORK/config/dev-tools-versions.sh" \
  || fail 'dry-run adopt mutated the Matt pin'
assert_live_untouched
pass 'dry-run adopt leaves current versions in place'

json=$(run_updater --json adopt)
[ "$(printf '%s' "$json" | jq -r '.status')" = ok ] || fail "adopt failed: $json"
grep -Fq 'reviewed-candidate-marker' "$WORK/skills/kun/SKILL.md" || fail 'adopt did not update the repository Kun loader'
grep -Fq "MATTPOCOCK_SKILLS_VERSION=1.2.4" "$WORK/config/dev-tools-versions.sh" \
  || fail 'adopt did not update the repository Matt pin'
grep -Fq "EXPECTED_SHA256=$(sha256sum "$WORK/skills/kun/SKILL.md" | awk '{print $1}')" "$WORK/tests/kun-skill.test.sh" \
  || fail 'adopt did not keep the Kun test hash aligned'
receipt=$(printf '%s' "$json" | jq -r '.receipt')
[ -f "$receipt" ] || fail 'adopt wrote no rollback receipt'
[ "$(stat -c '%a' "$receipt" 2>/dev/null || stat -f '%OLp' "$receipt")" = 600 ] \
  || fail 'adopt receipt was not mode 0600'
assert_live_untouched
pass 'adopt updates repository records only and writes rollback evidence'

json=$(run_updater --json rollback "$receipt")
[ "$(printf '%s' "$json" | jq -r '.status')" = check_only ] || fail 'rollback without --attended mutated state'
grep -Fq 'reviewed-candidate-marker' "$WORK/skills/kun/SKILL.md" || fail 'check-only rollback reverted the loader'
assert_live_untouched
pass 'rollback without --attended is evidence-only'

json=$(run_updater --json rollback "$receipt" --attended)
[ "$(printf '%s' "$json" | jq -r '.status')" = rolled_back ] || fail "attended rollback failed: $json"
if grep -Fq 'reviewed-candidate-marker' "$WORK/skills/kun/SKILL.md"; then
  fail 'attended rollback did not restore the prior Kun loader'
fi
grep -Fq "MATTPOCOCK_SKILLS_VERSION=1.2.3" "$WORK/config/dev-tools-versions.sh" \
  || fail 'attended rollback did not restore the prior Matt pin'
assert_live_untouched
pass 'attended rollback restores repository records and still writes no live skill store'

printf '\nall skill-reviewed-updates tests passed\n'
