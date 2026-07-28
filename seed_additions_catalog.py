#!/usr/bin/env python3
"""
One-time migration: seeds the shared Additions Catalog and applies matching
modifiers to every menu item whose description already spells out an
upcharge (e.g. "Add bacon +$5.50", "YOSH size: $53.20"), based on a full
sweep of the live menu on 2026-07-28 (not just the ~15 items covered by the
earlier migrate_menu_items.py).

Once run, each of these items gets real checkboxes for customers ordering
from their table, and every addition becomes pickable from a dropdown in
the single-item editor (Sources/App/Menu.swift's new `additionsCatalog`
field) instead of being retyped from scratch each time.

"Yosh Size" is priced per item (the upsized total minus that item's own
base price) since it genuinely varies by dish — everything else uses one
consistent catalog price across every item that offers it.

Run this yourself, logged in as staff — it asks for your own username/password
interactively (not stored, not passed as a command-line arg). Requires:
    pip install requests

Usage:
    python3 seed_additions_catalog.py           # apply changes
    python3 seed_additions_catalog.py --dry-run # just print what would change
"""
import getpass
import sys
import uuid

import requests

BASE = "https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io"

# The shared catalog — one consistent price per addition, reused across
# every item that offers it (except Yosh Size, priced per item below).
CATALOG = {
    "Add Bacon": 5.50,
    "Add Fried Egg": 3.50,
    "Add Spam": 6,
    "Add Salmon": 6,
    "Add Shrimp": 5,
    "Add Katsu": 6,
    "Add Chicken": 6,
    "Sub Fried Rice": 6,
    "Sub Kalua Pork": 0,
    "Sub Noodles": 3,
    "Extra Tofu": 3,
    "Add Strawberry": 1.50,
    "Add Mango": 1.50,
    "Add Banana": 1.50,
    "Yosh Size": 25.20,  # representative default; real per-item prices below override this
}

# (item name, [(addition name, price override or None to use the catalog price), ...])
ITEM_MODIFIERS = {
    "Spicy Fried Rice": [("Add Fried Egg", None), ("Add Spam", None), ("Add Bacon", None)],
    "Veggie Spring Rolls": [("Add Salmon", 5), ("Add Shrimp", None)],
    "Loco Moco": [
        ("Sub Fried Rice", None), ("Sub Kalua Pork", None), ("Add Bacon", None),
        ("Add Katsu", None), ("Add Spam", None), ("Yosh Size", 25.20),
    ],
    "Kalua Pork": [("Yosh Size", 24.30)],
    "Curry Rice": [("Add Katsu", None), ("Yosh Size", 23.40)],
    "Adobo": [("Yosh Size", 25.20)],
    "Yakisoba": [("Extra Tofu", None), ("Add Chicken", 4), ("Yosh Size", 20.70)],
    "Chicken Katsu": [("Yosh Size", 25.20)],
    "Ginger Chicken Broccoli": [("Sub Noodles", None), ("Yosh Size", 25.20)],
    "Big Kahuna Fish & Chips": [("Yosh Size", 26.10)],
    "Ohana Cheese Burger": [("Add Bacon", None)],
    "Island Style Baby Back Ribs": [("Yosh Size", 28.80)],
    "Ohana Salad": [("Add Chicken", None), ("Add Salmon", None), ("Yosh Size", 11.70)],
    "Chicken Teriyaki / Spicy Chicken Teriyaki": [("Yosh Size", 25.20)],
    "Salmon Teriyaki": [("Yosh Size", 27.90)],
    "Beef Teriyaki / Spicy Beef Teriyaki": [("Yosh Size", 27.90)],
    "Virgin Pina Colada": [("Add Strawberry", None), ("Add Mango", None), ("Add Banana", None)],
}

# NOTE: "Chicken Teriyaki / Spicy Chicken Teriyaki" and "Beef Teriyaki /
# Spicy Beef Teriyaki" are still combined listings (see migrate_menu_items.py,
# which splits these into separately orderable items but hasn't been run
# yet) — Yosh Size is applied to the combined item here regardless, so it
# isn't lost whenever that split does happen.


def find_item(menu, name):
    for cat in menu["categories"]:
        for item in cat["items"]:
            if item["name"].strip().lower() == name.strip().lower():
                return cat, item
    return None, None


def main():
    dry_run = "--dry-run" in sys.argv

    resp = requests.get(f"{BASE}/api/menu")
    resp.raise_for_status()
    menu = resp.json()

    existing_catalog = {c["name"]: c for c in menu.get("additionsCatalog", [])}
    new_catalog = list(menu.get("additionsCatalog", []))
    for name, price in CATALOG.items():
        if name not in existing_catalog:
            new_catalog.append({"id": str(uuid.uuid4()), "name": name, "priceDelta": price})
    menu["additionsCatalog"] = new_catalog
    print(f"Catalog: {len(existing_catalog)} existing + {len(new_catalog) - len(existing_catalog)} new = {len(new_catalog)} total")

    applied_count = 0
    for item_name, mods in ITEM_MODIFIERS.items():
        cat, item = find_item(menu, item_name)
        if not item:
            print(f"SKIP (not found): {item_name!r}")
            continue
        existing_names = {m["name"] for m in item.get("modifiers", [])}
        added = 0
        for mod_name, price_override in mods:
            if mod_name in existing_names:
                continue
            price = price_override if price_override is not None else CATALOG[mod_name]
            item.setdefault("modifiers", []).append({
                "id": str(uuid.uuid4()), "name": mod_name, "priceDelta": price,
            })
            added += 1
        if added:
            applied_count += 1
            print(f"MODIFIERS {item_name!r}: +{added} add-on(s)")

    print(f"\n{applied_count} item(s) got new modifiers.")

    if dry_run:
        print("\n--dry-run: no changes were sent.")
        return

    username = input("\nStaff username or email: ").strip()
    password = getpass.getpass("Password: ")

    session = requests.Session()
    login_resp = session.post(f"{BASE}/api/auth/login", json={"username": username, "password": password})
    if not login_resp.ok:
        print(f"Login failed ({login_resp.status_code}): {login_resp.text}")
        sys.exit(1)
    print(f"Logged in as {login_resp.json().get('displayName')}")

    put_resp = session.put(f"{BASE}/api/menu", json=menu)
    if not put_resp.ok:
        print(f"Save failed ({put_resp.status_code}): {put_resp.text}")
        sys.exit(1)
    print("Menu updated successfully.")


if __name__ == "__main__":
    main()
