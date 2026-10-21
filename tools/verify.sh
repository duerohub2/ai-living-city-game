#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot || true)}"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
GODOT_BIN="$(command -v "$GODOT_BIN" || true)"
VERIFY_DATA_DIR="$(mktemp -d)"

cleanup() {
  rm -rf -- "$VERIFY_DATA_DIR"
}
trap cleanup EXIT

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot executable not found: $GODOT_BIN" >&2
  exit 1
fi

run_godot() {
  local output
  if ! output="$(XDG_DATA_HOME="$VERIFY_DATA_DIR" "$GODOT_BIN" "$@" 2>&1)"; then
    printf '%s\n' "$output"
    return 1
  fi
  LAST_GODOT_OUTPUT="$output"
  printf '%s\n' "$output"
  if rg -q 'SCRIPT ERROR|ERROR:' <<<"$output"; then
    echo "Godot reported an error despite returning success." >&2
    return 1
  fi
}

run_godot_editor() {
  local output
  if ! output="$("$GODOT_BIN" "$@" 2>&1)"; then
    printf '%s\n' "$output"
    return 1
  fi
  printf '%s\n' "$output"
  if rg -q 'SCRIPT ERROR|ERROR:' <<<"$output"; then
    echo "Godot reported an editor error despite returning success." >&2
    return 1
  fi
}

node "$PROJECT_DIR/tools/audit_resources.mjs"

echo "[verify] Godot import"
run_godot_editor --headless --path "$PROJECT_DIR" --import

echo "[verify] deterministic source suite"
run_godot --headless --path "$PROJECT_DIR" res://test/test_suite.tscn --quit-after 1800
if ! rg -q '\[pong-tests\] PASS:' <<<"$LAST_GODOT_OUTPUT"; then
  echo "Test suite did not report success." >&2
  exit 1
fi

echo "[verify] BGM fallback and controls"
run_godot --headless --path "$PROJECT_DIR" --script res://test/browser_bgm_regression.gd
if ! rg -q '\[browser-bgm-regression\] PASS:' <<<"$LAST_GODOT_OUTPUT"; then
  echo "BGM regression did not report success." >&2
  exit 1
fi

echo "[verify] bounded main-scene boot"
run_godot --headless --path "$PROJECT_DIR" --fixed-fps 60 --quit-after 180

if [[ "${1:-}" == "--export" ]]; then
  echo "[verify] Web export"
  mkdir -p "$PROJECT_DIR/dist"
  # Export uses the installed editor templates. Only gameplay tests need an
  # isolated XDG data directory; redirecting export also hides Linux templates.
  run_godot_editor --headless --path "$PROJECT_DIR" --export-release Web "$PROJECT_DIR/dist/index.html"
  for artifact in index.html index.js index.wasm index.pck; do
    if [[ ! -s "$PROJECT_DIR/dist/$artifact" ]]; then
      echo "Missing or empty Web artifact: dist/$artifact" >&2
      exit 1
    fi
  done
  echo "[verify] isolated exported pack"
  mkdir -p "$VERIFY_DATA_DIR/pack"
  run_godot --headless --path "$VERIFY_DATA_DIR/pack" --main-pack "$PROJECT_DIR/dist/index.pck" --script "$PROJECT_DIR/tools/verify_exported_pack.gd" --quit-after 600
  if ! rg -q '\[exported-pack\] PASS:' <<<"$LAST_GODOT_OUTPUT"; then
    echo "Exported pack verification did not report success." >&2
    exit 1
  fi
fi

echo "[verify] PASS"
