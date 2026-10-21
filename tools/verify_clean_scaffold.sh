#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-2d-scaffold.XXXXXX")"

cleanup() {
  if [[ -n "${SCAFFOLD_DIR}" && -d "${SCAFFOLD_DIR}" && "${SCAFFOLD_DIR}" == *generic-2d-scaffold.* ]]; then
    rm -rf "${SCAFFOLD_DIR}"
  fi
}
trap cleanup EXIT

rsync -a \
  --exclude '.git/' \
  --exclude '.godot/' \
  --exclude 'dist/' \
  --exclude 'test-output/' \
  "${ROOT}/" "${SCAFFOLD_DIR}/"

echo "[clean-scaffold] verifying isolated copy"
GODOT_BIN="${GODOT_BIN:-$(command -v godot || true)}"
export GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
echo "[clean-scaffold] bootstrapping a fresh import cache"
# A project-level custom font is requested while Godot is still discovering
# importers on the very first scan. Build the disposable cache once, then run
# the strict verifier against the reconstructed state.
if ! bootstrap_output="$("${GODOT_BIN}" --headless --path "${SCAFFOLD_DIR}" --import 2>&1)"; then
  printf '%s\n' "${bootstrap_output}"
  exit 1
fi
"${SCAFFOLD_DIR}/tools/verify.sh"
echo "[clean-scaffold] PASS"
