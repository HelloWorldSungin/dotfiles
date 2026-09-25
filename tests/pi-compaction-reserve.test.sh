#!/usr/bin/env bash
# Behavior tests for bin/pi-set-compaction-reserve: the atomic, idempotent merge
# of three per-model compaction reserves into a machine-maintained settings.json,
# then the installed Pi package's resolved trigger
# (contextTokens > contextWindow - reserveTokens) for those models and for a
# model that must keep the ordinary reserve.
# No test touches the real ~/.pi; every case uses a temp file.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MERGE="$ROOT/bin/pi-set-compaction-reserve"
MODELS_JSON="$ROOT/pi/models.json"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/pi-compaction-reserve-tests.XXXXXX")
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
  PI_SETTINGS_FILE="$1" bash "$MERGE"
}

# ------------------------------------------------ merge into existing settings
case_dir="$TMP_ROOT/existing"
mkdir -p "$case_dir"
settings="$case_dir/settings.json"
cat > "$settings" <<'JSON'
{
  "lastChangelogVersion": "0.87.0",
  "theme": "dark",
  "defaultProvider": "openai-codex",
  "defaultModel": "gpt-6-astra",
  "defaultThinkingLevel": "low",
  "compaction": {
    "enabled": true,
    "reserveTokens": 20000,
    "keepRecentTokens": 8000,
    "modelOverrides": {
      "openai-codex/gpt-5.6-luna": { "reserveTokens": 4096 },
      "openai-codex/gpt-6-astra": { "keepRecentTokens": 3000 }
    }
  },
  "branchSummary": { "reserveTokens": 8192, "skipPrompt": true }
}
JSON
inode_before=$(stat -c %i "$settings")
run_merge "$settings" || fail "merge into an existing settings.json failed"
assert_eq "$(jq -r '.theme' "$settings")" "dark" "theme preserved"
assert_eq "$(jq -r '.defaultModel' "$settings")" "gpt-6-astra" "default model preserved"
assert_eq "$(jq -r '.compaction.enabled' "$settings")" "true" "compaction.enabled preserved"
assert_eq "$(jq -r '.compaction.reserveTokens' "$settings")" "20000" "ordinary reserve preserved"
assert_eq "$(jq -r '.compaction.keepRecentTokens' "$settings")" "8000" "ordinary keepRecentTokens preserved"
assert_eq "$(jq -r '.compaction.modelOverrides["openai-codex/gpt-5.6-luna"].reserveTokens' "$settings")" \
  "4096" "unrelated model override preserved"
assert_eq "$(jq -r '.compaction.modelOverrides["openai-codex/gpt-6-astra"].keepRecentTokens' "$settings")" \
  "3000" "same-model keepRecentTokens preserved"
for model in openai-codex/gpt-5.6-sol openai-codex/gpt-5.6-terra openai-codex/gpt-6-astra; do
  assert_eq "$(jq -r --arg m "$model" '.compaction.modelOverrides[$m].reserveTokens' "$settings")" \
    "372000" "$model reserveTokens"
done
assert_eq "$(jq -c '.branchSummary' "$settings")" '{"reserveTokens":8192,"skipPrompt":true}' "branch summary preserved"
[ "$(stat -c %i "$settings")" != "$inode_before" ] \
  || fail "the merge did not rewrite the settings, so a no-op cannot be distinguished"
pass "owned reserves are 372000 and unrelated settings survive"

# ------------------------------------------------------------- idempotence
inode1=$(stat -c %i "$settings")
sum1=$(cksum < "$settings")
for run in 2 3; do
  run_merge "$settings" || fail "repeat merge $run failed"
  assert_eq "$(stat -c %i "$settings")" "$inode1" "run $run must not rewrite the file"
  assert_eq "$(cksum < "$settings")" "$sum1" "run $run must not change the file"
done
pass "repeat runs are a no-op"

# ----------------------------------------------------------- absent settings
fresh="$TMP_ROOT/fresh/settings.json"
run_merge "$fresh" || fail "merge into an absent settings.json failed"
assert_eq "$(jq -c '.' "$fresh")" \
  '{"compaction":{"modelOverrides":{"openai-codex/gpt-5.6-sol":{"reserveTokens":372000},"openai-codex/gpt-5.6-terra":{"reserveTokens":372000},"openai-codex/gpt-6-astra":{"reserveTokens":372000}}}}' \
  "fresh settings.json"
pass "absent settings.json is created with only the owned reserves"

# --------------------------------------------------------- invalid settings
invalid="$TMP_ROOT/invalid.json"
printf '{ not json\n' > "$invalid"
if run_merge "$invalid" 2>/dev/null; then
  fail "invalid settings.json must be refused"
fi
assert_eq "$(cat "$invalid")" "{ not json" "invalid settings.json left untouched"
pass "invalid settings.json is refused and left untouched"

wrong_type="$TMP_ROOT/wrong-type.json"
printf '%s\n' '{"theme":"dark","compaction":{"modelOverrides":{"openai-codex/gpt-6-astra":"nope"}}}' > "$wrong_type"
before=$(cat "$wrong_type")
if run_merge "$wrong_type" 2>/dev/null; then
  fail "a non-object model override must be refused"
fi
assert_eq "$(cat "$wrong_type")" "$before" "non-object model override left untouched"
pass "a non-object model override is refused and left untouched"

# ----------------------------- installed Pi resolves the trigger per model
command -v node >/dev/null 2>&1 || fail "missing test dependency: node"
PI_PKG="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}/lib/node_modules/@earendil-works/pi-coding-agent"
jq -e '.name == "@earendil-works/pi-coding-agent"' "$PI_PKG/package.json" >/dev/null \
  || fail "missing or invalid test dependency: $PI_PKG"

probe_dir="$TMP_ROOT/probe"
mkdir -p "$probe_dir"
cp "$MODELS_JSON" "$probe_dir/models.json"
cp "$settings" "$probe_dir/settings.json"
probe_json="$TMP_ROOT/probe.json"
if ! PI_OFFLINE=1 node --input-type=module - "$PI_PKG" "$probe_dir" > "$probe_json" 2>"$probe_dir/probe.err" <<'NODE'
import { join } from "node:path";

const pkg = process.argv[2];
const agentDir = process.argv[3];
const { ModelRuntime, SettingsManager, shouldCompact } = await import(pkg + "/dist/index.js");
const runtime = await ModelRuntime.create({
  modelsPath: join(agentDir, "models.json"),
  authPath: join(agentDir, "auth.json"),
  refreshOnCreate: false,
  allowModelNetwork: false,
});
const manager = SettingsManager.create(agentDir, agentDir);
const targets = ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-6-astra"];
const owned = new Set(targets.map((id) => `openai-codex/${id}`));
const rows = [];
for (const model of runtime.getModels()) {
  const settings = manager.getCompactionSettings(model);
  const threshold = model.contextWindow - settings.reserveTokens;
  rows.push({
    key: `${model.provider}/${model.id}`,
    window: model.contextWindow,
    reserveTokens: settings.reserveTokens,
    keepRecentTokens: settings.keepRecentTokens,
    enabled: settings.enabled,
    threshold,
    compactAtThreshold: shouldCompact(threshold, model.contextWindow, settings),
    compactAtPlusOne: shouldCompact(threshold + 1, model.contextWindow, settings),
    compactAtOne: shouldCompact(1, model.contextWindow, settings),
  });
}
const byKey = Object.fromEntries(rows.map((row) => [row.key, row]));
const drift = rows.filter((row) => {
  if (owned.has(row.key)) return row.reserveTokens !== 372000;
  if (row.key === "openai-codex/gpt-5.6-luna") return row.reserveTokens !== 4096;
  return row.reserveTokens !== 20000;
}).map((row) => row.key);
process.stdout.write(JSON.stringify({
  targets: Object.fromEntries(targets.map((id) => [id, byKey[`openai-codex/${id}`]])),
  luna: byKey["openai-codex/gpt-5.6-luna"],
  drift: drift.slice(0, 8),
  driftCount: drift.length,
}));
NODE
then
  cat "$probe_dir/probe.err" >&2
  fail "Pi compaction probe failed"
fi

python3 - "$probe_json" <<'PY' || fail "Pi trigger assertions failed"
import json, sys
d = json.load(open(sys.argv[1]))
for model_id, row in d["targets"].items():
    assert row["window"] == 872000, (model_id, row)
    assert row["reserveTokens"] == 372000, (model_id, row)
    assert row["threshold"] == 500000, (model_id, row)
    assert row["compactAtThreshold"] is False, (model_id, row)
    assert row["compactAtPlusOne"] is True, (model_id, row)
    assert row["compactAtOne"] is False, (model_id, row)
    assert row["enabled"] is True, (model_id, row)
assert d["targets"]["gpt-6-astra"]["keepRecentTokens"] == 3000
assert d["targets"]["gpt-5.6-sol"]["keepRecentTokens"] == 8000
luna = d["luna"]
assert luna["window"] == 272000, luna
assert luna["reserveTokens"] == 4096, luna
assert luna["threshold"] == 272000 - 4096, luna
assert luna["compactAtOne"] is False, luna
assert luna["compactAtThreshold"] is False, luna
assert luna["compactAtPlusOne"] is True, luna
assert d["driftCount"] == 0, d
PY
pass "Pi triggers the three models above 500000 and leaves every other model on its ordinary reserve"

# A settings file with no ordinary reserve still leaves non-targets on 16384,
# including Luna and a model whose window is smaller than 372000.
plain="$TMP_ROOT/plain"
mkdir -p "$plain"
cp "$MODELS_JSON" "$plain/models.json"
run_merge "$plain/settings.json" || fail "plain settings merge failed"
plain_json="$TMP_ROOT/plain.json"
PI_OFFLINE=1 node --input-type=module - "$PI_PKG" "$plain" > "$plain_json" <<'NODE' \
  || fail "plain-reserve probe failed"
import { join } from "node:path";
const pkg = process.argv[2];
const agentDir = process.argv[3];
const { ModelRuntime, SettingsManager, shouldCompact } = await import(pkg + "/dist/index.js");
const runtime = await ModelRuntime.create({
  modelsPath: join(agentDir, "models.json"),
  authPath: join(agentDir, "auth.json"),
  refreshOnCreate: false,
  allowModelNetwork: false,
});
const manager = SettingsManager.create(agentDir, agentDir);
const owned = new Set([
  "openai-codex/gpt-5.6-sol",
  "openai-codex/gpt-5.6-terra",
  "openai-codex/gpt-6-astra",
]);
const bad = [];
let luna = null;
let small = null;
for (const model of runtime.getModels()) {
  const key = `${model.provider}/${model.id}`;
  const settings = manager.getCompactionSettings(model);
  const threshold = model.contextWindow - settings.reserveTokens;
  if (key === "openai-codex/gpt-5.6-luna") luna = { key, window: model.contextWindow, reserveTokens: settings.reserveTokens, threshold, compactAtOne: shouldCompact(1, model.contextWindow, settings) };
  if (key === "openai/gpt-4") small = { key, window: model.contextWindow, reserveTokens: settings.reserveTokens, threshold, compactAtOne: shouldCompact(1, model.contextWindow, settings) };
  if (owned.has(key)) continue;
  if (settings.reserveTokens !== 16384) bad.push(key);
}
process.stdout.write(JSON.stringify({ luna, small, badCount: bad.length, bad: bad.slice(0, 5) }));
NODE
python3 - "$plain_json" <<'PY' || fail "plain-reserve assertions failed"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["luna"]["window"] == 272000, d["luna"]
assert d["luna"]["reserveTokens"] == 16384, d["luna"]
assert d["luna"]["threshold"] == 255616, d["luna"]
assert d["luna"]["compactAtOne"] is False, d["luna"]
assert d["small"]["window"] == 8192, d["small"]
assert d["small"]["reserveTokens"] == 16384, d["small"]
assert d["badCount"] == 0, d
PY
pass "without an ordinary reserve, Luna and other models stay on the built-in 16384"

printf '\nall Pi compaction reserve tests passed\n'
