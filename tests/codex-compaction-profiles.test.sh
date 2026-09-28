#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import tomllib

root = Path(sys.argv[1])
home_module = (root / 'home/common.nix').read_text()
with tempfile.TemporaryDirectory(prefix='.codex-profiles-', dir=root) as scratch:
    codex_home = Path(scratch)
    (codex_home / 'config.toml').write_text(
        'model_context_window = 872000\n'
        'model_auto_compact_token_limit = 500000\n'
        'model_auto_compact_token_limit_scope = "total"\n')
    env = dict(os.environ, CODEX_HOME=str(codex_home))
    for model in ('gpt-6-sol', 'gpt-6-astra'):
        profile = f'{model}-512k'
        relative = f'config/codex/{profile}.config.toml'
        assert f'link "{relative}"' in home_module
        source = root / relative
        contents = tomllib.loads(source.read_text())
        assert contents == {
            'model': model,
            'model_context_window': 872000,
            'model_auto_compact_token_limit': 512000,
            'model_auto_compact_token_limit_scope': 'total',
        }, contents
        shutil.copyfile(source, codex_home / f'{profile}.config.toml')
        args = ['codex', '-p', profile, '--strict-config',
                '-c', 'model_provider="fixture"',
                '-c', 'model_providers.fixture={name="fixture",base_url="http://127.0.0.1:1/v1",wire_api="responses",supports_websockets=false}',
                'exec', '--skip-git-repo-check', '--ephemeral', '--color', 'never', 'fixture only']
        process = subprocess.Popen(args, cwd=root, env=env, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            _, stderr = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            _, stderr = process.communicate(timeout=10)
        assert f'model: {model}' in stderr, stderr
        assert 'unknown configuration field' not in stderr, stderr
        assert 'api.openai.com' not in stderr, stderr
        print(f'ok - {profile} selects {model} with accepted 512000 policy')
print('ok - the global 500000 policy is untouched')
PY
