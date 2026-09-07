#!/usr/bin/env bash
# Expose $COMFY_PORT to your local machine. Prints the URL to use.
set -euo pipefail
. "$(dirname "$0")/common.sh"
mkdir -p "$RUN_DIR"

case "$TUNNEL" in
  cloudflared)
    if ! have cloudflared; then
      log "installing cloudflared"
      wget -q -O /tmp/cloudflared.deb \
        https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
      dpkg -i /tmp/cloudflared.deb >/dev/null
    fi
    logfile="$RUN_DIR/cloudflared.log"
    : > "$logfile"
    nohup cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:$COMFY_PORT" \
      > "$logfile" 2>&1 &
    echo $! > "$RUN_DIR/cloudflared.pid"
    log "waiting for tunnel URL"
    for _ in $(seq 1 60); do
      url="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$logfile" | head -1 || true)"
      [ -n "${url:-}" ] && break
      sleep 1
    done
    [ -n "${url:-}" ] || { tail -20 "$logfile"; die "cloudflared did not report a URL"; }
    echo "$url" > "$RUN_DIR/url.txt"
    printf '\n\033[1;32mComfyUI: %s\033[0m\n\n' "$url"
    log "this URL is public but unguessable; anyone holding it can run workflows"
    ;;

  tailscale)
    [ -n "${TS_AUTHKEY:-}" ] || die "set TS_AUTHKEY (Tailscale auth key) for TUNNEL=tailscale"
    if ! have tailscaled; then
      log "installing tailscale"
      curl -fsSL https://tailscale.com/install.sh | sh >/dev/null
    fi
    nohup tailscaled --tun=userspace-networking --socks5-server=localhost:1055 \
      --state="$RUN_DIR/tailscaled.state" > "$RUN_DIR/tailscaled.log" 2>&1 &
    echo $! > "$RUN_DIR/tailscaled.pid"
    sleep 3
    tailscale up --authkey="$TS_AUTHKEY" --hostname="${TS_HOSTNAME:-colab-comfy}" --ssh
    ip="$(tailscale ip -4 | head -1)"
    echo "http://$ip:$COMFY_PORT" > "$RUN_DIR/url.txt"
    printf '\n\033[1;32mComfyUI: http://%s:%s   (tailnet only)\033[0m\n' "$ip" "$COMFY_PORT"
    printf '\033[1;32mSSH:     ssh root@%s\033[0m\n\n' "${TS_HOSTNAME:-colab-comfy}"
    ;;

  none)
    log "no tunnel; ComfyUI reachable only inside the runtime"
    ;;

  *) die "unknown TUNNEL=$TUNNEL (use cloudflared, tailscale, or none)" ;;
esac
