#!/usr/bin/env bash
# Hermetic behavior tests for the complete read-only tool inventory.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHECKER="$ROOT/bin/dev-tools-check-updates"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dev-tools-check-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

FIXTURE="$TMP_ROOT/fixture"
FAKEBIN="$FIXTURE/bin"
mkdir -p "$FAKEBIN" "$FIXTURE/home/firstmate/.git" "$FIXTURE/home/baby-menu/.git" "$FIXTURE/nvim/lazy"
PINS="$FIXTURE/pins.sh"
cp "$ROOT/config/dev-tools-versions.sh" "$PINS"
CURSOR_BODY="download=https://downloads.cursor.com/versions/2026.09.08-6caf4ff/cursor-agent/linux/x64/cursor-agent"
CURSOR_HASH=$(printf '%s\n' "$CURSOR_BODY" | sha256sum | awk '{print $1}')
printf '\nCURSOR_INSTALLER_SHA256=%s\n' "$CURSOR_HASH" >>"$PINS"

# shellcheck source=../config/dev-tools-versions.sh
# shellcheck disable=SC1091
source "$PINS"
for row in "${NEOVIM_PLUGIN_PINS[@]}"; do
  IFS='|' read -r name _repo _policy _ref _commit <<<"$row"
  mkdir -p "$FIXTURE/nvim/lazy/$name/.git"
done

CALL_LOG="$FIXTURE/calls.log"
: >"$CALL_LOG"

cat >"$FAKEBIN/npm" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'npm %s\n' "$*" >>"$TEST_CALL_LOG"
[ "${TEST_FAIL_NPM:-0}" = 1 ] && exit 1
package=$2
field=$3
# shellcheck source=/dev/null
source "$TEST_PINS"
version=
for row in "${NPM_TOOL_PINS[@]}"; do
  IFS='|' read -r _name _command candidate candidate_version _integrity _guarded _channel <<<"$row"
  [ "$candidate" = "$package" ] && version=$candidate_version
done
case "$package" in
  opencode-ai) version=$OPENCODE_ACP_VERSION ;;
  omp-acp) version=$OMP_ACP_VERSION ;;
  claude-spend) version=$CLAUDE_SPEND_VERSION ;;
esac
[ "$package" = "${TEST_NPM_PRERELEASE_PACKAGE:-}" ] && version=9.0.0-beta.1
[ -n "$version" ] || exit 1
if [ "$field" = dist-tags.stable ] || [ "$field" = version ]; then jq -cn --arg v "$version" '$v'; else exit 1; fi
SH

cat >"$FAKEBIN/curl" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'curl %s\n' "$*" >>"$TEST_CALL_LOG"
if [ "$#" -eq 1 ] && [ "$1" = --version ]; then printf 'curl 8.21.0\n'; exit 0; fi
[ "${TEST_FAIL_CURL:-0}" = 1 ] && exit 1
url= output=
previous=
for arg in "$@"; do
  [ "$previous" = -o ] && output=$arg
  case "$arg" in https://*) url=$arg ;; esac
  previous=$arg
done
# shellcheck source=/dev/null
source "$TEST_PINS"
if [ "$url" = "$CURSOR_INSTALLER_URL" ]; then
  printf '%s\n' 'download=https://downloads.cursor.com/versions/2026.09.08-6caf4ff/cursor-agent/linux/x64/cursor-agent' >"$output"
  exit 0
fi
if [ "$url" = "$HERDR_LATEST_MANIFEST_URL" ]; then
  for row in "${RELEASE_SHA256_PINS[@]}"; do IFS='|' read -r key _tree _nm sha <<<"$row"; [ "$key" = linux-amd64 ] && break; done
  version=${TEST_HERDR_LATEST_VERSION:-$HERDR_VERSION}
  asset="https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-linux-x86_64"
  [ "$version" = "$HERDR_VERSION" ] || sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  jq -cn --arg v "$version" --arg asset "$asset" --arg sha "$sha" '{version:$v,assets:{"linux-x86_64":$asset},sha256:{"linux-x86_64":$sha}}'
  exit 0
fi
case "$url" in
  *antigravity-cli-auto-updater*)
    for row in "${ANTIGRAVITY_ASSET_PINS[@]}"; do IFS='|' read -r key asset sha <<<"$row"; [ "$key" = linux-amd64 ] && break; done
    version=${TEST_ANTIGRAVITY_LATEST_VERSION:-$ANTIGRAVITY_VERSION}
    asset=${asset/$ANTIGRAVITY_VERSION/$version}
    [ "$version" = "$ANTIGRAVITY_VERSION" ] || sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    jq -cn --arg v "$version" --arg asset "$asset" --arg sha "$sha" '{version:$v,url:$asset,sha512:$sha}'
    exit 0
    ;;
  *api.github.com/repos/*/releases/latest)
    repo=${url#*api.github.com/repos/}; repo=${repo%/releases/latest}
    tag=
    for row in "${GITHUB_TOOL_PINS[@]}"; do
      IFS='|' read -r name _command candidate version _install _apply <<<"$row"
      [ "$candidate" = "$repo" ] && [ "$name" != herdr ] && tag="v$version"
    done
    for row in "${NEOVIM_PLUGIN_PINS[@]}"; do
      IFS='|' read -r _name candidate policy ref _commit <<<"$row"
      [ "$candidate" = "$repo" ] && [ "$policy" = release ] && tag=$ref
    done
    for row in "${CI_ACTION_PINS[@]}"; do
      IFS='|' read -r _name candidate ref _commit <<<"$row"
      [ "$candidate" = "$repo" ] && tag=$ref
    done
    [ "$repo" = DeterminateSystems/nix-installer ] && tag="v$NIX_INSTALLER_VERSION"
    [ "$repo" = kunchenguid/baby-menu ] && tag="baby-menu-v$BABY_MENU_VERSION"
    [ -n "$tag" ] || exit 1
    if [ "$repo" = "${TEST_PRERELEASE_REPO:-}" ]; then
      jq -cn --arg tag "${tag}-preview.1" '{draft:false,prerelease:true,tag_name:$tag}'
    else
      jq -cn --arg tag "$tag" '{draft:false,prerelease:false,tag_name:$tag}'
    fi
    exit 0
    ;;
esac
exit 1
SH

cat >"$FAKEBIN/git" <<'SH'
#!/usr/bin/env bash
set -eu
# shellcheck source=/dev/null
source "$TEST_PINS"
if [ "${1:-}" = --version ]; then printf 'git version 2.54.0\n'; exit 0; fi
printf 'git %s\n' "$*" >>"$TEST_CALL_LOG"
if [ "${1:-}" = -C ]; then
  path=$2
  [ "${3:-}" = rev-parse ] || exit 1
  case "$path" in
    *firstmate) printf '%s\n' "$FIRSTMATE_REV"; exit 0 ;;
    *baby-menu) printf '%s\n' "$BABY_MENU_REV"; exit 0 ;;
    */lazy/*)
      name=${path##*/}
      for row in "${NEOVIM_PLUGIN_PINS[@]}"; do
        IFS='|' read -r candidate _repo _policy _ref commit <<<"$row"
        [ "$candidate" = "$name" ] && { printf '%s\n' "$commit"; exit 0; }
      done
      ;;
  esac
  exit 1
fi
[ "${1:-}" = ls-remote ] || exit 1
repo=$2
ref=${3:-HEAD}
case "$repo|$ref" in
  *NixOS/nixpkgs.git*refs/heads/nixos-*) printf '%s\t%s\n' "$NIXPKGS_REV" "$ref"; exit 0 ;;
  *nix-community/home-manager.git*refs/heads/release-*) printf '%s\t%s\n' "$HOME_MANAGER_REV" "$ref"; exit 0 ;;
  *kunchenguid/firstmate.git*HEAD) printf '%s\tHEAD\n' "$FIRSTMATE_REV"; exit 0 ;;
  *kunchenguid/baby-menu.git*HEAD) printf '%s\tHEAD\n' "$BABY_MENU_REV"; exit 0 ;;
  *kunchenguid/baby-menu.git*refs/tags/baby-menu-v*) printf '%s\t%s^{}\n' "$BABY_MENU_REV" "$ref"; exit 0 ;;
esac
clean=${repo#https://github.com/}; clean=${clean%.git}
for row in "${NEOVIM_PLUGIN_PINS[@]}"; do
  IFS='|' read -r _name candidate _policy tag commit <<<"$row"
  [ "$candidate" = "$clean" ] || continue
  if [ "$ref" = HEAD ]; then printf '%s\tHEAD\n' "$commit"
  else printf '%s\trefs/tags/%s^{}\n' "$commit" "$tag"
  fi
  exit 0
done
for row in "${CI_ACTION_PINS[@]}"; do
  IFS='|' read -r _name candidate _tag commit <<<"$row"
  [ "$candidate" = "$clean" ] || continue
  printf '%s\t%s^{}\n' "$commit" "$ref"
  exit 0
done
exit 1
SH

cat >"$FAKEBIN/tool-version" <<'SH'
#!/usr/bin/env bash
set -eu
# shellcheck source=/dev/null
source "$TEST_PINS"
command_name=${0##*/}
printf '%s %s\n' "$command_name" "$*" >>"$TEST_CALL_LOG"
for row in "${NPM_TOOL_PINS[@]}"; do
  IFS='|' read -r _name candidate _package version _integrity _guarded _channel <<<"$row"
  [ "$candidate" = "$command_name" ] && { printf '%s %s\n' "$command_name" "$version"; exit 0; }
done
for row in "${GITHUB_TOOL_PINS[@]}"; do
  IFS='|' read -r _name candidate _repo version _install _apply <<<"$row"
  [ "$candidate" = "$command_name" ] && { printf '%s %s\n' "$command_name" "$version"; exit 0; }
done
for row in "${NIX_PACKAGE_PINS[@]}"; do
  IFS='|' read -r _package candidate version _evidence <<<"$row"
  if [ "$candidate" = "$command_name" ]; then
    [ "$candidate" = unzip ] && version=6.00
    printf '%s %s\n' "$command_name" "$version"
    exit 0
  fi
done
[ "$command_name" = agy ] && { printf 'agy %s\n' "$ANTIGRAVITY_VERSION"; exit 0; }
[ "$command_name" = cursor-agent ] && { printf 'cursor-agent %s\n' "$CURSOR_AGENT_OBSERVED_VERSION"; exit 0; }
[ "$command_name" = nix ] && { printf 'nix (Determinate Nix %s) 2.34.8\n' "$NIX_INSTALLER_VERSION"; exit 0; }
exit 1
SH

cat >"$FAKEBIN/printenv" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${TEST_CHROME_ARGS:---no-sandbox --disable-dev-shm-usage --disable-gpu}"
SH
chmod +x "$FAKEBIN"/*

for row in "${NPM_TOOL_PINS[@]}"; do IFS='|' read -r _name command_name _rest <<<"$row"; ln -s tool-version "$FAKEBIN/$command_name"; done
for row in "${GITHUB_TOOL_PINS[@]}"; do IFS='|' read -r _name command_name _rest <<<"$row"; ln -sf tool-version "$FAKEBIN/$command_name"; done
for row in "${NIX_PACKAGE_PINS[@]}"; do
  IFS='|' read -r _package command_name _version _evidence <<<"$row"
  [ "$command_name" = git ] || [ "$command_name" = curl ] || ln -sf tool-version "$FAKEBIN/$command_name"
done
# The closure manifest home/dev-tools.nix generates: name -> exact store path.
# Its stubs answer with the pinned version while the ambient stubs for the same
# commands answer with a wrong one, so which source the checker measured is
# observable in the result rather than assumed. The ambient stub replaces the
# shared `tool-version` symlink instead of writing through it, and git and curl
# keep the suite's own behavioural stubs, which the checker is pointed at.
BASH_BIN=$(command -v bash) || fail 'missing test dependency: bash'
CLOSURE_DIR="$FIXTURE/closure"
CLOSURE_FILE="$FIXTURE/dev-tools-closure.json"
closure_entries='[]'
CLOSURE_ROWS=()
for row in "${NIX_PACKAGE_PINS[@]}"; do
  IFS='|' read -r package command_name version evidence <<<"$row"
  [ "$evidence" = closure ] || continue
  CLOSURE_ROWS+=("$package|$command_name|$version")
  mkdir -p "$CLOSURE_DIR/$package/bin"
  printf '#!%s\nprintf "%s (closure) %s\\n"\n' "$BASH_BIN" "$command_name" "$version" \
    >"$CLOSURE_DIR/$package/bin/$command_name"
  chmod +x "$CLOSURE_DIR/$package/bin/$command_name"
  closure_entries=$(jq -cn --argjson a "$closure_entries" --arg n "$package" --arg v "$version" \
    --arg p "$CLOSURE_DIR/$package" '$a + [{name:$n,version:$v,store_path:$p}]')
  # A hostile ambient answer for the same command, so any PATH measurement shows.
  case "$command_name" in
    git|curl) ;;
    *)
      rm -f "$FAKEBIN/$command_name"
      printf '#!%s\nprintf "%s 0.0.1\\n"\n' "$BASH_BIN" "$command_name" >"$FAKEBIN/$command_name"
      chmod +x "$FAKEBIN/$command_name"
      ;;
  esac
done
[ "${#CLOSURE_ROWS[@]}" -gt 0 ] || fail 'the manifest declares no closure-classed Nix rows'
printf '%s\n' "$closure_entries" >"$CLOSURE_FILE"

ln -sf tool-version "$FAKEBIN/agy"
ln -sf tool-version "$FAKEBIN/cursor-agent"
ln -sf tool-version "$FAKEBIN/nix"

# Machine-consumed declarative artifacts are read through a semantic model
# rather than grepped: the workflow's action steps and the Baby Menu agents'
# launch specs.
python3 -c 'import yaml' >/dev/null 2>&1 || fail 'missing test dependency: python3 with PyYAML'
workflow_action_refs() {
  python3 - "$1" <<'PARSE_WORKFLOW'
import sys, yaml
with open(sys.argv[1]) as handle:
    workflow = yaml.safe_load(handle)
for job in (workflow.get("jobs") or {}).values():
    for step in job.get("steps") or []:
        if step.get("uses"):
            print(step["uses"])
PARSE_WORKFLOW
}

acp_launch_version() {
  jq -r --arg agent "$2" --arg package "$3" '
    .[] | select(.name == $agent) | .launchCommand | split(" ")
    | map(select(startswith($package + "@"))) | first // ""
    | ltrimstr($package + "@")
  ' "$1"
}

run_checker() {
  env HOME="$FIXTURE/home" PATH="${TEST_PATH:-$PATH}" DEV_TOOLS_PINS_FILE="$PINS" DEV_TOOLS_NVIM_LOCK_FILE="$ROOT/config/nvim/lazy-lock.json" \
    DEV_TOOLS_FLAKE_LOCK_FILE="${TEST_FLAKE_LOCK_FILE:-$ROOT/flake.lock}" \
    DEV_TOOLS_CLOSURE_FILE="${TEST_CLOSURE_FILE-$CLOSURE_FILE}" \
    DEV_TOOLS_NVIM_DATA_HOME="$FIXTURE/nvim" DEV_TOOLS_UPDATE_BIN_DIR="$FAKEBIN" DEV_TOOLS_UPDATE_NPM_BIN="$FAKEBIN/npm" \
    DEV_TOOLS_UPDATE_CURL_BIN="$FAKEBIN/curl" DEV_TOOLS_UPDATE_GIT_BIN="$FAKEBIN/git" DEV_TOOLS_HEALTH_PRINTENV_BIN="$FAKEBIN/printenv" \
    DEV_TOOLS_UPDATE_CACHE_PATH="$FIXTURE/cache.json" DEV_TOOLS_UPDATE_NOW_EPOCH=1000 TEST_PINS="$PINS" TEST_CALL_LOG="$CALL_LOG" \
    TEST_FAIL_NPM="${TEST_FAIL_NPM:-0}" TEST_FAIL_CURL="${TEST_FAIL_CURL:-0}" \
    TEST_NPM_PRERELEASE_PACKAGE="${TEST_NPM_PRERELEASE_PACKAGE:-}" TEST_PRERELEASE_REPO="${TEST_PRERELEASE_REPO:-}" \
    TEST_HERDR_LATEST_VERSION="${TEST_HERDR_LATEST_VERSION:-}" TEST_ANTIGRAVITY_LATEST_VERSION="${TEST_ANTIGRAVITY_LATEST_VERSION:-}" \
    TEST_CHROME_ARGS="${TEST_CHROME_ARGS:---no-sandbox --disable-dev-shm-usage --disable-gpu}" "$CHECKER" "$@"
}

json=$(run_checker --json --force --no-cache)
[ "$(printf '%s' "$json" | jq -r '.schema_version')" = 4 ] || fail 'schema version is not 4'
[ ! -e "$FIXTURE/cache.json" ] || fail '--no-cache wrote the persistent cache'

expected=0
for _row in "${NPM_TOOL_PINS[@]}" "${GITHUB_TOOL_PINS[@]}" "${NIX_PACKAGE_PINS[@]}" "${NEOVIM_PLUGIN_PINS[@]}" "${CI_ACTION_PINS[@]}"; do expected=$((expected + 1)); done
expected=$((expected + 10)) # antigravity, Cursor, two repos, installer, two inputs, three npx tools
[ "$(printf '%s' "$json" | jq '.tools | length')" -eq "$expected" ] || fail 'complete manifest inventory was not emitted'
[ "$(printf '%s' "$json" | jq '[.tools[] | select(.status != "up_to_date")] | length')" -eq 0 ] || fail 'matching installed, pinned, and latest values were not current'
[ "$(printf '%s' "$json" | jq '.intentionally_unmanaged | length')" -ge 8 ] || fail 'unmanaged documented dependencies were not explicit'
action_refs=$(workflow_action_refs "$ROOT/.github/workflows/build.yml")
[ -n "$action_refs" ] || fail 'the workflow model exposed no action steps to check'
for row in "${CI_ACTION_PINS[@]}"; do
  IFS='|' read -r _name repo _tag commit <<<"$row"
  printf '%s\n' "$action_refs" | grep -Fxq "$repo@$commit" || fail "$repo resolves to a different action commit than the manifest"
done
if printf '%s\n' "$action_refs" | grep -Evq '@[0-9a-f]{40}$'; then
  fail 'a workflow action step resolves to a moving ref instead of an exact commit'
fi
[ "$(acp_launch_version "$ROOT/config/baby-menu/agents.json" opencode opencode-ai)" = "$OPENCODE_ACP_VERSION" ] || fail 'the OpenCode agent launches a different opencode-ai version than the manifest'
[ "$(acp_launch_version "$ROOT/config/baby-menu/agents.json" omp omp-acp)" = "$OMP_ACP_VERSION" ] || fail 'the OMP agent launches a different omp-acp version than the manifest'
grep -Fq 'npm view @anthropic-ai/claude-code dist-tags.stable --json' "$CALL_LOG" || fail 'Claude did not use its authoritative stable dist-tag'
grep -Fq 'herdr --version' "$CALL_LOG" || fail 'Herdr installed version was not surveyed'
! grep -Eq 'herdr (update|server|setup|restart|reload|stop|start)' "$CALL_LOG" || fail 'checker drove Herdr lifecycle behavior'
! grep -Eq 'no-mistakes (daemon|update|setup|restart|reload|stop|start)' "$CALL_LOG" || fail 'checker drove no-mistakes lifecycle behavior'
pass 'full inventory reports matching installed, pinned, and latest stable values read-only'

# macOS ships shasum but neither sha256sum nor sha512sum. The Cursor snapshot
# audit must still compare the real installer hash there rather than reporting
# drift that does not exist.
SHASUM_ONLY_BIN="$FIXTURE/shasum-only-bin"
mkdir -p "$SHASUM_ONLY_BIN"
for command_name in awk basename bash cat cut date dirname env grep head jq ln ls mkdir mktemp rm sed sort tail timeout tr uname wc; do
  resolved=$(type -P "$command_name") || fail "missing test dependency: $command_name"
  ln -sf "$resolved" "$SHASUM_ONLY_BIN/$command_name"
done
cat >"$SHASUM_ONLY_BIN/shasum" <<SHASUM
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
chmod +x "$SHASUM_ONLY_BIN/shasum"
( PATH="$SHASUM_ONLY_BIN"; ! type -P sha256sum >/dev/null && ! type -P sha512sum >/dev/null ) \
  || fail 'the shasum-only fixture PATH still exposes the coreutils checksum tools'

TEST_PATH="$SHASUM_ONLY_BIN"
json=$(run_checker --json --force --no-cache)
unset TEST_PATH
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name=="cursor-agent") | .status')" = up_to_date ] \
  || fail 'a shasum-only platform manufactured Cursor installer drift'
[ "$(printf '%s' "$json" | jq '[.tools[] | select(.status != "up_to_date")] | length')" -eq 0 ] \
  || fail 'a shasum-only platform changed the audit result for some other tool'
pass 'the Cursor snapshot audit is accurate on platforms that ship only shasum'

TEST_NPM_PRERELEASE_PACKAGE=@openai/codex
TEST_PRERELEASE_REPO=kunchenguid/treehouse
json=$(run_checker --json --force --no-cache)
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name=="codex") | .status')" = unknown ] || fail 'npm prerelease was accepted as stable'
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name=="treehouse") | .status')" = unknown ] || fail 'GitHub prerelease was accepted as stable'
unset TEST_NPM_PRERELEASE_PACKAGE TEST_PRERELEASE_REPO
pass 'stable-channel filters reject npm and GitHub prereleases'

TEST_HERDR_LATEST_VERSION=0.10.0
TEST_ANTIGRAVITY_LATEST_VERSION=1.2.0
json=$(run_checker --json --force --no-cache)
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name=="herdr") | [.latest_stable,.status] | join("|")')" = '0.10.0|pin_outdated' ] || fail 'newer stable Herdr manifest was hidden as unknown'
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name=="antigravity") | [.latest_stable,.status] | join("|")')" = '1.2.0|pin_outdated' ] || fail 'newer stable Antigravity manifest was hidden as unknown'
unset TEST_HERDR_LATEST_VERSION TEST_ANTIGRAVITY_LATEST_VERSION
pass 'newer stable publisher manifests remain visible as pin drift'

DRIFTED_LOCK="$FIXTURE/drifted-flake.lock"
jq '.nodes.nixpkgs.locked.rev = "0000000000000000000000000000000000000000"' "$ROOT/flake.lock" >"$DRIFTED_LOCK"
TEST_FLAKE_LOCK_FILE=$DRIFTED_LOCK
json=$(run_checker --json --force --no-cache)
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name=="nixpkgs-input") | .status')" = drifted ] || fail 'flake.lock disagreement was hidden'
unset TEST_FLAKE_LOCK_FILE
pass 'flake input declarations are checked against the exact lock revisions'

TEST_FAIL_NPM=1
json=$(run_checker --json --force --no-cache)
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name=="quota-axi") | .status')" = unknown ] || fail 'unknown registry source was treated as current'
unset TEST_FAIL_NPM
pass 'unknown publication sources remain explicitly unknown'

health=$(run_checker --health --json)
[ "$(printf '%s' "$health" | jq -r '.checks.chrome_devtools_headless.status')" = healthy ] || fail 'healthy browser flags failed'
TEST_CHROME_ARGS='--no-sandbox --disable-dev-shm-usage'
health=$(run_checker --health --json)
[ "$(printf '%s' "$health" | jq -r '.checks.chrome_devtools_headless.status')" = broken ] || fail 'missing browser flag was hidden'
unset TEST_CHROME_ARGS
pass 'health mode remains local and deterministic'

# The Nix wrapper prepends `export DEV_TOOLS_*=/nix/store/...` lines and its own
# interpreter line ahead of this script's body, so --help must stay anchored to
# the header instead of "everything from line 2".
PACKAGED_CHECKER="$FIXTURE/packaged-dev-tools-check-updates"
{
  printf '#!/usr/bin/env bash\n'
  printf 'export DEV_TOOLS_PINS_FILE=/nix/store/aaaaaaaa-dev-tools-versions.sh\n'
  printf 'export DEV_TOOLS_FLAKE_LOCK_FILE=/nix/store/bbbbbbbb-flake.lock\n'
  printf 'export DEV_TOOLS_NVIM_LOCK_FILE=/nix/store/cccccccc-nvim-lazy-lock.json\n'
  cat "$CHECKER"
} >"$PACKAGED_CHECKER"
chmod +x "$PACKAGED_CHECKER"
packaged_help=$("$PACKAGED_CHECKER" --help)
[ "$(printf '%s\n' "$packaged_help" | head -1)" = "$("$CHECKER" --help | head -1)" ] || fail 'the packaged --help does not start with the usage header'
if printf '%s\n' "$packaged_help" | grep -Eq '/nix/store/|env bash'; then
  fail 'the packaged --help leaks wrapper exports or the interpreter line'
fi
case "$packaged_help" in *'Usage: dev-tools-check-updates [--json]'*) : ;; *) fail 'the packaged --help omits the usage line' ;; esac
pass 'the packaged --help prints only the operator contract'

# ------------------- closure rows are immune to the ambient PATH

# These reach the operator only through a wrapper's own PATH, so the audit has to
# read the store path the generated manifest binds. Every one of their ambient
# commands answers 0.0.1 above, so a PATH measurement would show up here.
json=$(run_checker --json --force --no-cache)
for row in "${CLOSURE_ROWS[@]}"; do
  IFS='|' read -r package command_name version <<<"$row"
  entry=$(printf '%s' "$json" | jq -ce --arg n "nix:$package" '.tools[] | select(.name == $n)') \
    || fail "the inventory omits nix:$package"
  [ "$(printf '%s' "$entry" | jq -r '.current')" = "$version" ] \
    || fail "nix:$package was measured as $(printf '%s' "$entry" | jq -r '.current') instead of the closure's $version"
  [ "$(printf '%s' "$entry" | jq -r '.status')" = up_to_date ] \
    || fail "nix:$package is not up_to_date against its own closure"
  [ "$(printf '%s' "$entry" | jq -r '.source')" = nixpkgs-locked-closure ] \
    || fail "nix:$package does not label its evidence source distinctly"
  [ "$command_name" = git ] || [ "$command_name" = curl ] || {
    [ "$("$FAKEBIN/$command_name" | awk '{print $2}')" = 0.0.1 ] \
      || fail "the hostile ambient stub for $command_name is not actually hostile"
  }
done
pass 'closure Nix rows are measured from the bound store path and are immune to the ambient PATH'

# A user-environment row is the opposite contract: the operator's own command is
# the pinned one, so drift there has to surface.
rm -f "$FAKEBIN/node"
printf '#!%s\nprintf "v20.0.0\\n"\n' "$BASH_BIN" >"$FAKEBIN/node"
chmod +x "$FAKEBIN/node"
json=$(run_checker --json --force --no-cache)
node_entry=$(printf '%s' "$json" | jq -ce '.tools[] | select(.name == "nix:nodejs_22")')
[ "$(printf '%s' "$node_entry" | jq -r '.current')" = 20.0.0 ] \
  || fail 'a user-environment Nix row was not measured from the command the operator runs'
[ "$(printf '%s' "$node_entry" | jq -r '.status')" = drifted ] || fail 'user-environment drift was not reported'
[ "$(printf '%s' "$node_entry" | jq -r '.source')" = nixpkgs-locked-stable ] \
  || fail 'a user-environment row does not keep its own evidence source'
ln -sf tool-version "$FAKEBIN/node"
pass 'user-environment Nix rows keep their ambient measurement and still expose drift'

# A repository-checkout run binds no manifest, so there is no closure to measure
# and the honest answer is unknown - never a reading of an unrelated build.
json=$(TEST_CLOSURE_FILE='' run_checker --json --force --no-cache)
for row in "${CLOSURE_ROWS[@]}"; do
  IFS='|' read -r package _command_name _version <<<"$row"
  entry=$(printf '%s' "$json" | jq -ce --arg n "nix:$package" '.tools[] | select(.name == $n)')
  [ "$(printf '%s' "$entry" | jq -r '.current')" = unknown ] \
    || fail "nix:$package fell back to the ambient PATH without a closure manifest: $(printf '%s' "$entry" | jq -r '.current')"
  printf '%s' "$entry" | jq -e '.detail | test("no closure measurement manifest is bound")' >/dev/null \
    || fail "nix:$package did not say why it could not be measured"
done
[ "$(printf '%s' "$json" | jq -r '.tools[] | select(.name == "nix:nodejs_22") | .current')" != unknown ] \
  || fail 'the missing manifest also suppressed a user-environment measurement'
pass 'a run with no closure manifest reports every closure row unknown instead of measuring the wrong binary'

# Manifest data that cannot bind the package is the same refusal, named.
BROKEN_MANIFEST="$FIXTURE/broken-closure.json"
printf 'not json\n' >"$BROKEN_MANIFEST"
json=$(TEST_CLOSURE_FILE="$BROKEN_MANIFEST" run_checker --json --force --no-cache)
gzip_entry=$(printf '%s' "$json" | jq -ce '.tools[] | select(.name == "nix:gzip")')
[ "$(printf '%s' "$gzip_entry" | jq -r '.current')" = unknown ] || fail 'a malformed closure manifest was measured anyway'
printf '%s' "$gzip_entry" | jq -e '.detail | test("malformed")' >/dev/null \
  || fail 'a malformed closure manifest did not say so'

printf '%s\n' '[{"name":"gzip","version":"1.14","store_path":"/nonexistent/gzip"}]' >"$BROKEN_MANIFEST"
json=$(TEST_CLOSURE_FILE="$BROKEN_MANIFEST" run_checker --json --force --no-cache)
gzip_entry=$(printf '%s' "$json" | jq -ce '.tools[] | select(.name == "nix:gzip")')
[ "$(printf '%s' "$gzip_entry" | jq -r '.current')" = unknown ] || fail 'a missing bound path was measured anyway'
printf '%s' "$gzip_entry" | jq -e '.detail | test("does not carry an executable")' >/dev/null \
  || fail 'a missing bound executable did not say so'
pass 'a manifest that cannot bind a closure package reports unknown with the reason'

printf '\nall dev-tools-check-updates tests passed\n'
