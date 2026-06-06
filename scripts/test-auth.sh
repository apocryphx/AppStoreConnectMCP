#!/usr/bin/env bash
# Compile test-auth.m and run it — no Xcode, no install, no bridge restart.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN=/tmp/asc-test-auth

echo "[test-auth] compiling..."
clang -framework Foundation -framework Security \
      -fobjc-arc \
      scripts/test-auth.m -o "$BIN"

echo "[test-auth] running..."
"$BIN"
