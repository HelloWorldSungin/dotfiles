#!/usr/bin/env bash
# Behavioral deployment tests for the official, opt-in Kun skill loader.
#
# The loader itself is an intentional user-visible instruction contract, not an
# executable client. Therefore the test obtains each deployed file from the
# real Home Manager generation and verifies its bytes against the reviewed
# upstream loader digest. This proves that ordinary generation/deployment only
# exposes the inert loader; network retrieval is deferred to explicit /kun.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG='homeConfigurations."sungin@ct110".config'
EXPECTED_SHA256=37864c82e1d8b73a153fbad9d9b88d2ab62278867b051cdf884ed16d258af0d0
LOADER="$ROOT/skills/kun/SKILL.md"

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v nix >/dev/null 2>&1 || fail 'missing test dependency: nix'
command -v sha256sum >/dev/null 2>&1 || fail 'missing test dependency: sha256sum'
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

# Materialize the Home Manager generation without activating it. Its declared
# file sources are store objects, so evaluating their paths alone does not make
# them available for byte-for-byte deployment checks.
nix build --no-link "$ROOT#homeConfigurations.\"sungin@ct110\".activationPackage" \
  || fail 'Home Manager cannot build the Kun deployment generation'
pass 'Home Manager builds the Kun deployment generation without activation'

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

# A normal Home Manager evaluation reads only the static loader. Its content is
# byte-identical to the official loader, whose public contract makes fetching
# conditional on explicit /kun and supplies the visible no-guess refusal when
# both sources fail. These are properties of the exact delivered contract, not
# a fabricated local fetch implementation.
python3 - "$LOADER" <<'PY' || fail 'the deployed loader is not an opt-in Agent Skill contract'
import sys
from pathlib import Path

loader = Path(sys.argv[1]).read_text()
frontmatter, body = loader.split('---', 2)[1:]
if 'user-invocable: true' not in frontmatter:
    raise SystemExit('loader is not user-invocable')
if 'Use on /kun' not in frontmatter:
    raise SystemExit('loader does not limit activation to /kun')
if 'If the files cannot be fetched, stop and say so. Do not guess file contents.' not in body:
    raise SystemExit('loader lost the official visible no-guess refusal')
if body.count('https://raw.githubusercontent.com/kunchenguid/kun/main/') != 4:
    raise SystemExit('loader no longer defers all four living documents to invocation time')
PY
pass 'the deployed official contract is user-invocable, fetches only on /kun, and visibly refuses unavailable content'

printf 'kun skill tests passed\n'
