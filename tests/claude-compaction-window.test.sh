#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT
python3 - <<'PY'
import json
import os
from pathlib import Path
import subprocess
import tempfile

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'settings.json'
    env = dict(os.environ, CLAUDE_CONFIG_DIR=directory)
    def run():
        return subprocess.run(['bash', os.environ['ROOT'] + '/bin/claude-set-compaction-window'], env=env, capture_output=True)
    assert run().returncode == 0
    assert json.loads(path.read_text()) == {'env': {'CLAUDE_CODE_AUTO_COMPACT_WINDOW': '600000'}}
    assert path.stat().st_mode & 0o777 == 0o600
    for original in [
        {'model': 'fixture', 'permissions': {'deny': ['Read(secret)']}, 'env': {'OTHER': 'keep', 'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE': '50'}},
        {'env': {'CLAUDE_CODE_AUTO_COMPACT_WINDOW': '400000'}},
        {'env': {'CLAUDE_CODE_AUTO_COMPACT_WINDOW': ''}},
        {'autoCompactWindow': 300000, 'env': {'OTHER': 'keep'}},
    ]:
        path.write_text(json.dumps(original))
        path.chmod(0o640)
        assert run().returncode == 0
        expected = json.loads(json.dumps(original))
        if 'autoCompactWindow' not in original and 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' not in original.get('env', {}):
            expected.setdefault('env', {})['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] = '600000'
        assert json.loads(path.read_text()) == expected
        before = path.read_bytes(), path.stat().st_mtime_ns
        assert run().returncode == 0
        assert (path.read_bytes(), path.stat().st_mtime_ns) == before
        assert path.stat().st_mode & 0o777 == 0o640
    for invalid in ['{', '[]', '{"env":null}']:
        path.write_text(invalid)
        assert run().returncode != 0
        assert path.read_text() == invalid
print('Claude settings default, overrides, preservation, idempotence and malformed-input refusal passed')
PY
