# Controlling a Colab runtime from your local machine

Colab runs inside Google's network with no public IP, so every option below is
some form of outbound tunnel started from inside the runtime. You cannot keep
ComfyUI local and borrow only the GPU: diffusion moves gigabytes of tensors per
step, and no home link makes that viable. The engine runs on Colab, your
machine is the client.

Google disallows remote shells on free runtimes and permits them while you hold
a positive compute-unit balance. Google AI Pro includes Colab Pro, so this
project is within terms.

## The four channels

| Channel | Account needed | Gives you | Exposure |
|---|---|---|---|
| Tailscale | Free Tailscale login | Web UI and SSH | Your tailnet only |
| Cloudflare quick tunnel | None | Web UI | Public random URL |
| VS Code Remote Tunnels | GitHub | Editor, filesystem, terminal | Your GitHub account |
| sshd over Cloudflare | None | SSH with a password | Public random hostname |

This project defaults to Tailscale plus the VS Code tunnel.

### Tailscale

`scripts/tunnel.sh` installs Tailscale, brings it up in userspace networking
mode, which is what works inside a container without a TUN device, and enables
Tailscale SSH. ComfyUI then binds `0.0.0.0` because only tailnet peers can
reach it. You get a stable hostname across sessions, so bookmarks keep working,
and `ssh root@colab-comfy` is available to any CLI agent on your machine.

Needs `TS_AUTHKEY` in the Colab secrets panel. Generate a reusable, ephemeral
auth key in the Tailscale admin console so dead Colab nodes clean themselves up.

### Cloudflare quick tunnel

Zero setup, prints a `trycloudflare.com` URL. The URL is unguessable but
public, and ComfyUI has no authentication, so anyone holding the link can run
workflows on your GPU and read your outputs. Keep it as a fallback for when
Tailscale is unavailable. Set `TUNNEL=cloudflared` to use it.

### VS Code Remote Tunnels

`scripts/remote_dev.sh vscode` downloads the official VS Code CLI and runs
`code tunnel`. Authenticate once with the printed GitHub device code, then use
`Remote-Tunnels: Connect to Tunnel` locally and open `/content/ComfyUI`. Your
editor agent can then read logs, patch custom nodes, and run commands on the
GPU host directly.

### sshd over Cloudflare

`scripts/remote_dev.sh ssh` with `SSH_PASSWORD` set. Useful only if you refuse
a Tailscale account. It needs `cloudflared` installed locally too, because the
SSH client reaches the tunnel through a `ProxyCommand`.

## Why weights do not live on Drive directly

ComfyUI memory-maps checkpoints. Reading a 21 GB file through the Drive FUSE
mount during model load is far slower than reading local NVMe, and it stalls
unpredictably. The cache in this project copies files from Drive to local disk
once per session instead, and times both routes so the choice stays evidence
based rather than assumed.

Outputs go the other way for the same reason. ComfyUI writes to local disk and
an rsync loop mirrors to Drive every 30 seconds, which avoids the stall you get
when a video node writes hundreds of megabytes straight to FUSE.

## Session lifecycle

Nothing on the ephemeral disk survives a disconnect. Everything this project
needs to rebuild a session is in the repository, so a new runtime is three
cells and one weight copy away from where you left off. Keep the Colab tab open
while you work in the tunnel tab, or the idle timer will reclaim the runtime.
