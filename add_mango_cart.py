#!/usr/bin/env python3
"""
One-time menu addition: adds Golden Road Brewing's Mango Cart (12oz can) to
the Beer category on the drinks menu, with a product photo.

The photo (FoodPics/golden-road-mango-cart.jpg) is Golden Road's own can and
glass product shot from goldenroad.la/mango-cart, cropped square on white.

Run this yourself, logged in as staff. It asks for your username/password
interactively (not stored, not passed as a command-line arg). Requires:
    pip install requests

Usage:
    python3 add_mango_cart.py           # apply changes
    python3 add_mango_cart.py --dry-run # just print what would change
"""
import getpass
import os
import sys
import uuid

import requests

BASE = "https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io"
PHOTO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "FoodPics", "golden-road-mango-cart.jpg")

NAME = "Mango Cart (12oz Can)"
DESCRIPTION = (
    "Golden Road Brewing's light wheat ale brewed with real mango, inspired by "
    "the street fruit carts of Los Angeles. Crisp and refreshing. 4% ABV."
)
# Same as the Kona draft beers (Kona Rotating, Kona Longboard).
PRICE = 8.5
# Inserted alphabetically among the bottles/cans, ahead of this item.
INSERT_BEFORE = "Mexican Beer (Rotator)"


def main():
    dry_run = "--dry-run" in sys.argv

    menu = requests.get(f"{BASE}/api/menu").json()
    beer = next((c for c in menu["categories"] if c["section"] == "drinks" and c["name"] == "Beer"), None)
    if beer is None:
        print("Couldn't find the Beer category on the drinks menu.")
        sys.exit(1)
    if any(item["name"].lower().startswith("mango cart") for item in beer["items"]):
        print("Mango Cart is already on the beer menu; nothing to do.")
        return

    item = {
        "id": str(uuid.uuid4()).upper(),
        "name": NAME,
        "description": DESCRIPTION,
        "price": PRICE,
        "images": [],
        "tags": [],
        "modifiers": [],
        "choiceGroups": [],
        "available": True,
        "featured": False,
        "happyHour": False,
        "requiresModifierSelection": False,
    }
    names = [i["name"] for i in beer["items"]]
    position = names.index(INSERT_BEFORE) if INSERT_BEFORE in names else len(names)

    print(f"\nWill add to drinks > Beer at position {position + 1} of {len(names) + 1}:")
    print(f"  {NAME} — ${PRICE:.2f}")
    print(f"  {DESCRIPTION}")
    print(f"  photo: {PHOTO}")
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

    with open(PHOTO, "rb") as f:
        upload_resp = session.post(f"{BASE}/api/upload", files={"image": ("golden-road-mango-cart.jpg", f, "image/jpeg")})
    if not upload_resp.ok:
        print(f"Photo upload failed ({upload_resp.status_code}): {upload_resp.text}")
        sys.exit(1)
    item["images"] = [upload_resp.json()["url"]]
    print(f"Photo uploaded: {item['images'][0]}")

    # Re-read right before saving so an edit someone made in the menu editor
    # while this was waiting for a password isn't overwritten.
    menu = session.get(f"{BASE}/api/menu").json()
    beer = next(c for c in menu["categories"] if c["section"] == "drinks" and c["name"] == "Beer")
    names = [i["name"] for i in beer["items"]]
    position = names.index(INSERT_BEFORE) if INSERT_BEFORE in names else len(names)
    beer["items"].insert(position, item)

    put_resp = session.put(f"{BASE}/api/menu", json=menu)
    if not put_resp.ok:
        print(f"Save failed ({put_resp.status_code}): {put_resp.text}")
        sys.exit(1)
    print(f"Added {NAME} to the beer menu: {BASE}/drinks")


if __name__ == "__main__":
    main()
