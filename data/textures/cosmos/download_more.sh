#!/bin/sh
# download_more.sh — resume / extend an existing run.
# Picks up from state.json. Safe to invoke any time; bumps the target.
set -eu
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
TARGET=${1:-$(( $(wc -l < "$HERE/manifest.tsv" 2>/dev/null || echo 1) + 2000 - 1 ))}
echo "[download_more] resuming with --target $TARGET"
exec python3 "$HERE/cosmos_cache.py" both --target "$TARGET"
