#!/usr/bin/env bash
# Entrypoint bootstrap script for skim-ub24-1 Ubuntu build server VM.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${DIR}/bootstrap-skim-ub24-1.sh" "$@"
