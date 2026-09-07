#!/usr/bin/env bash
# Install ComfyUI + custom nodes on a fresh Colab runtime and wire the
# persistent directories to Google Drive. Safe to re-run.
set -euo pipefail
. "$(dirname "$0")/common.sh"

log "GPU:"; nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || log "no GPU visible"

log "installing system packages"
apt-get -qq update >/dev/null 2>&1 || true
apt-get -qq install -y aria2 ffmpeg rsync >/dev/null 2>&1 || true

if [ ! -d "$COMFY_ROOT/.git" ]; then
  log "cloning ComfyUI into $COMFY_ROOT"
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI "$COMFY_ROOT"
else
  log "updating ComfyUI"
  git -C "$COMFY_ROOT" pull --ff-only || log "pull skipped (local changes)"
fi

torch_before="$(python3 -c 'import torch;print(torch.__version__)' 2>/dev/null || echo none)"

log "installing ComfyUI requirements"
pip install -q -r "$COMFY_ROOT/requirements.txt"
pip install -q "huggingface_hub[cli]" hf_transfer

torch_after="$(python3 -c 'import torch;print(torch.__version__)' 2>/dev/null || echo none)"
[ "$torch_before" = "$torch_after" ] || log "WARNING: torch changed $torch_before -> $torch_after; restart the runtime if CUDA breaks"

# --- custom nodes ---------------------------------------------------------
mkdir -p "$COMFY_ROOT/custom_nodes"
while read -r url _rest; do
  case "$url" in ''|'#'*) continue ;; esac
  name="$(basename "$url" .git)"
  dir="$COMFY_ROOT/custom_nodes/$name"
  if [ -d "$dir/.git" ]; then
    log "updating custom node $name"
    git -C "$dir" pull --ff-only || true
  else
    log "installing custom node $name"
    git clone --depth 1 "$url" "$dir"
  fi
  if [ -f "$dir/requirements.txt" ]; then pip install -q -r "$dir/requirements.txt" || true; fi
done < "$REPO_ROOT/config/custom_nodes.txt"

# --- persistence ----------------------------------------------------------
if [ -d "$(dirname "$DRIVE_ROOT")" ]; then
  mkdir -p "$DRIVE_ROOT"/{outputs,input,user,models_small,logs}
  if [ -n "${MODEL_CACHE:-}" ]; then mkdir -p "$MODEL_CACHE"; fi
  # Small and latency-tolerant: live on Drive via symlink.
  link_to_drive user   user      # settings + saved workflows
  link_to_drive input  input     # images/video you feed into workflows
  # Outputs stay on local disk and are rsynced to Drive (see sync_outputs.sh):
  # writing multi-hundred-MB video straight to the Drive FUSE mount stalls.
  mkdir -p "$COMFY_ROOT/output"
  # LoRAs and other small weights are cheap to keep on Drive.
  mkdir -p "$COMFY_ROOT/models/loras"
  link_to_drive models/loras models_small/loras
  # Seed the repo's UI-format workflows into the Drive workflow folder.
  # (workflows/api/ holds API-format graphs for scripts/smoke_test.py, not the UI.)
  mkdir -p "$DRIVE_ROOT/user/default/workflows"
  cp -n "$REPO_ROOT"/workflows/ui/*.json "$DRIVE_ROOT/user/default/workflows/" 2>/dev/null || true
  log "Drive persistence active at $DRIVE_ROOT"
else
  log "WARNING: $DRIVE_ROOT not reachable; running without Drive persistence"
fi

mkdir -p "$RUN_DIR"
log "bootstrap complete"
