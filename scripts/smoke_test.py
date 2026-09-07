#!/usr/bin/env python3
"""Queue one image through a running ComfyUI and report what came out.

Verifies the whole chain without a browser: server up, checkpoint loads, GPU
sampling works, and the file lands where the Drive sync loop will find it.
"""
from __future__ import annotations

import argparse
import json
import os
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PORT = os.environ.get("COMFY_PORT", "8188")
BASE = f"http://127.0.0.1:{PORT}"


def post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def get(path: str) -> dict:
    with urllib.request.urlopen(BASE + path, timeout=30) as resp:
        return json.load(resp)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--workflow", default=str(REPO_ROOT / "workflows" / "api" / "smoke_sd15_api.json"))
    ap.add_argument("--checkpoint", help="override ckpt_name in the workflow")
    ap.add_argument("--prompt", help="override the positive prompt")
    ap.add_argument("--timeout", type=int, default=600)
    args = ap.parse_args()

    graph = json.loads(Path(args.workflow).read_text())
    for node in graph.values():
        if args.checkpoint and node["class_type"] == "CheckpointLoaderSimple":
            node["inputs"]["ckpt_name"] = args.checkpoint
    if args.prompt and "6" in graph:
        graph["6"]["inputs"]["text"] = args.prompt

    try:
        stats = get("/system_stats")
    except urllib.error.URLError as exc:
        print(f"ComfyUI is not answering on {BASE}: {exc}")
        return 1
    for dev in stats.get("devices", []):
        print(f"device: {dev.get('name')}  vram {dev.get('vram_total', 0)/1e9:.0f} GB")

    client_id = str(uuid.uuid4())
    started = time.time()
    prompt_id = post("/prompt", {"prompt": graph, "client_id": client_id})["prompt_id"]
    print(f"queued {prompt_id}")

    while time.time() - started < args.timeout:
        history = get(f"/history/{prompt_id}")
        entry = history.get(prompt_id)
        if entry:
            status = entry.get("status", {})
            if status.get("status_str") == "error" or not status.get("completed", True):
                print(json.dumps(status, indent=2)[:2000])
                return 1
            files = [
                img["filename"]
                for out in entry.get("outputs", {}).values()
                for img in out.get("images", []) + out.get("gifs", [])
            ]
            print(f"finished in {time.time() - started:.0f}s: {', '.join(files) or 'no files'}")
            return 0 if files else 1
        time.sleep(2)

    print(f"timed out after {args.timeout}s")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
