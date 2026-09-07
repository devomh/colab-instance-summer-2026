#!/usr/bin/env bash
# Mirror ComfyUI's local output dir to Drive on a loop. ComfyUI writes to fast
# local disk; this makes the results survive the runtime.
set -uo pipefail
. "$(dirname "$0")/common.sh"

src="$COMFY_ROOT/output/"
dst="$DRIVE_ROOT/outputs/"
[ -d "$(dirname "$DRIVE_ROOT")" ] || { log "no Drive mount; sync loop not started"; exit 0; }
mkdir -p "$src" "$dst"

log "syncing $src -> $dst every ${SYNC_INTERVAL}s"
while true; do
  rsync -a --no-perms --no-owner --no-group --exclude '*.tmp' "$src" "$dst" 2>/dev/null
  sleep "$SYNC_INTERVAL"
done
