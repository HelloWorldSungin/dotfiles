#!/usr/bin/env bash
# Behavioral deployment tests for the official, opt-in Kun skill loader.
#
# The loader itself is an intentional user-visible instruction contract, not an
# executable client. The test obtains each deployed file from Home Manager,
# verifies its reviewed upstream digest, and drives Pi's RPC interface to prove
# that startup exposes only skill metadata while explicit invocation emits the
# full reviewed contract.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG='homeConfigurations."sungin@ct110".config'
EXPECTED_SHA256=37864c82e1d8b73a153fbad9d9b88d2ab62278867b051cdf884ed16d258af0d0
EXPECTED_EXPANDED_SHA256=b8e72f01509f156baa14f859153d9b4c729e3d762fbb43c787e3c96c6fc9ad35
LOADER="$ROOT/skills/kun/SKILL.md"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/kun-skill-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v nix >/dev/null 2>&1 || fail 'missing test dependency: nix'
command -v sha256sum >/dev/null 2>&1 || fail 'missing test dependency: sha256sum'
command -v jq >/dev/null 2>&1 || fail 'missing test dependency: jq'
command -v pi >/dev/null 2>&1 || fail 'missing test dependency: pi'
[ -f "$LOADER" ] || fail 'the repository Kun loader is missing'

hash_file() { sha256sum "$1" | awk '{print $1}'; }
assert_hash() {
  [ "$(hash_file "$1")" = "$EXPECTED_SHA256" ] \
    || fail "$2 does not match the reviewed official loader"
}

# Ask Home Manager, the deployment consumer, for each source. The source value
# is a real path selected by the generated configuration, not a source-tree
# convention reconstructed by this test.
hm_source() {
  nix build --no-link --print-out-paths "$ROOT#$CONFIG.home.file.\"$1\".source"
}

assert_hash "$LOADER" 'the repository loader'
pass 'the repository loader matches the reviewed official upstream content hash'

paths=(
  '.claude/skills/kun/SKILL.md'
  '.pi/agent/skills/kun/SKILL.md'
  '.agents/skills/kun/SKILL.md'
)
sources=()
for path in "${paths[@]}"; do
  source=$(hm_source "$path") || fail "Home Manager has no Kun deployment for $path"
  [ -L "$source" ] || fail "Home Manager does not deploy $path as a declarative link: $source"
  sources+=("$(readlink "$source")")
done
[ "${sources[0]}" = "${sources[1]}" ] && [ "${sources[1]}" = "${sources[2]}" ] \
  || fail 'the three global Kun paths do not resolve to one loader'
[ "${sources[0]}" = '/home/sungin/dotfiles/skills/kun/SKILL.md' ] \
  || fail "the global Kun paths resolve to an unexpected loader: ${sources[0]}"
pass 'Claude, Pi, and generic global paths resolve to the same intended loader'

# Probe the supported skill host at the boundaries immediately before a model
# would run. The startup command records Pi's structured skill inventory and
# whether the full instruction body reached its system prompt. Explicit skill
# invocation records Pi's expanded user prompt, then exits before any provider
# or network tool can run.
cat >"$TMP_ROOT/probe.ts" <<'TS'
import { readFileSync, writeFileSync } from "node:fs";

export default function (pi: any) {
  pi.registerProvider("kun-test", {
    baseUrl: "http://127.0.0.1:9",
    apiKey: "KUN_TEST_API_KEY",
    api: "openai-completions",
    models: [{
      id: "probe",
      name: "Kun test probe",
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 4096,
      maxTokens: 64,
    }],
  });

  pi.registerCommand("capture-kun-startup", {
    handler: async (_args: string, ctx: any) => {
      const skills = ctx.getSystemPromptOptions().skills ?? [];
      const kun = skills.find((skill: any) => skill.name === "kun");
      const document = kun ? readFileSync(kun.filePath, "utf8") : "";
      writeFileSync(process.env.KUN_PROBE_FILE!, JSON.stringify({
        kun,
        fullDocumentVisible: document !== "" && ctx.getSystemPrompt().includes(document),
      }));
      process.exit(0);
    },
  });

  pi.on("before_agent_start", async (event: any) => {
    writeFileSync(process.env.KUN_PROBE_FILE!, event.prompt);
    process.exit(0);
  });
}
TS

run_pi_probe() {
  local message=$1 output=$2
  printf '{"type":"prompt","message":"%s"}\n' "$message" |
    KUN_PROBE_FILE="$output" KUN_TEST_API_KEY=test \
      pi --mode rpc --offline --no-session --provider kun-test --model probe \
      --no-context-files --no-prompt-templates --no-themes --no-extensions \
      --no-skills --skill "$LOADER" --extension "$TMP_ROOT/probe.ts" \
      >/dev/null 2>"$TMP_ROOT/pi.stderr" \
    || fail "Pi failed while probing $message"
  [ -s "$output" ] || fail "Pi produced no probe result for $message"
}

run_pi_probe '/capture-kun-startup' "$TMP_ROOT/startup.json"
if ! jq -e --arg loader "$LOADER" '
  .fullDocumentVisible == false and
  .kun.name == "kun" and
  .kun.filePath == $loader and
  .kun.disableModelInvocation == false and
  .kun.description == "Summon Kun to solve your problems. Use on /kun or when asked how Kun thinks, builds, or solves problems.\n"
' "$TMP_ROOT/startup.json" >/dev/null; then
  jq . "$TMP_ROOT/startup.json" >&2
  fail 'ordinary startup did not expose only the official Kun activation metadata'
fi
pass 'ordinary startup exposes Kun only for explicit invocation or a matching user request'

run_pi_probe '/skill:kun' "$TMP_ROOT/invocation.txt"
normalized=$(sed "s#$ROOT#<ROOT>#g" "$TMP_ROOT/invocation.txt" | sha256sum | awk '{print $1}')
if [ "$normalized" != "$EXPECTED_EXPANDED_SHA256" ]; then
  sed "s#$ROOT#<ROOT>#g" "$TMP_ROOT/invocation.txt" >&2
  fail "explicit Kun invocation emitted unexpected contract digest: $normalized"
fi
pass 'explicit invocation emits the reviewed visible refusal contract before any model call'

printf 'kun skill tests passed\n'
