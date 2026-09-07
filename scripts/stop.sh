#!/usr/bin/env bash
# Stop everything launch.sh started and flush outputs to Drive one last time.
set -uo pipefail
. "$(dirname "$0")/common.sh"

for name in comfyui cloudflared tailscaled sync; do
  pidfile="$RUN_DIR/$name.pid"
  [ -f "$pidfile" ] || continue
  pid="$(cat "$pidfile")"
  kill "$pid" 2>/dev/null && log "stopped $name ($pid)"
  rm -f "$pidfile"
done

if [ -d "$DRIVE_ROOT" ]; then
  log "final output sync"
  rsync -a --no-perms --no-owner --no-group "$COMFY_ROOT/output/" "$DRIVE_ROOT/outputs/" 2>/dev/null
fi
log "done"
