#!/usr/bin/env bash
# Behavior tests for the GPT long-context configuration (GPT-5.6 Sol/Terra and
# GPT-6 Astra):
#   - pi/models.json: the exact three openai-codex modelOverrides.
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
    "1050000" "$model contextWindow is 1050000"
  assert_eq "$(jq -r --arg m "$model" '.providers["openai-codex"].modelOverrides[$m] | keys | join(",")' "$MODELS_JSON")" \
    "contextWindow" "$model overrides only contextWindow"
done
pass "Sol, Terra and Astra each override only contextWindow, to 1050000"

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

# Codex has no per-model mechanism: the one global key is what covers Astra, so
# the config must carry exactly one context-window key and no per-model table.
assert_eq "$(grep -c '^model_context_window' "$cfg4")" "1" \
  "Codex context window is configured exactly once, globally"
! grep -q 'gpt-6-astra' "$cfg4" \
  || fail "the Codex merge must not invent a per-model Astra setting"
pass "Codex Astra coverage comes from the single global key, not a per-model one"

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
