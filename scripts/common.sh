# Sourced by the other scripts. Not executable on its own.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ -f "$REPO_ROOT/config/comfy.env" ] && . "$REPO_ROOT/config/comfy.env"

: "${COMFY_ROOT:=/content/ComfyUI}"
: "${DRIVE_ROOT:=/content/drive/MyDrive/colab-comfy}"
: "${COMFY_PORT:=8188}"
: "${TUNNEL:=tailscale}"
: "${TS_HOSTNAME:=colab-comfy}"
: "${MODEL_CACHE:=$DRIVE_ROOT/models_cache}"
: "${SYNC_INTERVAL:=30}"
: "${COMFY_EXTRA_ARGS:=}"
: "${RUN_DIR:=/content/.comfy-run}"

export REPO_ROOT COMFY_ROOT DRIVE_ROOT MODEL_CACHE COMFY_PORT TUNNEL TS_HOSTNAME SYNC_INTERVAL COMFY_EXTRA_ARGS RUN_DIR

log() { printf '\033[1;36m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# link_to_drive <comfy-subdir> <drive-subdir>
# Replaces $COMFY_ROOT/<comfy-subdir> with a symlink into Drive, preserving
# anything that was already there.
link_to_drive() {
  local sub="$1" dst="$DRIVE_ROOT/$2" src="$COMFY_ROOT/$1"
  mkdir -p "$dst"
  if [ -L "$src" ]; then
    [ "$(readlink -f "$src")" = "$(readlink -f "$dst")" ] || { rm "$src"; ln -s "$dst" "$src"; }
  elif [ -d "$src" ]; then
    cp -rn "$src/." "$dst/" 2>/dev/null || true
    rm -rf "$src"
    ln -s "$dst" "$src"
  else
    mkdir -p "$(dirname "$src")"
    ln -s "$dst" "$src"
  fi
  log "linked $sub -> $dst"
}

wait_for_port() {
  local port="$1" timeout="${2:-600}" i=0
  while [ "$i" -lt "$timeout" ]; do
    if python3 - "$port" <<'PY' 2>/dev/null
import socket, sys
s = socket.socket()
s.settimeout(1)
sys.exit(0 if s.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0 else 1)
PY
    then return 0; fi
    sleep 1; i=$((i+1))
  done
  return 1
}
