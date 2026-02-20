#!/usr/bin/env bash
set -euo pipefail

if [[ -f ".gitmodules" ]]; then
  echo "ERROR: git submodules are forbidden in this ecosystem."
  echo "Found: .gitmodules"
  echo "Fix: remove submodules; prefer versioned deps or repo templates."
  exit 2
fi

