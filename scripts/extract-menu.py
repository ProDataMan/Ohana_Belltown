#!/usr/bin/env python3
"""Extract menu items from reference-site HTML into database/menu.json.

This is a starter script. It looks for category headings (h1/h2/h3), item
names in `<strong>` tags, and descriptions following those tags. It is
designed to be robust for the current static snapshot and will need manual
review of `database/menu.json` after running.
"""
import json
import os
import re
from pathlib import Path

from bs4 import BeautifulSoup


ROOT = Path(__file__).resolve().parents[1]
REF_PAGES = Path(ROOT, "reference-site", "pages")
OUT_DIR = Path(ROOT, "database")
OUT_FILE = OUT_DIR / "menu.json"


def slugify(s: str) -> str:
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"^-|-$", "", s)
    return s or "item"


def extract_from_file(path: Path):
    html = path.read_text(encoding="utf-8", errors="ignore")
    soup = BeautifulSoup(html, "lxml")

    # Find top-level headings to use as categories
    categories = []
    # Heuristic: treat h2/h3 as category headings; fallback to 'Menu'
    headings = soup.find_all(["h2", "h3"]) or [None]

    if headings and headings[0]:
        for h in headings:
            cat_name = h.get_text(strip=True)
            if not cat_name:
                continue
            items = []

            # look for strong tags under the same section
            for strong in h.find_all_next("strong"):
                # stop if the strong appears under the next heading
                parent_heading = strong.find_previous(["h2", "h3"])
                if parent_heading is not None and parent_heading is not h:
                    break

                name = strong.get_text(" ", strip=True)
                # description: gather following sibling text until a <br> or next strong
                desc_parts = []
                node = strong.parent
                # search siblings after the strong tag
                for sib in strong.next_siblings:
                    if getattr(sib, "name", None) == "strong":
                        break
                    text = getattr(sib, "get_text", lambda **k: str(sib))(strip=True) if hasattr(sib, "get_text") else str(sib).strip()
                    if text:
                        desc_parts.append(text)
                description = " ".join(desc_parts).strip() or None

                # price: try to find currency pattern in description
                price = None
                if description:
                    m = re.search(r"\$\s*([0-9]+(?:\.[0-9]{1,2})?)", description)
                    if m:
                        try:
                            price = float(m.group(1))
                        except Exception:
                            price = None

                item = {
                    "id": slugify(name),
                    "name": name,
                    "description": description,
                    "price": price,
                    "image": None,
                    "tags": [],
                    "available": True,
                    "featured": False,
                }
                items.append(item)

            categories.append({"id": slugify(cat_name), "name": cat_name, "description": None, "sortOrder": 0, "items": items})
    else:
        # fallback: find strong tags across whole page
        items = []
        for strong in soup.find_all("strong"):
            name = strong.get_text(" ", strip=True)
            description = None
            item = {"id": slugify(name), "name": name, "description": description, "price": None, "image": None, "tags": [], "available": True, "featured": False}
            items.append(item)
        categories.append({"id": "menu", "name": "Menu", "description": None, "sortOrder": 0, "items": items})

    return categories


def main():
    pages = [
        REF_PAGES / "menu.html",
        REF_PAGES / "sushi.html",
        REF_PAGES / "drinks.html",
        REF_PAGES / "happy-hour.html",
    ]

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    menu = {
        "restaurant": {"name": "Ohana Sushi Bar & Grill", "location": "Belltown, Seattle"},
        "categories": [],
    }

    for p in pages:
        if not p.exists():
            print(f"Warning: {p} not found; skipping")
            continue
        cats = extract_from_file(p)
        # merge categories by id if already exists
        for cat in cats:
            existing = next((c for c in menu["categories"] if c["id"] == cat["id"]), None)
            if existing:
                existing["items"].extend(cat["items"])
            else:
                menu["categories"].append(cat)

    # write output
    OUT_FILE.write_text(json.dumps(menu, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {OUT_FILE}")


if __name__ == "__main__":
    main()
