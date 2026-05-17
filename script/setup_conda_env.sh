#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONDA_EXE="${CONDA_EXE:-conda}"

cd "$ROOT_DIR/worker"
"$CONDA_EXE" env update -f environment.yml --prune
