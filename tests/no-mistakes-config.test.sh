#!/usr/bin/env bash
# Behavioral tests for the repository-owned .no-mistakes.yaml.
#
# The real v1.72.0 parser is the oracle wherever it can be one: `no-mistakes
# ci-workflow` is the public command that loads and validates the repo config,
# and it is driven here against throwaway git repositories so nothing in this
# checkout is written. It tolerates unknown top-level keys silently, so a typo
# would otherwise be an invisible no-op - the key-set assertion below is what
# catches that, and the negative parse case proves the oracle really is reading
# the file rather than ignoring it.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG="$ROOT/.no-mistakes.yaml"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/no-mistakes-config-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v python3 >/dev/null 2>&1 || fail 'missing test dependency: python3'
python3 -c 'import yaml' >/dev/null 2>&1 || fail 'missing test dependency: python3 with PyYAML'
GIT_BIN=$(command -v git) || fail 'missing test dependency: git'
[ -f "$CONFIG" ] || fail '.no-mistakes.yaml is missing'

# --- shape and invariants, independent of the installed binary -----------------

# Every check below reads the config on stdin with the same two arguments.
py() { python3 - "$CONFIG" "$ROOT"; }

py <<'PY' || fail 'unexpected top-level key set in .no-mistakes.yaml'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
expected = {"commands", "review_agents", "review", "document"}
actual = set(cfg)
if actual != expected:
    print("top-level keys %s, expected %s" % (sorted(actual), sorted(expected)), file=sys.stderr)
    sys.exit(1)
PY
pass 'top-level key set is exactly the reviewed one, so neither a typo nor allow_repo_commands can appear'

py <<'PY' || fail 'commands do not name executable tracked repository scripts'
import os, subprocess, sys, yaml
cfg = yaml.safe_load(open(sys.argv[1])); root = sys.argv[2]
tracked = set(subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True,
                             check=True).stdout.split())
cmds = cfg["commands"]
if set(cmds) != {"test", "lint"}:
    print("commands keys %s" % sorted(cmds), file=sys.stderr); sys.exit(1)
for name, cmd in cmds.items():
    if cmd not in tracked:
        print("commands.%s %r is not a tracked file" % (name, cmd), file=sys.stderr); sys.exit(1)
    if not os.access(os.path.join(root, cmd), os.X_OK):
        print("commands.%s %r is not executable" % (name, cmd), file=sys.stderr); sys.exit(1)
PY
pass 'commands.test and commands.lint name tracked, executable repository entry points'

py <<'PY' || fail 'review_agents does not describe two independent harnesses'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
ra = cfg["review_agents"]
if set(ra) != {"reviewer", "fixer"}:
    print("review_agents roles %s, expected reviewer and fixer" % sorted(ra), file=sys.stderr); sys.exit(1)
# Only claude and codex neutralize a target repository's AGENTS.md/CLAUDE.md; a
# gate agent that does not is refused by no-mistakes in a gated checkout.
neutralizing = {"claude", "codex"}
agents = {}
for role, profile in ra.items():
    agent = (profile or {}).get("agent")
    if not agent:
        print("review_agents.%s has no explicit agent" % role, file=sys.stderr); sys.exit(1)
    if agent == "auto":
        print("review_agents.%s must name an explicit harness, not auto" % role, file=sys.stderr); sys.exit(1)
    if agent not in neutralizing:
        print("review_agents.%s agent %r does not neutralize AGENTS.md" % (role, agent), file=sys.stderr); sys.exit(1)
    agents[role] = agent
if agents["reviewer"] == agents["fixer"]:
    print("reviewer and fixer share harness %r, losing cross-harness independence"
          % agents["reviewer"], file=sys.stderr); sys.exit(1)
PY
pass 'reviewer and fixer name different neutralizing harnesses explicitly'

py <<'PY' || fail 'a review.path_instructions rule matches no tracked file'
import fnmatch, subprocess, sys, yaml
cfg = yaml.safe_load(open(sys.argv[1])); root = sys.argv[2]
tracked = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True,
                         check=True).stdout.split()

def matches(pattern, candidate):
    """Go path.Match semantics, which is what no-mistakes matches these with:
    `*` and `?` never cross `/`, so a pattern binds segment by segment and
    `system/*` matches nothing under system/ct110-network-failover/."""
    pat, name = pattern.split("/"), candidate.split("/")
    return len(pat) == len(name) and all(map(fnmatch.fnmatchcase, name, pat))

rules = cfg["review"]["path_instructions"]
if not rules:
    print("review.path_instructions is empty", file=sys.stderr); sys.exit(1)
seen = set()
for i, rule in enumerate(rules):
    path, text = rule.get("path"), (rule.get("instructions") or "").strip()
    if not path or not text:
        print("review.path_instructions[%d] is incomplete" % i, file=sys.stderr); sys.exit(1)
    if path in seen:
        print("review.path_instructions[%d] duplicates path %r" % (i, path), file=sys.stderr); sys.exit(1)
    seen.add(path)
    # no-mistakes matches these per changed path and silently drops a rule that
    # never matches, so a glob that has gone stale must fail here instead.
    if not any(matches(path, f) for f in tracked):
        print("review.path_instructions[%d] path %r matches no tracked file" % (i, path),
              file=sys.stderr); sys.exit(1)
PY
pass 'every review.path_instructions rule is complete, unique, and matches tracked files'

py <<'PY' || fail 'document.instructions is missing or empty'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
if not (cfg.get("document", {}).get("instructions") or "").strip():
    print("document.instructions is empty", file=sys.stderr); sys.exit(1)
PY
pass 'document.instructions is present'

# --- the installed no-mistakes parser as the oracle ---------------------------

if ! command -v no-mistakes >/dev/null 2>&1; then
  printf 'ok - # SKIP real-parser checks: no-mistakes is not installed\n'
  exit 0
fi

probe_repo() { # probe_repo <dir> <config-file>
  mkdir -p "$1"
  $GIT_BIN -C "$1" init -q -b main .
  cp "$2" "$1/.no-mistakes.yaml"
}

ACCEPT="$TMP_ROOT/accept"
probe_repo "$ACCEPT" "$CONFIG"
( cd "$ACCEPT" && no-mistakes ci-workflow ) >"$TMP_ROOT/accept.out" 2>&1 ||
  { cat "$TMP_ROOT/accept.out" >&2; fail 'the installed no-mistakes parser rejected .no-mistakes.yaml'; }
pass 'the installed no-mistakes parser accepts .no-mistakes.yaml'

GENERATED="$ACCEPT/.github/workflows/ci.yml"
[ -f "$GENERATED" ] || fail 'no-mistakes generated no workflow to read the commands back from'
python3 - "$CONFIG" "$GENERATED" <<'PY' || fail 'the generated workflow does not bind each step to its role entry point'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
workflow = yaml.safe_load(open(sys.argv[2]))
bodies = {}
for job in (workflow.get("jobs") or {}).values():
    for step in (job.get("steps") or []):
        if step.get("name") is not None:
            bodies.setdefault(step["name"], []).append((step.get("run") or "").strip())
# Each role is bound to the entry point that performs it, not merely to whatever
# the config happens to say: comparing the generated step only against
# cfg["commands"][key] round-trips, so swapping the two commands would satisfy
# both sides at once while the pipeline ran lint as its Test step.
for role, key, entrypoint in (("Test", "test", "bin/dotfiles-test"),
                              ("Lint", "lint", "bin/dotfiles-lint")):
    found = bodies.get(role, [])
    if len(found) != 1:
        print("generated workflow has %d %s step(s)" % (len(found), role), file=sys.stderr)
        sys.exit(1)
    if cfg["commands"][key] != entrypoint:
        print("commands.%s is %r, expected the %s entry point %r"
              % (key, cfg["commands"][key], role, entrypoint), file=sys.stderr)
        sys.exit(1)
    if found[0] != entrypoint:
        print("%s step runs %r, expected %r" % (role, found[0], entrypoint), file=sys.stderr)
        sys.exit(1)
PY
pass 'the generated workflow runs bin/dotfiles-test as Test and bin/dotfiles-lint as Lint'

# Negative case: prove the oracle really parses review.path_instructions rather
# than ignoring the key, so the acceptance above is meaningful.
REJECT="$TMP_ROOT/reject"
python3 - "$CONFIG" "$TMP_ROOT/broken.yaml" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
cfg["review"]["path_instructions"][0]["path"] = "[unclosed"
yaml.safe_dump(cfg, open(sys.argv[2], "w"))
PY
probe_repo "$REJECT" "$TMP_ROOT/broken.yaml"
if ( cd "$REJECT" && no-mistakes ci-workflow ) >"$TMP_ROOT/reject.out" 2>&1; then
  fail 'no-mistakes accepted an invalid review.path_instructions glob'
fi
grep -q 'review.path_instructions\[0\].path' "$TMP_ROOT/reject.out" ||
  { cat "$TMP_ROOT/reject.out" >&2; fail 'no-mistakes did not report the invalid glob it was given'; }
pass 'no-mistakes validates review.path_instructions, so the acceptance above is real'

printf 'no-mistakes-config tests passed\n'
