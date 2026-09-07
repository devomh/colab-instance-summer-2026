#!/usr/bin/env python3
"""Download a model profile into ComfyUI/models, using the Drive cache.

Profiles are plain-text manifests in config/models/. Two line formats:

    hf   <repo_id> <path_in_repo>  <dest_subdir> [dest_name]
    url  <url>                     <dest_subdir> <dest_name>

For every file the script prefers the Google Drive cache when the file is
already there, and otherwise downloads from the source and writes a copy back
to the cache in the background. Both paths are timed, and the running averages
are printed so you can see which one is actually faster on this runtime.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path

os.environ.setdefault("HF_HUB_ENABLE_HF_TRANSFER", "1")

REPO_ROOT = Path(__file__).resolve().parent.parent
PROFILE_DIR = REPO_ROOT / "config" / "models"

COMFY_ROOT = Path(os.environ.get("COMFY_ROOT") or "/content/ComfyUI")
DRIVE_ROOT = Path(os.environ.get("DRIVE_ROOT") or "/content/drive/MyDrive/colab-comfy")
MODELS = COMFY_ROOT / "models"
_cache = os.environ.get("MODEL_CACHE", str(DRIVE_ROOT / "models_cache"))
CACHE = Path(_cache) if _cache else None
BENCH = DRIVE_ROOT / "logs" / "transfer_bench.jsonl"

GB = 1_000_000_000


def token() -> str | None:
    tok = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    if tok:
        return tok
    try:  # Colab secret, if the notebook did not export it already
        from google.colab import userdata  # type: ignore

        return userdata.get("HF_TOKEN")
    except Exception:
        return None


def record(name: str, nbytes: int, seconds: float, source: str) -> None:
    rate = nbytes / seconds / 1e6 if seconds > 0 else 0.0
    print(f"    {nbytes/GB:.2f} GB in {seconds:.0f}s = {rate:.0f} MB/s from {source}")
    try:
        BENCH.parent.mkdir(parents=True, exist_ok=True)
        with BENCH.open("a") as fh:
            fh.write(json.dumps({
                "ts": time.time(), "file": name, "bytes": nbytes,
                "seconds": round(seconds, 2), "mbps": round(rate, 1), "source": source,
            }) + "\n")
    except OSError:
        pass  # no Drive, benchmarking is optional


def summarise() -> None:
    if not BENCH.exists():
        return
    by_source: dict[str, list[float]] = defaultdict(list)
    for line in BENCH.read_text().splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if row.get("bytes", 0) > GB:  # ignore small files, they are noise
            by_source[row["source"]].append(row["mbps"])
    if len(by_source) < 1:
        return
    print("\ntransfer history for files over 1 GB:")
    for source, rates in sorted(by_source.items()):
        print(f"  {source:<12} {sum(rates)/len(rates):6.0f} MB/s mean over {len(rates)} files")
    if len(by_source) > 1:
        best = max(by_source, key=lambda s: sum(by_source[s]) / len(by_source[s]))
        print(f"  -> {best} is the faster source on this runtime so far")


def link(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink() or dest.exists():
        if dest.is_symlink() and dest.resolve() == src.resolve():
            return
        dest.unlink()
    dest.symlink_to(src)


def copy_timed(src: Path, dest: Path, source_label: str) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    start = time.time()
    shutil.copyfile(src, tmp)
    tmp.replace(dest)
    record(dest.name, dest.stat().st_size, time.time() - start, source_label)


def cache_write_back(local: Path, rel: str) -> None:
    """Copy a freshly downloaded file to the Drive cache, in the background."""
    if CACHE is None or not CACHE.parent.exists():
        return
    target = CACHE / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = f"{target}.part"
    subprocess.Popen(
        ["bash", "-c", f'cp --no-preserve=mode "{local}" "{tmp}" && mv "{tmp}" "{target}"'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
    )
    print(f"    caching to Drive in the background -> {target}")


def obtain(rel: str, fetch, use_cache: bool) -> None:
    """rel is the path relative to ComfyUI/models, e.g. 'vae/foo.safetensors'."""
    dest = MODELS / rel
    if dest.exists():
        print(f"  have {rel}")
        return
    cached = (CACHE / rel) if (use_cache and CACHE) else None
    if cached is not None and cached.exists():
        print(f"  {rel} <- Drive cache")
        copy_timed(cached, dest, "drive")
        return
    fetch(dest, rel)


def fetch_hf(repo: str, path_in_repo: str, rel: str, dest: Path) -> None:
    from huggingface_hub import hf_hub_download

    print(f"  {rel} <- huggingface {repo}")
    start = time.time()
    local = Path(hf_hub_download(repo_id=repo, filename=path_in_repo, token=token()))
    elapsed = time.time() - start
    link(local, dest)
    record(dest.name, local.stat().st_size, elapsed, "huggingface")
    cache_write_back(local, rel)


def fetch_url(url: str, rel: str, dest: Path) -> None:
    print(f"  {rel} <- {url}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    start = time.time()
    subprocess.run(
        ["aria2c", "-c", "-x", "16", "-s", "16", "-k", "1M",
         "-d", str(dest.parent), "-o", dest.name, url],
        check=True,
    )
    record(dest.name, dest.stat().st_size, time.time() - start, "http")
    cache_write_back(dest, rel)


def profiles() -> list[str]:
    return sorted(p.stem for p in PROFILE_DIR.glob("*.txt"))


def run(profile: str, use_cache: bool) -> None:
    manifest = PROFILE_DIR / f"{profile}.txt"
    if not manifest.exists():
        sys.exit(f"unknown profile {profile!r}; available: {', '.join(profiles())}")
    print(f"profile: {profile}   cache: {CACHE if use_cache and CACHE else 'disabled'}")
    for lineno, raw in enumerate(manifest.read_text().splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        try:
            if parts[0] == "hf":
                repo, path_in_repo, dest_dir = parts[1:4]
                name = parts[4] if len(parts) > 4 else Path(path_in_repo).name
                rel = f"{dest_dir}/{name}"
                obtain(rel, lambda d, r, a=repo, b=path_in_repo: fetch_hf(a, b, r, d), use_cache)
            elif parts[0] == "url":
                rel = f"{parts[2]}/{parts[3]}"
                obtain(rel, lambda d, r, u=parts[1]: fetch_url(u, r, d), use_cache)
            else:
                sys.exit(f"{manifest}:{lineno}: unknown line type {parts[0]!r}")
        except IndexError:
            sys.exit(f"{manifest}:{lineno}: malformed line: {raw}")
    summarise()


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("profile", nargs="?", help="manifest name in config/models/")
    ap.add_argument("--list", action="store_true", help="list available profiles")
    ap.add_argument("--no-cache", action="store_true", help="ignore the Drive cache")
    ap.add_argument("--bench", action="store_true", help="print transfer history and exit")
    args = ap.parse_args()
    if args.bench:
        summarise()
    elif args.list or not args.profile:
        print("\n".join(profiles()))
    else:
        run(args.profile, not args.no_cache)
