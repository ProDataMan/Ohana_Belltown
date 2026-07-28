#!/usr/bin/env python3
"""
One-time Happy Hour menu update, sourced from the two printed Happy Hour
flyer photos (Mon-Fri 3-6pm) shared 2026-07-27:
  1. Prices existing items that were live with no price at all.
  2. Splits the single combined "Rolls" item into the 10 individually
     priced Classic Ohana Rolls.
  3. Adds items that are on the new flyer but weren't in the live data yet
     (Twisted Tea Can, three new cocktails, Beef Robata, and the whole
     "Ohana Specialty Rolls" group).
  4. Adds food-safety/handroll/sauce-upcharge disclaimers as category notes,
     matching the flyer's fine print.

Deliberately NOT touched (per 2026-07-27 confirmation): Raspberry Lemondrop,
Gold Apple at Sea, Aloha Iced Tea, Strawberry Sake Margarita, and Temaki Hand
Rolls aren't on the new flyer, but stay live as-is rather than being removed
or marked unavailable.

Run this yourself, logged in as staff — it asks for your own username/password
interactively (not stored, not passed as a command-line arg). Requires:
    pip install requests

Usage:
    python3 update_happy_hour_prices.py           # apply changes
    python3 update_happy_hour_prices.py --dry-run # just print what would change
"""
import getpass
import sys
import uuid

import requests

BASE = "https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io"

# (item name, new price, new description or None to leave description as-is)
PRICE_UPDATES = [
    ("Draft Beer", 7.5, None),
    ("Rotating Hard Cider", 7.5, None),
    ("House Red or White", 8, "(Red - Cabernet or White - Pinot Grigio)"),
    ("House Wells", 7.5, None),
    ("Hot or Cold Sake", 8.5, None),
    ("Blue Hawaiian", 14, None),
    ("Ohana Sliders", 11, None),
    ("Chicken Katsu Fillet", 9.5, None),
    ("BBQ Pork", 12, None),
    ("Gyoza", 11, None),
    ("Mini Ohana Salad", 8.5, None),
    ("Agedashi Tofu", 12, None),
    ("Sushi Special", 16, "4 pieces of nigiri - fish on rice (Chef's Choice)"),
    ("Sashimi Special", 18, "5 slices of fresh sashimi, sliced fish (Chef's Choice)"),
    ("Hawaiian Style Poke", 16, None),
]

# Brand-new items not in the live data at all yet: (category name, name, price, description)
NEW_ITEMS = [
    ("Drinks", "Twisted Tea Can", 7, None),
    ("Drinks", "Lychee Martini", 14, "Vodka and lychee juice"),
    ("Drinks", "Mauna Loa Sunrise", 14, "Gin, fresh lime juice, pineapple and grapefruit juice, splash black raspberry liqueur"),
    ("Drinks", "Red Bull Mai Tai", 16, "White Rum, Red Bull and orange juice with a splash of grenadine"),
    ("From the Beach", "Beef Robata", 12, "2 grilled skewers"),
]

# The single combined "Rolls" item becomes these 10 individually priced items.
CLASSIC_ROLLS = [
    ("California", 10),
    ("Cucumber", 6.5),
    ("Salmon", 7.5),
    ("Da Kine", 9.5),
    ("Veggie", 7.5),
    ("Spicy Tuna", 9.5),
    ("Belltown", 9.5),
    ("Spicy California", 10),
    ("Spicy Crunchy Salmon", 9.5),
    ("Spicy Crunchy Tuna", 9.5),
]

# New category on the flyer, not represented in the live data at all yet.
# Added into "From the Water" alongside the classic rolls above.
SPECIALTY_ROLLS = [
    ("Super Crunchy Rolls", 16, "Your choice of tuna or salmon"),
    ("Maui Wowie", 18, None),
    ("Volcano Roll", 18, None),
    ("Ohana Roll", 21, None),
]

CATEGORY_NOTES = {
    "From the Water": (
        "Rolls come in 5-8 pieces and can be ordered as a Handroll. "
        "Consuming raw or undercooked meats, poultry, seafood, shellfish, or eggs may "
        "increase your risk of foodborne illness, especially if you have a medical condition."
    ),
    "From the Beach": "Extra sauces are $2, BBQ and Gravy is $3. Happy Hour items not available for take out.",
}


def find_item(menu, name):
    for cat in menu["categories"]:
        if cat["section"] != "happy_hour":
            continue
        for item in cat["items"]:
            if item["name"].strip().lower() == name.strip().lower():
                return cat, item
    return None, None


def find_category(menu, name):
    for cat in menu["categories"]:
        if cat["section"] == "happy_hour" and cat["name"] == name:
            return cat
    return None


def new_item(name, price, description=None):
    item = {
        "id": str(uuid.uuid4()),
        "name": name,
        "images": [],
        "tags": [],
        "featured": False,
        "available": True,
        "happyHour": True,
        "modifiers": [],
        "price": price,
    }
    if description:
        item["description"] = description
    return item


def main():
    dry_run = "--dry-run" in sys.argv

    resp = requests.get(f"{BASE}/api/menu")
    resp.raise_for_status()
    menu = resp.json()

    for name, price, description in PRICE_UPDATES:
        cat, item = find_item(menu, name)
        if not item:
            print(f"SKIP price update (not found): {name!r}")
            continue
        old_price = item.get("price")
        item["price"] = price
        if description:
            item["description"] = description
        print(f"PRICE {name!r}: {old_price!r} -> {price!r}" + (" (+ description)" if description else ""))

    rolls_cat, rolls_item = find_item(menu, "Rolls")
    if rolls_item:
        idx = rolls_cat["items"].index(rolls_item)
        split_items = [new_item(name, price) for name, price in CLASSIC_ROLLS]
        rolls_cat["items"][idx:idx + 1] = split_items
        print(f"SPLIT 'Rolls' -> {len(split_items)} Classic Ohana Rolls items")
    else:
        print("SKIP split (not found): 'Rolls'")
        rolls_cat = find_category(menu, "From the Water")

    if rolls_cat:
        for name, price, description in SPECIALTY_ROLLS:
            _, existing = find_item(menu, name)
            if existing:
                print(f"SKIP new specialty roll (already exists): {name!r}")
                continue
            rolls_cat["items"].append(new_item(name, price, description))
            print(f"ADD {name!r} (Ohana Specialty Rolls) -> ${price}")

    for cat_name, name, price, description in NEW_ITEMS:
        _, existing = find_item(menu, name)
        if existing:
            print(f"SKIP new item (already exists): {name!r}")
            continue
        cat = find_category(menu, cat_name)
        if not cat:
            print(f"SKIP new item (category not found): {cat_name!r}")
            continue
        cat["items"].append(new_item(name, price, description))
        print(f"ADD {name!r} ({cat_name}) -> ${price}")

    for cat_name, note in CATEGORY_NOTES.items():
        cat = find_category(menu, cat_name)
        if cat:
            cat["note"] = note
            print(f"NOTE set on {cat_name!r}")

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
