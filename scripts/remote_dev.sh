#!/usr/bin/env bash
# Give your local editor or terminal a session on the Colab runtime.
#   scripts/remote_dev.sh vscode   -> VS Code / Cursor Remote Tunnels
#   scripts/remote_dev.sh ssh      -> sshd exposed over a Cloudflare TCP tunnel
# Tailscale SSH is handled by scripts/tunnel.sh with TUNNEL=tailscale.
set -euo pipefail
. "$(dirname "$0")/common.sh"
mkdir -p "$RUN_DIR"
mode="${1:-vscode}"

case "$mode" in
  vscode)
    if [ ! -x "$RUN_DIR/code" ]; then
      log "downloading VS Code CLI"
      curl -sLk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' \
        -o "$RUN_DIR/vscode_cli.tar.gz"
      tar -xf "$RUN_DIR/vscode_cli.tar.gz" -C "$RUN_DIR"
    fi
    logfile="$RUN_DIR/vscode.log"
    : > "$logfile"
    nohup "$RUN_DIR/code" tunnel --accept-server-license-terms \
      --name "${VSCODE_TUNNEL_NAME:-colab-comfy}" > "$logfile" 2>&1 &
    echo $! > "$RUN_DIR/vscode.pid"
    log "authenticate with the code shown below, then in VS Code or Cursor run"
    log "  Remote-Tunnels: Connect to Tunnel  ->  ${VSCODE_TUNNEL_NAME:-colab-comfy}"
    sleep 5
    tail -f "$logfile"
    ;;

  ssh)
    pass="${SSH_PASSWORD:-}"
    [ -n "$pass" ] || die "set SSH_PASSWORD before starting the ssh tunnel"
    apt-get -qq install -y openssh-server >/dev/null 2>&1 || true
    mkdir -p /run/sshd
    echo "root:$pass" | chpasswd
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    service ssh restart >/dev/null 2>&1 || /usr/sbin/sshd

    if ! have cloudflared; then
      wget -q -O /tmp/cloudflared.deb \
        https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
      dpkg -i /tmp/cloudflared.deb >/dev/null
    fi
    logfile="$RUN_DIR/cloudflared-ssh.log"
    : > "$logfile"
    nohup cloudflared tunnel --no-autoupdate --url ssh://localhost:22 > "$logfile" 2>&1 &
    echo $! > "$RUN_DIR/cloudflared-ssh.pid"
    for _ in $(seq 1 60); do
      host="$(grep -oE '[a-z0-9-]+\.trycloudflare\.com' "$logfile" | head -1 || true)"
      [ -n "${host:-}" ] && break
      sleep 1
    done
    [ -n "${host:-}" ] || { tail -20 "$logfile"; die "no tunnel hostname"; }
    cat <<TXT

Add this to your local ~/.ssh/config (needs cloudflared installed locally):

  Host colab
    HostName $host
    User root
    ProxyCommand cloudflared access ssh --hostname %h

Then from your machine:  ssh colab

TXT
    ;;

  *) die "usage: remote_dev.sh [vscode|ssh]" ;;
esac
