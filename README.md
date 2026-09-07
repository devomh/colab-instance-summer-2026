# colab-instance-summer-2026

Run ComfyUI on a Google Colab GPU and drive it from your own machine: the web
UI in your local browser, a shell over Tailscale SSH, and your editor over a
VS Code tunnel. Google Drive holds everything that must survive the runtime.

## What lives where

| Path | Location | Why |
|---|---|---|
| `ComfyUI/` | Colab ephemeral disk | Fast local NVMe, rebuilt every session |
| `models/` | Colab ephemeral disk | Loaded into VRAM, must not read over Drive FUSE |
| `models_cache/` | Drive | Copy of downloaded weights, avoids re-fetching gated repos |
| `user/` | Drive symlink | Settings and saved workflows, small and needs live writes |
| `input/` | Drive symlink | Images and clips you feed into workflows |
| `outputs/` | Drive via rsync | Written locally, mirrored every 30s so big video never stalls |

## First session

1. Runtime type: **T4** or **L4** for images, **A100 High-RAM** only for video.
2. Colab secrets panel: add `TS_AUTHKEY` and `HF_TOKEN`, notebook access on.
3. Open `notebooks/comfyui_colab.ipynb` in Colab and run cells 1 to 5.
4. Cell 4 prints the address. On Tailscale it is `http://<tailscale-ip>:8188`,
   reachable only from your own devices.
5. Cell 5 queues one image through the API and prints the output filename.

Later sessions repeat the same cells. Bootstrap is idempotent and weights come
back from the Drive cache.

## Scripts

| Script | Does |
|---|---|
| `scripts/bootstrap.sh` | Installs ComfyUI and custom nodes, wires Drive |
| `scripts/fetch_models.py` | Downloads a model profile, prefers the Drive cache |
| `scripts/launch.sh` | Starts ComfyUI, the output sync loop, and the tunnel |
| `scripts/tunnel.sh` | Tailscale or Cloudflare, called by `launch.sh` |
| `scripts/remote_dev.sh` | VS Code tunnel, or sshd over Cloudflare |
| `scripts/smoke_test.py` | Queues one workflow through the API, no browser |
| `scripts/stop.sh` | Stops everything, final flush to Drive |

Configuration is `config/comfy.env`, written by notebook cell 1. Copy
`config/comfy.env.example` if you run the scripts by hand.

## Model profiles

Manifests in `config/models/`. Add a line to add a file.

| Profile | Size | Needs |
|---|---|---|
| `smoke` | 2 GB | Any GPU |
| `z-image-turbo` | 12 GB | L4 or newer, few-step sampler |
| `flux1-dev` | 17 GB | L4 or better |
| `qwen-image` | 30 GB | 40 GB VRAM |
| `ltx-2.5` | 39 GB | A100 40GB, `HF_TOKEN`, license accepted on the model page |

`fetch_models.py` times every transfer and writes the results to
`Drive/colab-comfy/logs/transfer_bench.jsonl`. Run it with `--bench` to see
whether Hugging Face or the Drive cache is actually faster for you.

## Compute budget

Colab Pro, included with Google AI Pro, gives 100 compute units per month.
Published burn rates disagree, so read the real figure in Colab's resources
panel. An A100 plausibly costs 5 to 15 units per hour, which is between 7 and
18 hours a month. Do image work on a cheap GPU and save the A100 for video.

See `docs/remote-access-options.md` for how the control channels compare.
