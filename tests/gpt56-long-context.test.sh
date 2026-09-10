#!/usr/bin/env bash
# Behavior tests for the GPT long-context configuration (GPT-5.6 Sol/Terra and
# GPT-6 Astra):
#   - pi/models.json: the exact three openai-codex modelOverrides.
#   - the installed Pi package (from the npm prefix) applying them, and its
#     shouldCompact threshold at contextWindow minus the configured reserve.
#   - bin/codex-set-context-window: the narrowly scoped, atomic, idempotent
#     merge of the single owned key into a machine-maintained config.toml.
# No test touches the real ~/.codex or ~/.pi; every case uses a temp file.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODELS_JSON="$ROOT/pi/models.json"
MERGE="$ROOT/bin/codex-set-context-window"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gpt56-long-context-tests.XXXXXX")
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

# --------------------------------------------------------------- pi models.json

jq -e . "$MODELS_JSON" >/dev/null 2>&1 || fail "pi/models.json is not valid JSON"
pass "pi/models.json is valid JSON"

assert_eq "$(jq -r '.providers | keys | join(",")' "$MODELS_JSON")" \
  "openai-codex" "pi/models.json configures only the openai-codex provider"
pass "pi/models.json configures only the openai-codex provider"

assert_eq "$(jq -r '.providers["openai-codex"].modelOverrides | keys | sort | join(",")' "$MODELS_JSON")" \
  "gpt-5.6-sol,gpt-5.6-terra,gpt-6-astra" "modelOverrides covers exactly Sol, Terra and Astra"
pass "modelOverrides covers exactly Sol, Terra and Astra"

for model in gpt-5.6-sol gpt-5.6-terra gpt-6-astra; do
  assert_eq "$(jq -r --arg m "$model" '.providers["openai-codex"].modelOverrides[$m].contextWindow' "$MODELS_JSON")" \
    "872000" "$model contextWindow is 872000"
  assert_eq "$(jq -r --arg m "$model" '.providers["openai-codex"].modelOverrides[$m] | keys | join(",")' "$MODELS_JSON")" \
    "contextWindow" "$model overrides only contextWindow"
done
pass "Sol, Terra and Astra each override only contextWindow, to 872000"

# The overrides must not touch model selection, effort, or any unrelated model
# such as Luna.
has_default_model_or_effort() {
  jq -e '[.. | objects | has("model") or has("reasoningEffort")] | any' "$1" >/dev/null 2>&1
}

# Negative controls: the guard itself must fire on a document that violates it.
probe="$TMP_ROOT/default-probe.json"
for probe_json in \
  '{"model":"gpt-5.6-sol","providers":{"openai-codex":{"modelOverrides":{"gpt-5.6-sol":{"contextWindow":1050000}}}}}' \
  '{"providers":{"openai-codex":{"modelOverrides":{"gpt-5.6-sol":{"contextWindow":1050000,"reasoningEffort":"high"}}}}}'
do
  printf '%s\n' "$probe_json" > "$probe"
  has_default_model_or_effort "$probe" \
    || fail "the default model/effort guard is inert on: $probe_json"
done
pass "the default model/effort guard fires on a root model and on a nested effort"

! has_default_model_or_effort "$MODELS_JSON" \
  || fail "pi/models.json must not set a default model or effort"

# Luna, and every other unrelated model, is left alone: the provider object
# carries only the three overrides already pinned above.
assert_eq "$(jq -r '.providers["openai-codex"] | keys | join(",")' "$MODELS_JSON")" \
  "modelOverrides" "the openai-codex provider carries nothing but modelOverrides"
pass "pi/models.json changes no default model, effort, or Luna"

# Pi's installed ModelRuntime applies models.json, SettingsManager supplies the
# configured reserve, and shouldCompact is the same predicate the session uses.
# Live provider probes stay out of this suite.
command -v node >/dev/null 2>&1 || fail "missing test dependency: node"
PI_PKG="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}/lib/node_modules/@earendil-works/pi-coding-agent"
jq -e '.name == "@earendil-works/pi-coding-agent"' "$PI_PKG/package.json" >/dev/null \
  || fail "missing or invalid test dependency: $PI_PKG"

pi_compact_probe() {
  local models_json=$1
  local settings_json=$2
  local agent_dir
  agent_dir=$(mktemp -d "$TMP_ROOT/pi-compact.XXXXXX")
  cp "$models_json" "$agent_dir/models.json"
  printf '%s\n' "$settings_json" > "$agent_dir/settings.json"
  if ! PI_CODING_AGENT_DIR="$agent_dir" PI_OFFLINE=1 node --input-type=module - "$PI_PKG" "$agent_dir" 2>"$agent_dir/probe.err" <<'NODE'
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
const settings = SettingsManager.create(agentDir, agentDir).getCompactionSettings();
const ids = ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-6-astra"];
const windows = {};
for (const id of ids) {
  const model = runtime.getModel("openai-codex", id);
  windows[id] = model?.contextWindow ?? null;
}
const sol = runtime.getModel("openai-codex", "gpt-5.6-sol");
const luna = runtime.getModel("openai-codex", "gpt-5.6-luna");
const window = windows["gpt-5.6-sol"];
const threshold = window - settings.reserveTokens;
process.stdout.write(JSON.stringify({
  windows,
  lunaWindow: luna?.contextWindow ?? null,
  solMaxTokens: sol?.maxTokens ?? null,
  solApi: sol?.api ?? null,
  solProvider: sol?.provider ?? null,
  reserveTokens: settings.reserveTokens,
  enabled: settings.enabled,
  threshold,
  compactAtEq: shouldCompact(threshold, window, settings),
  compactAtPlusOne: shouldCompact(threshold + 1, window, settings),
  compactAt909436: shouldCompact(909436, window, settings),
  compactDisabled: shouldCompact(threshold + 1, window, { ...settings, enabled: false }),
}));
NODE
  then
    cat "$agent_dir/probe.err" >&2
    return 1
  fi
}

accepted_json="$TMP_ROOT/accepted-compact.json"
pi_compact_probe "$MODELS_JSON" '{"theme":"dark"}' > "$accepted_json" \
  || fail "Pi ModelRuntime/shouldCompact probe failed"
python3 - "$accepted_json" <<'PY' || fail "accepted Pi compaction consumer assertions failed"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["windows"] == {
    "gpt-5.6-sol": 872000,
    "gpt-5.6-terra": 872000,
    "gpt-6-astra": 872000,
}, d["windows"]
assert d["lunaWindow"] == 272000, d["lunaWindow"]
assert d["solMaxTokens"] == 128000, d["solMaxTokens"]
assert d["solApi"] == "openai-codex-responses", d["solApi"]
assert d["solProvider"] == "openai-codex", d["solProvider"]
assert d["reserveTokens"] == 16384, d["reserveTokens"]
assert d["enabled"] is True
assert d["threshold"] == 872000 - 16384 == 855616, d["threshold"]
assert d["compactAtEq"] is False
assert d["compactAtPlusOne"] is True
assert d["compactAt909436"] is True
assert d["compactDisabled"] is False
PY
pass "Pi applies 872000 and compacts above contextWindow minus the default reserve"

# Negative control: the defective 1,050,000 declaration leaves the historically
# accepted 909,436-token request below the compact threshold.
bad_models="$TMP_ROOT/bad-models.json"
jq '.providers["openai-codex"].modelOverrides |= with_entries(.value.contextWindow=1050000)' \
  "$MODELS_JSON" > "$bad_models"
bad_json="$TMP_ROOT/bad-compact.json"
pi_compact_probe "$bad_models" '{"theme":"dark"}' > "$bad_json" \
  || fail "defective-declaration probe failed"
python3 - "$bad_json" <<'PY' || fail "1,050,000 negative control failed"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["windows"]["gpt-5.6-sol"] == 1050000, d["windows"]
assert d["threshold"] == 1050000 - 16384 == 1033616, d["threshold"]
assert d["compactAtEq"] is False
assert d["compactAtPlusOne"] is True
assert d["compactAt909436"] is False, "1,050,000 must not compact a 909,436-token request"
assert d["lunaWindow"] == 272000
assert d["solMaxTokens"] == 128000
PY
pass "a 1,050,000 override does not compact at 909,436 (negative control)"

# Negative control: a configured reserve, not the default, moves the threshold.
custom_json="$TMP_ROOT/custom-compact.json"
pi_compact_probe "$MODELS_JSON" '{"theme":"dark","compaction":{"reserveTokens":20000}}' \
  > "$custom_json" || fail "custom-reserve probe failed"
python3 - "$custom_json" <<'PY' || fail "configured-reserve negative control failed"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["reserveTokens"] == 20000, d["reserveTokens"]
assert d["threshold"] == 872000 - 20000 == 852000, d["threshold"]
assert d["compactAtEq"] is False
assert d["compactAtPlusOne"] is True
PY
pass "shouldCompact uses the configured reserve, not a hard-coded 16384"

# ------------------------------------------------- codex config.toml merge

run_merge() {
  CODEX_CONFIG_FILE="$1" CODEX_MODEL_CONTEXT_WINDOW=872000 "$MERGE"
}

# A realistic machine-maintained config: top-level keys, then nested tables,
# quoted-path project trust entries, and an array of tables.
fixture() {
  cat <<'TOML'
model = "gpt-5.6-sol"
model_reasoning_effort = "high"

[features]
hooks = true

[projects."/home/sungin/firstmate"]
trust_level = "trusted"

[[mcp_servers]]
name = "example"

[tui.theme]
name = "dark"
TOML
}

cfg="$TMP_ROOT/config.toml"
fixture > "$cfg"
before=$(cat "$cfg")
inode_before=$(stat -c %i "$cfg")

run_merge "$cfg" || fail "merge failed on a populated config"

grep -qx 'model_context_window = 872000' "$cfg" \
  || fail "merge did not write model_context_window = 872000"
pass "merge writes model_context_window = 872000"

# The key must land in the top-level region, before the first table header.
key_line=$(grep -n '^model_context_window' "$cfg" | cut -d: -f1)
table_line=$(grep -n '^\[' "$cfg" | head -1 | cut -d: -f1)
[ "$key_line" -lt "$table_line" ] \
  || fail "model_context_window must precede the first table header"
pass "model_context_window is placed in the top-level region"

# Every pre-existing line survives byte-identically, in order.
after_without_key=$(grep -v '^model_context_window = 872000$' "$cfg")
assert_eq "$after_without_key" "$before" "unrelated config content is preserved verbatim"
pass "all unrelated and nested TOML content is preserved verbatim"

# The merge replaces the file by rename, so a run that really wrote is visible
# as a new inode. That is what makes the no-op assertion below falsifiable.
inode1=$(stat -c %i "$cfg")
[ "$inode1" != "$inode_before" ] \
  || fail "the merge did not rewrite the config, so a no-op cannot be distinguished"
pass "a merge that has work to do replaces the config atomically"

# Idempotence: a second and third run do not rewrite the file at all. The inode
# is checked after every run, not once at the end: a rename frees an inode that
# the next mktemp reclaims, so an even number of rewrites lands back on inode1.
sum1=$(cksum < "$cfg")
for run in 2 3; do
  run_merge "$cfg" || fail "repeat merge $run failed"
  assert_eq "$(stat -c %i "$cfg")" "$inode1" "run $run must not rewrite the file"
  assert_eq "$(cksum < "$cfg")" "$sum1" "run $run must not change the file"
done
assert_eq "$(grep -c '^model_context_window' "$cfg")" "1" "the key must not be duplicated"
pass "repeated merges are idempotent and do not rewrite or duplicate the key"

# An existing stale value is updated in place, not appended.
sed -i 's/^model_context_window = 872000$/model_context_window = 272000/' "$cfg"
run_merge "$cfg" || fail "merge failed over a stale value"
assert_eq "$(grep -c '^model_context_window' "$cfg")" "1" "stale value must be replaced, not appended"
grep -qx 'model_context_window = 872000' "$cfg" || fail "stale value was not updated"
pass "an existing value is updated in place"

# A config.toml that opens directly with a table header still gets valid TOML.
cfg2="$TMP_ROOT/table-first.toml"
printf '[features]\nhooks = true\n' > "$cfg2"
run_merge "$cfg2" || fail "merge failed on a table-first config"
assert_eq "$(head -1 "$cfg2")" "model_context_window = 872000" \
  "the key must be prepended above a leading table header"
pass "a table-first config gets the key prepended, keeping it top-level"

# A missing config.toml is created with just the owned key.
cfg3="$TMP_ROOT/missing/config.toml"
run_merge "$cfg3" || fail "merge failed on a missing config"
assert_eq "$(cat "$cfg3")" "model_context_window = 872000" \
  "a missing config is created containing only the owned key"
pass "a missing config.toml is created with only the owned key"

# The value an activation actually writes is the script's own default: nothing
# sets CODEX_MODEL_CONTEXT_WINDOW on the rebuild path, and every assertion above
# pins it. `env -u` keeps that hermetic while covering the committed value -
# Codex's advertised maximum for Sol, Terra, Luna and Astra.
cfg4="$TMP_ROOT/committed-default/config.toml"
env -u CODEX_MODEL_CONTEXT_WINDOW CODEX_CONFIG_FILE="$cfg4" "$MERGE" \
  || fail "merge failed with CODEX_MODEL_CONTEXT_WINDOW unset"
assert_eq "$(cat "$cfg4")" "model_context_window = 872000" \
  "an activation with an empty environment must write Codex's 872000 maximum"
pass "the committed default is 872000, Codex's advertised maximum"

# Astra is covered by that one global key and nothing else. Run the merge over a
# config that already selects Astra - the case where a per-model window would be
# most tempting to write - and assert the merge adds only the top-level key.
per_model_window() {
  # A context window scoped to a model: either a `[...]` table whose header
  # names a model, carrying a window key, or a dotted key like
  # `models.gpt-6-astra.context_window`.
  python3 - "$1" <<'PY_INNER'
import re, sys
table = None
for raw in open(sys.argv[1]):
    line = raw.strip()
    m = re.match(r'^\[+([^\]]+)\]+$', line)
    if m:
        table = m.group(1)
        continue
    key = line.split('=')[0].strip() if '=' in line else ''
    if not key.endswith('context_window'):
        continue
    scope = f"{table}.{key}" if table else key
    if table or '.' in key:
        print(scope)
        sys.exit(0)
sys.exit(1)
PY_INNER
}

# Negative control: the detector must actually fire on both shapes.
probe_toml="$TMP_ROOT/per-model-probe.toml"
for probe_body in \
  'model_context_window = 872000
[models.gpt-6-astra]
context_window = 1050000' \
  'models.gpt-6-astra.context_window = 1050000'
do
  printf '%s\n' "$probe_body" > "$probe_toml"
  per_model_window "$probe_toml" >/dev/null \
    || fail "the per-model-window detector is inert on: $probe_body"
done
pass "the per-model-window detector fires on a scoped table and a dotted key"

cfg5="$TMP_ROOT/astra-selected/config.toml"
mkdir -p "$(dirname "$cfg5")"
printf 'model = "gpt-6-astra"\nmodel_reasoning_effort = "xhigh"\n\n[tui]\ntheme = "dark"\n' > "$cfg5"
run_merge "$cfg5" || fail "merge failed on an Astra-selected config"

assert_eq "$(grep -c 'context_window' "$cfg5")" "1" \
  "Astra's context window is configured exactly once"
! per_model_window "$cfg5" \
  || fail "the merge must not write a per-model Astra context window"
grep -qx 'model_context_window = 872000' "$cfg5" \
  || fail "the global key must cover the selected Astra model"
grep -qx 'model = "gpt-6-astra"' "$cfg5" \
  || fail "selecting Astra must survive the merge"
pass "Astra is covered by the single global key, with no per-model mechanism"

# The merge must never touch model selection or effort.
grep -qx 'model = "gpt-5.6-sol"' "$cfg" || fail "the selected model was altered"
grep -qx 'model_reasoning_effort = "high"' "$cfg" || fail "the reasoning effort was altered"
pass "the merge leaves the selected model and effort untouched"

# ------------------------------------------------------------- TOML syntax

if command -v python3 >/dev/null 2>&1 \
   && python3 -c 'import tomllib' >/dev/null 2>&1; then
  parsed=$(python3 - "$cfg" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as fh:
    data = tomllib.load(fh)
print(data["model_context_window"])
print(data["model"])
print(data["features"]["hooks"])
print(data["projects"]["/home/sungin/firstmate"]["trust_level"])
print(data["tui"]["theme"]["name"])
PY
) || fail "the merged config is not parseable TOML"
  assert_eq "$parsed" "872000
gpt-5.6-sol
True
trusted
dark" "the merged config parses with all nested content intact"
  pass "the merged config is valid TOML with nested content intact"
else
  printf 'skip - tomllib unavailable, syntax check skipped\n'
fi

printf '\nall GPT long-context tests passed\n'
