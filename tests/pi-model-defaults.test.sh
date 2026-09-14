#!/usr/bin/env bash
# Behavior tests for bin/pi-set-model-defaults: the atomic, idempotent merge of
# Pi's three default-model keys into a machine-maintained settings.json, and the
# Firstmate Pi supervision-branch pins. The installed Pi package then resolves
# the rendered settings to the expected default model and thinking level.
# No test touches the real ~/.pi or Firstmate home; every case uses temp paths.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MERGE="$ROOT/bin/pi-set-model-defaults"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/pi-model-defaults-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3 (expected '$2', got '$1')"
}

run_merge() {
  local case_dir=$1
  env -u PI_DEFAULT_PROVIDER -u PI_DEFAULT_MODEL -u PI_DEFAULT_THINKING_LEVEL \
    -u PI_SUPERVISION_MODEL -u PI_SUPERVISION_EFFORT -u PI_CODING_AGENT_DIR \
    HOME="$case_dir/home" \
    PI_SETTINGS_FILE="$case_dir/agent/settings.json" \
    PI_SUPERVISION_FIRSTMATE_HOME="$case_dir/firstmate" \
    bash "$MERGE"
}

# ---------------------------------------------- merge into existing settings
case_dir="$TMP_ROOT/existing"
mkdir -p "$case_dir/agent" "$case_dir/firstmate/config"
cat > "$case_dir/agent/settings.json" <<'JSON'
{
  "lastChangelogVersion": "0.85.1",
  "theme": "dark",
  "defaultProvider": "openai-codex",
  "defaultModel": "gpt-5.6-sol",
  "defaultThinkingLevel": "high",
  "modelThinkingLevels": { "zai/glm-5.2": "max" }
}
JSON
run_merge "$case_dir" || fail "merge into an existing settings.json failed"
settings="$case_dir/agent/settings.json"
assert_eq "$(jq -r '.defaultProvider' "$settings")" "openai-codex" "defaultProvider"
assert_eq "$(jq -r '.defaultModel' "$settings")" "gpt-6-astra" "defaultModel"
assert_eq "$(jq -r '.defaultThinkingLevel' "$settings")" "low" "defaultThinkingLevel"
assert_eq "$(jq -r '.lastChangelogVersion' "$settings")" "0.85.1" "unrelated key preserved"
assert_eq "$(jq -r '.modelThinkingLevels["zai/glm-5.2"]' "$settings")" "max" "per-model override preserved"
pass "settings.json gets gpt-6-astra/low and keeps every other key"

assert_eq "$(cat "$case_dir/firstmate/config/supervision-branch-model")" \
  "openai-codex/gpt-5.6-luna" "supervision model pin"
assert_eq "$(cat "$case_dir/firstmate/config/supervision-branch-effort")" "high" "supervision effort pin"
assert_eq "$(stat -c %a "$case_dir/firstmate/config/supervision-branch-model")" "600" "model pin mode"
assert_eq "$(stat -c %a "$case_dir/firstmate/config/supervision-branch-effort")" "600" "effort pin mode"
[ "$(tail -c1 "$case_dir/firstmate/config/supervision-branch-model" | od -An -c | tr -d ' ')" = '\n' ] \
  || fail "model pin must end in exactly one newline"
pass "supervision pins are openai-codex/gpt-5.6-luna and high, mode 0600"

# ------------------------------------------------------------- idempotence
touch -d '2000-01-01' "$settings" "$case_dir/firstmate/config/supervision-branch-model"
before=$(stat -c %Y "$settings" "$case_dir/firstmate/config/supervision-branch-model")
run_merge "$case_dir" || fail "second merge failed"
assert_eq "$(stat -c %Y "$settings" "$case_dir/firstmate/config/supervision-branch-model")" \
  "$before" "a repeat run must not rewrite unchanged files"
[ -z "$(find "$case_dir" -name '*.json.*' -o -name 'supervision-branch-*.*')" ] \
  || fail "temporary files left behind"
pass "repeat runs are a no-op"

# ------------------------------------------- absent settings, no Firstmate
case_dir="$TMP_ROOT/fresh"
mkdir -p "$case_dir"
run_merge "$case_dir" || fail "merge into an absent settings.json failed"
assert_eq "$(jq -c '.' "$case_dir/agent/settings.json")" \
  '{"defaultProvider":"openai-codex","defaultModel":"gpt-6-astra","defaultThinkingLevel":"low"}' \
  "fresh settings.json"
[ ! -e "$case_dir/firstmate" ] || fail "a host without a Firstmate config dir must be untouched"
pass "absent settings.json is created and a missing Firstmate home is left alone"

# --------------------------------------------------------- invalid settings
case_dir="$TMP_ROOT/invalid"
mkdir -p "$case_dir/agent"
printf '{ not json\n' > "$case_dir/agent/settings.json"
if run_merge "$case_dir" 2>/dev/null; then
  fail "invalid settings.json must be refused"
fi
assert_eq "$(cat "$case_dir/agent/settings.json")" "{ not json" "invalid settings.json left untouched"
pass "invalid settings.json is refused and left untouched"

# ------------------------------------------ Pi resolves the rendered default
command -v node >/dev/null 2>&1 || fail "missing test dependency: node"
PI_PKG="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}/lib/node_modules/@earendil-works/pi-coding-agent"
jq -e '.name == "@earendil-works/pi-coding-agent"' "$PI_PKG/package.json" >/dev/null \
  || fail "missing or invalid test dependency: $PI_PKG"

agent_dir="$TMP_ROOT/existing/agent"
resolved=$(PI_CODING_AGENT_DIR="$agent_dir" PI_OFFLINE=1 node --input-type=module - "$PI_PKG" "$agent_dir" <<'NODE'
import { join } from "node:path";
const [pkg, agentDir] = process.argv.slice(2);
const { ModelRuntime, SettingsManager } = await import(pkg + "/dist/index.js");
const runtime = await ModelRuntime.create({
  modelsPath: join(agentDir, "models.json"),
  authPath: join(agentDir, "auth.json"),
  refreshOnCreate: false,
  allowModelNetwork: false,
});
const settings = SettingsManager.create(agentDir, agentDir);
const provider = settings.getDefaultProvider();
const id = settings.getDefaultModel();
const model = runtime.getModel(provider, id);
const luna = runtime.getModel("openai-codex", "gpt-5.6-luna");
process.stdout.write([
  `${model?.provider}/${model?.id}`,
  settings.getDefaultThinkingLevel(),
  `${luna?.provider}/${luna?.id}`,
  String(Boolean(luna?.reasoning)),
].join(" "));
NODE
) || fail "Pi default-model resolution probe failed"
assert_eq "$resolved" "openai-codex/gpt-6-astra low openai-codex/gpt-5.6-luna true" \
  "Pi resolves the rendered defaults against its catalog"
pass "Pi resolves openai-codex/gpt-6-astra at low, and knows reasoning-capable gpt-5.6-luna"
