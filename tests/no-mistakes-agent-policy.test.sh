#!/usr/bin/env bash
# Behavioral tests for bin/no-mistakes-set-agent-policy.
#
# Every case runs the real helper against a temporary file selected with
# NO_MISTAKES_CONFIG_FILE; the real ~/.no-mistakes/config.yaml is never read.
# PyYAML is the parse oracle for values; comment and key preservation is
# asserted on the raw text. Idempotence means byte-identical content on the
# same inode, which is what the live file's activation depends on.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

command -v python3 >/dev/null 2>&1 || { echo 'not ok - missing test dependency: python3' >&2; exit 1; }
python3 -c 'import yaml' >/dev/null 2>&1 || { echo 'not ok - missing test dependency: python3 with PyYAML' >&2; exit 1; }

python3 - <<'PY'
import os
from pathlib import Path
import subprocess
import tempfile

import yaml

HELPER = os.environ['ROOT'] + '/bin/no-mistakes-set-agent-policy'
DESIRED_ARGS = ['--model', 'claude-opus-5-5', '--effort', 'xhigh']
BASELINE_ARGS = ['--model', 'claude-opus-5-5', '--effort', 'low']
CODEX_ARGS = ['-m', 'gpt-6-sol', '-c', 'model_reasoning_effort="high"',
              '-c', 'model_auto_compact_token_limit=512000']
# Every case runs on a pinned clock: the temporary policy window is real time.
BEFORE_EXPIRY = '2026-10-03T23:59:59Z'
AT_EXPIRY = '2026-10-04T00:00:00Z'


def run(path, now=BEFORE_EXPIRY, *args):
    env = dict(os.environ, NO_MISTAKES_CONFIG_FILE=str(path),
               NO_MISTAKES_POLICY_NOW=now)
    return subprocess.run(['bash', HELPER, *args], env=env,
                          capture_output=True, text=True)


def state(path):
    stat = path.stat()
    return path.read_bytes(), stat.st_ino, stat.st_mtime_ns


def assert_policy(path):
    cfg = yaml.safe_load(path.read_text())
    assert cfg['agent'] == 'claude', cfg
    assert cfg['review_agents'] == {'reviewer': {'agent': 'claude'},
                                    'fixer': {'agent': 'claude'}}, cfg
    assert cfg['agent_args_override']['claude'] == DESIRED_ARGS, cfg
    return cfg


LIVE_SHAPED = '''# no-mistakes global configuration

# Agent to use for code generation. This may also be an ordered fallback list,
# for example: agent: [codex, claude]
agent: claude

# Maximum time the CI monitor babysits an open PR with no base-branch movement
ci_timeout: "168h"

# Captain's fleet-wide selection, 2026-09-14: Claude Code, Opus, medium effort
# for all agent stages, including both independent review-role sessions.
review_agents:
  reviewer:
    agent: claude
  fixer:
    agent: claude

# Log level for daemon output
log_level: info

# Extra native agent CLI flags (optional, global only)
agent_args_override:
  codex:
    - -m
    - gpt-6-astra
    - -c
    - model_reasoning_effort="medium"
  # Pinned 2026-08-18 (captain request): Claude Opus 5 while the codex window is out.
  # Re-pinned 2026-10-01 to claude-opus-5-5 at xhigh effort.
  claude:
    - --model
    - claude-opus-5-5
    - --effort
    - xhigh

# Maximum follow-up auto-fix attempts per step (0 = disabled after the initial pass)
auto_fix:
  rebase: 3
  review: 0
  ci: 0

# User-intent extraction.
intent:
  enabled: true
  threshold: 0.2
'''

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'config.yaml'

    # Absent file: a fresh machine gets a minimal file with just the policy.
    assert run(path).returncode == 0
    assert_policy(path)
    assert path.stat().st_mode & 0o777 == 0o644
    before = state(path)
    assert run(path).returncode == 0
    assert state(path) == before

    # Empty file is treated the same as absent.
    path.write_text('')
    assert run(path).returncode == 0
    assert_policy(path)

    # Live-shaped file already matching: no rewrite, same bytes, same inode.
    path.write_text(LIVE_SHAPED)
    path.chmod(0o644)
    before = state(path)
    assert run(path).returncode == 0
    assert state(path) == before

    # Quoted-but-equal values are already correct: no rewrite.
    quoted = LIVE_SHAPED.replace('agent: claude\n', 'agent: "claude"\n', 1) \
                        .replace('- xhigh', "- 'xhigh'")
    path.write_text(quoted)
    before = state(path)
    assert run(path).returncode == 0
    assert state(path) == before

    # Drifted values merge surgically: comments and undeclared keys survive.
    drifted = LIVE_SHAPED \
        .replace('agent: claude\n', 'agent: [codex, claude]  # fallback list\n', 1) \
        .replace('  reviewer:\n    agent: claude', '  reviewer:\n    agent: codex') \
        .replace('    - xhigh\n', '    - medium\n    - --verbose\n')
    path.write_text(drifted)
    path.chmod(0o640)
    assert run(path).returncode == 0
    cfg = assert_policy(path)
    assert cfg['agent_args_override']['codex'] == [
        '-m', 'gpt-6-astra', '-c', 'model_reasoning_effort="medium"']
    assert cfg['auto_fix'] == {'rebase': 3, 'review': 0, 'ci': 0}
    assert cfg['intent'] == {'enabled': True, 'threshold': 0.2}
    assert cfg['ci_timeout'] == '168h' and cfg['log_level'] == 'info'
    text = path.read_text()
    for comment in ('# fallback list',
                    '# Captain\'s fleet-wide selection, 2026-09-14',
                    '# Pinned 2026-08-18 (captain request)',
                    '# Maximum follow-up auto-fix attempts per step'):
        assert comment in text, comment
    assert path.stat().st_mode & 0o777 == 0o640
    before = state(path)
    assert run(path).returncode == 0
    assert state(path) == before

    # The pre-migration baseline (Codex policy, Claude override at low effort)
    # converges to the temporary Claude xhigh policy. The Codex override, not
    # owned, and every other key and comment stay byte for byte.
    codex_args_block = ''.join(f'    - {arg}\n' for arg in CODEX_ARGS)
    live_temporary = LIVE_SHAPED \
        .replace('    - -m\n    - gpt-6-astra\n    - -c\n'
                 '    - model_reasoning_effort="medium"\n', codex_args_block)
    assert codex_args_block in live_temporary
    baseline = live_temporary \
        .replace('agent: claude\n', 'agent: codex\n', 1) \
        .replace('    agent: claude\n', '    agent: codex\n') \
        .replace('    - xhigh\n', '    - low\n')
    path.write_text(baseline)
    path.chmod(0o644)
    assert run(path).returncode == 0
    cfg = assert_policy(path)
    assert cfg['agent_args_override']['codex'] == CODEX_ARGS
    assert path.read_text() == live_temporary
    before = state(path)
    assert run(path).returncode == 0
    assert state(path) == before

    # Expiry: before the instant nothing happens, even when asked.
    result = run(path, BEFORE_EXPIRY, '--expire-temporary')
    assert result.returncode == 0 and state(path) == before

    # At and after expiry the temporary policy is restored to the baseline
    # exactly, whether by the timer flag or a plain activation, then stays put.
    for now, args in ((AT_EXPIRY, ('--expire-temporary',)), ('2026-12-01T00:00:00Z', ()),
                      ('2026-10-04T00:00:00+00:00', ('--expire-temporary',))):
        path.write_text(live_temporary)
        path.chmod(0o644)
        assert run(path, now, *args).returncode == 0
        assert path.read_text() == baseline, now
        settled = state(path)
        assert run(path, now, *args).returncode == 0
        assert state(path) == settled

    # A later choice is never overwritten after expiry: a different effort, a
    # different agent, a drifted role, or the baseline hand-edited. Neither the
    # timer flag nor an activation touches it, and xhigh is never reapplied.
    later_choices = [
        live_temporary.replace('    - xhigh\n', '    - high\n'),
        live_temporary.replace('agent: claude\n', 'agent: codex\n', 1),
        live_temporary.replace('  fixer:\n    agent: claude', '  fixer:\n    agent: codex'),
        baseline.replace('    - low\n', '    - medium\n'),
        baseline.replace('agent: codex\n', 'agent: claude\n', 1),
    ]
    for chosen in later_choices:
        for args in ((), ('--expire-temporary',)):
            path.write_text(chosen)
            before = state(path)
            assert run(path, AT_EXPIRY, *args).returncode == 0
            assert state(path) == before, (args, chosen)
            assert 'xhigh' not in path.read_text() or 'xhigh' in chosen

    # Expiry on a fresh machine writes the baseline, never xhigh.
    path.unlink()
    assert run(path, AT_EXPIRY).returncode == 0
    cfg = yaml.safe_load(path.read_text())
    assert cfg['agent'] == 'codex'
    assert cfg['review_agents'] == {'reviewer': {'agent': 'codex'},
                                    'fixer': {'agent': 'codex'}}
    assert cfg['agent_args_override'] == {'codex': CODEX_ARGS, 'claude': BASELINE_ARGS}
    path.write_text('')

    # A bad argument or clock is refused with no write.
    for bad_args, now in ((('--nope',), BEFORE_EXPIRY), ((), 'tomorrow')):
        path.write_text(live_temporary)
        before = state(path)
        assert run(path, now, *bad_args).returncode != 0
        assert state(path) == before

    # Missing blocks are appended; existing keys keep their place.
    path.write_text('# only a comment\nlog_level: info\n')
    assert run(path).returncode == 0
    cfg = assert_policy(path)
    assert cfg['log_level'] == 'info'
    text = path.read_text()
    assert text.startswith('# only a comment\n')
    assert 'log_level: info\n' in text

    # A missing role is inserted into the existing review_agents block.
    path.write_text('review_agents:\n  reviewer:\n    agent: claude\n')
    assert run(path).returncode == 0
    assert_policy(path)

    # A missing claude entry is inserted into the existing overrides block.
    path.write_text('agent_args_override:\n  codex:\n    - -m\n    - gpt-6-astra\n')
    assert run(path).returncode == 0
    cfg = assert_policy(path)
    assert cfg['agent_args_override']['codex'] == ['-m', 'gpt-6-astra']

    # Unhandled shapes refuse with no write, byte for byte.
    for invalid in [
            'agent:\n  - claude\n',              # block value for a scalar key
            '- claude\n',                        # not a mapping document
            'agent: codex\nagent: claude\n',     # duplicate owned key
            'agent: [codex,\n  claude]\n',       # multi-line flow value
            'review_agents: {reviewer: {agent: codex}}\n',  # flow mapping
            '\tagent: claude\n',                 # tab indentation
    ]:
        path.write_text(invalid)
        before = state(path)
        result = run(path)
        assert result.returncode != 0, (invalid, result.stdout, result.stderr)
        assert state(path) == before, invalid

print('no-mistakes agent policy: fresh, idempotent, merge, preservation, insertion, refusal and expiry cases passed')
PY
