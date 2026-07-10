#!/bin/sh
# download.sh — entry point for the cosmos.so /public-work texture cache.
#
# Usage:
#   ./download.sh                 # discover + download up to defaults
#   ./download.sh discover        # just enqueue candidates
#   ./download.sh download        # just consume the existing queue
#   ./download.sh both --target 15000
#
# This script is intentionally thin; the heavy lifting lives in cosmos_cache.py.
# It is fully resumable: state lives in state.json and the .index files.

set -eu
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$HERE/cosmos_cache.py" "$@"
