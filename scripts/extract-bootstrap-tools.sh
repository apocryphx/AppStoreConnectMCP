#!/usr/bin/env bash
#
# extract-bootstrap-tools.sh
#
# Captures the Astro server's tools/list (via the built bridge binary) and
# writes it to Resources/tools-bootstrap.json — the cold-start fallback that
# SchemaCache serves when Astro isn't running and no on-disk cache yet exists
# (first launch while Astro is down).
#
# Re-run this whenever Astro's tool surface changes enough that a stale
# cold-start fallback would be misleading. At runtime, a successful tools/list
# overwrites the on-disk last-known-good, so this matters only for the very
# first launch.
#
# Requires: python3, xcodebuild. Astro.app must be running.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

DERIVED="/tmp/astro-bootstrap-derived"
echo "[bootstrap] building bridge into $DERIVED" >&2
xcodebuild -project "Astro-Bridge.xcodeproj" \
           -scheme "Astro-Bridge" \
           -configuration Debug \
           -derivedDataPath "$DERIVED" \
           build >/dev/null

BIN="$DERIVED/Build/Products/Debug/Astro_Bridge.app/Contents/MacOS/Astro_Bridge"
[[ -x "$BIN" ]] || { echo "[bootstrap] binary not found at $BIN" >&2; exit 1; }

OUT="$ROOT/Astro-Bridge/Resources/tools-bootstrap.json"
mkdir -p "$(dirname "$OUT")"

echo "[bootstrap] capturing tools/list response" >&2
RESPONSE=$({
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
    sleep 2
} | "$BIN" 2>/dev/null)

# Extract the tools/list response (id=2) and pretty-print the tools array.
echo "$RESPONSE" | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        msg = json.loads(line)
    except Exception:
        continue
    if msg.get('id') == 2:
        tools = msg['result']['tools']
        print(json.dumps(tools, indent=2, ensure_ascii=False))
        sys.exit(0)
sys.exit(1)
" > "$OUT"

COUNT=$(python3 -c "import json; print(len(json.load(open('$OUT'))))")
echo "[bootstrap] wrote $OUT ($COUNT tools)" >&2
