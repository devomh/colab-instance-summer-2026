#!/usr/bin/env bash
# Start ComfyUI, the Drive sync loop, and the tunnel. Keeps running in the
# foreground and tails the ComfyUI log.
set -euo pipefail
. "$(dirname "$0")/common.sh"
mkdir -p "$RUN_DIR" "$COMFY_ROOT/output"

listen=127.0.0.1
[ "$TUNNEL" = tailscale ] && listen=0.0.0.0

if [ "$SYNC_INTERVAL" -gt 0 ]; then
  nohup bash "$REPO_ROOT/scripts/sync_outputs.sh" > "$RUN_DIR/sync.log" 2>&1 &
  sync_pid=$!
  echo "$sync_pid" > "$RUN_DIR/sync.pid"
  # A background failure here would otherwise be invisible, and outputs would
  # never reach Drive.
  sleep 2
  if kill -0 "$sync_pid" 2>/dev/null; then
    log "output sync loop running (pid $sync_pid)"
  else
    log "WARNING: output sync loop died, outputs will NOT reach Drive"
    sed 's/^/  /' "$RUN_DIR/sync.log"
  fi
fi

comfylog="$RUN_DIR/comfyui.log"
: > "$comfylog"
log "starting ComfyUI on $listen:$COMFY_PORT"
# shellcheck disable=SC2086
nohup python3 "$COMFY_ROOT/main.py" --listen "$listen" --port "$COMFY_PORT" \
  $COMFY_EXTRA_ARGS > "$comfylog" 2>&1 &
echo $! > "$RUN_DIR/comfyui.pid"

wait_for_port "$COMFY_PORT" 900 || { tail -40 "$comfylog"; die "ComfyUI failed to start"; }
log "ComfyUI is up"

bash "$REPO_ROOT/scripts/tunnel.sh"

log "tailing $comfylog (interrupt the cell to stop tailing; servers keep running)"
tail -f "$comfylog"
