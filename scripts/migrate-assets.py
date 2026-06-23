#!/usr/bin/env python3
"""Copy images referenced in `reference-site/pages/` into `frontend/public/images/` and write an assets map.

It finds `src` attributes and background-image urls in the reference pages and copies
files from `reference-site/` to `frontend/public/images/`. Produces `frontend/public/assets-map.json`.
"""
import json
import os
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF_PAGES = ROOT / "reference-site" / "pages"
REF_ROOT = ROOT / "reference-site"
OUT_DIR = ROOT / "frontend" / "public" / "images"
MAP_FILE = ROOT / "frontend" / "public" / "assets-map.json"

IMG_URL_RE = re.compile(r"url\(([^)]+)\)")


def discover_image_paths():
    paths = set()
    for p in REF_PAGES.glob("*.html"):
        txt = p.read_text(encoding="utf-8", errors="ignore")
        # img src
        for m in re.finditer(r"<img[^>]+src=[\"']([^\"']+)[\"']", txt, re.I):
            paths.add(m.group(1))
        # background-image url(...)
        for m in IMG_URL_RE.finditer(txt):
            url = m.group(1).strip().strip('"\'')
            paths.add(url)
    return sorted(paths)


def normalize_src(src: str) -> str:
    # remove protocol and domain if present
    if src.startswith("http://") or src.startswith("https://"):
        # try to keep path after domain
        parts = src.split("/")
        # find first path segment after domain
        if len(parts) > 3:
            return "/" + "/".join(parts[3:])
        return src
    return src.lstrip("./")


def copy_images(paths):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    assets = {}
    for src in paths:
        src_norm = normalize_src(src)
        # handle leading slashes
        rel = src_norm.lstrip("/")
        # locate file under reference-site
        candidates = [REF_ROOT / rel, REF_ROOT / "images" / rel, REF_ROOT / rel.replace("uploads/", "uploads/")]
        found = None
        for c in candidates:
            if c.exists():
                found = c
                break
        if not found:
            # fallback: try to match filename anywhere under reference-site
            name = Path(rel).name
            for f in REF_ROOT.rglob(name):
                found = f
                break
        if not found:
            print(f"Warning: source not found for {src} (normalized {rel})")
            continue
        dest = OUT_DIR / found.name
        shutil.copy2(found, dest)
        assets[src] = str(Path("/images") / found.name)
        print(f"Copied {found} -> {dest}")

    MAP_FILE.write_text(json.dumps(assets, indent=2), encoding="utf-8")
    print(f"Wrote assets map to {MAP_FILE}")
    return assets


def main():
    paths = discover_image_paths()
    print(f"Discovered {len(paths)} referenced paths")
    copy_images(paths)


if __name__ == "__main__":
    main()
