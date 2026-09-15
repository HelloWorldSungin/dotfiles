#!/usr/bin/env bash
# Exercise the merge, then ask installed Codex to resolve defaults and overrides.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/codex-model-defaults.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
export CODEX_HOME="$TMP_ROOT"
unset CODEX_CONFIG_FILE
cat > "$TMP_ROOT/config.toml" <<'TOML'
# Existing user preferences
model = "gpt-6-astra"
model_reasoning_effort = "medium"
model_context_window = 272000
[tui]
theme = "dark"
[profiles.dispatch]
model = "gpt-5.6-sol"
model_reasoning_effort = "medium"
TOML
bash "$ROOT/bin/codex-set-model-defaults"
touch -d '2000-01-01' "$TMP_ROOT/config.toml"
bash "$ROOT/bin/codex-set-model-defaults"
[ "$(stat -c %Y "$TMP_ROOT/config.toml")" = 946684800 ]
python3 - "$TMP_ROOT" "$ROOT/bin/codex-set-model-defaults" <<'PY'
import json, os, pathlib, selectors, signal, subprocess, sys, time, tomllib
root = pathlib.Path(sys.argv[1])
config = tomllib.loads((root / 'config.toml').read_text())
assert config == {'model': 'gpt-6-astra', 'model_reasoning_effort': 'low',
                  'model_context_window': 272000, 'tui': {'theme': 'dark'},
                  'profiles': {'dispatch': {'model': 'gpt-5.6-sol', 'model_reasoning_effort': 'medium'}}}
for args, expected in [([], ('gpt-6-astra', 'low')),
                       (['-c', 'model="gpt-5.6-sol"', '-c', 'model_reasoning_effort="medium"'], ('gpt-5.6-sol', 'medium'))]:
    p = subprocess.Popen(['codex'] + args + ['app-server', '--stdio'], cwd=root,
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True)
    selector = selectors.DefaultSelector()
    selector.register(p.stdout, selectors.EVENT_READ)
    try:
        for request in [{'id': 1, 'method': 'initialize', 'params': {'clientInfo': {'name': 'defaults-test', 'version': '1'}}},
                        {'id': 2, 'method': 'config/read', 'params': {'includeLayers': False, 'cwd': str(root)}}]:
            p.stdin.write(json.dumps(request) + '\n'); p.stdin.flush()
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if not selector.select(1):
                    continue
                line = p.stdout.readline()
                assert line, 'Codex exited before replying: ' + p.stderr.read()
                response = json.loads(line)
                if response.get('id') == request['id']:
                    assert 'error' not in response, response
                    break
            else:
                raise AssertionError('Codex config/read timed out')
        effective = response['result']['config']
        assert (effective['model'], effective['model_reasoning_effort']) == expected, effective
        print('ok - Codex effective defaults/override', args, expected)
    finally:
        p.terminate(); p.wait(timeout=10); selector.close()
# Preserve TOML syntax that a line-oriented substitution can corrupt.
edge = root / 'edge.toml'
edge.write_text("\"model\" = '''gpt-5.6-sol'''\n'model_reasoning_effort' = \"medium\"\n"
                "developer_instructions = '''\nmodel = \"literal instruction\"\n[not_a_table]\n'''\n"
                "[profiles.explicit]\nmodel = \"gpt-5.6-sol\"\nmodel_reasoning_effort = \"medium\"\n")
edge.chmod(0o640)
before = tomllib.loads(edge.read_text())
env = dict(os.environ, CODEX_CONFIG_FILE=str(edge))
subprocess.run(['bash', sys.argv[2]], env=env, check=True)
assert tomllib.loads(edge.read_text()) == before | {'model': 'gpt-6-astra', 'model_reasoning_effort': 'low'}
assert edge.stat().st_mode & 0o777 == 0o640
edge.write_text('model = [invalid TOML')
result = subprocess.run(['bash', sys.argv[2]], env=env, capture_output=True)
assert result.returncode != 0 and edge.read_text() == 'model = [invalid TOML'
print('ok - quoted keys, multiline content, permissions, and malformed TOML safety')

# app-server rejects --profile. The supported runtime CLI prints its effective
# model and reasoning before inference. Point its provider at a closed local
# port, so this fixture cannot send a request to a real model service.
# Legacy table preservation was asserted above. Current CLI refuses mixed formats.
path = root / 'config.toml'
path.write_text(path.read_text().split('[profiles.dispatch]')[0])
(root / 'dispatch.config.toml').write_text('model = "gpt-5.6-sol"\nmodel_reasoning_effort = "medium"\n')
args = ['codex', '-p', 'dispatch', '-c', 'model_provider="fixture"',
        '-c', 'model_providers.fixture={name="fixture",base_url="http://127.0.0.1:1/v1",wire_api="responses",supports_websockets=false}',
        'exec', '--skip-git-repo-check', '--ephemeral', '--color', 'never', 'fixture only']
env = {k: v for k, v in os.environ.items() if not any(x in k for x in ['API_KEY', 'AUTH_TOKEN', 'ACCESS_TOKEN'])}
p = subprocess.Popen(args, cwd=root, env=env, stdin=subprocess.DEVNULL,
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
try:
    _, stderr = p.communicate(timeout=10)
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGKILL)
    _, stderr = p.communicate(timeout=10)
assert 'model: gpt-5.6-sol' in stderr and 'reasoning effort: medium' in stderr, stderr
assert 'api.openai.com' not in stderr, stderr
print('ok - supported Codex runtime CLI preserves explicit profile Sol/medium')

PY
CODEX_CONFIG_FILE="$TMP_ROOT/fresh/config.toml" bash "$ROOT/bin/codex-set-model-defaults"
[ "$(stat -c %a "$TMP_ROOT/fresh/config.toml")" = 600 ]
printf 'ok - merge preserves unrelated settings and profiles; idempotent; fresh config private\n'
