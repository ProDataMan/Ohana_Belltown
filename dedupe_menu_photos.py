#!/usr/bin/env python3
"""
Finds menu item photos in /uploads/ that are byte-identical duplicates
(same picture uploaded more than once under a different random filename),
repoints every menu item that references a duplicate at a single canonical
copy, then deletes the now-unused duplicate files from the server.

Only looks at /uploads/ files referenced by at least one menu item — those
are the ones that show up in /gallery. It can't see uploaded files that
aren't referenced anywhere (no directory-listing API exists), so a photo
nobody's item points to won't be found or touched either way.

Run this yourself, logged in as staff — it asks for your own username/password
interactively (not stored, not passed as a command-line arg). Requires:
    pip install requests

Usage:
    python3 dedupe_menu_photos.py           # apply changes
    python3 dedupe_menu_photos.py --dry-run # just print what would change
"""
import hashlib
import getpass
import sys
from collections import defaultdict

import requests

BASE = "https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io"


def hash_all_referenced_photos(menu, session):
    urls = set()
    for cat in menu["categories"]:
        for item in cat["items"]:
            for img in item.get("images", []):
                if img.startswith("/uploads/"):
                    urls.add(img)

    print(f"{len(urls)} distinct /uploads/ photo(s) referenced by the menu — downloading to compare...")
    by_hash = defaultdict(list)
    for url in sorted(urls):
        resp = session.get(BASE + url, timeout=15)
        resp.raise_for_status()
        digest = hashlib.sha256(resp.content).hexdigest()
        by_hash[digest].append(url)
    return by_hash


def main():
    dry_run = "--dry-run" in sys.argv
    session = requests.Session()

    resp = session.get(f"{BASE}/api/menu")
    resp.raise_for_status()
    menu = resp.json()

    by_hash = hash_all_referenced_photos(menu, session)
    dup_groups = [urls for urls in by_hash.values() if len(urls) > 1]

    if not dup_groups:
        print("No duplicate photos found. Nothing to do.")
        return

    # Canonical = alphabetically first in each group, purely for determinism.
    redirect = {}
    for group in dup_groups:
        canonical = sorted(group)[0]
        for url in group:
            if url != canonical:
                redirect[url] = canonical
        print(f"DUPLICATE GROUP: keep {canonical!r}, remove {sorted(set(group) - {canonical})}")

    changed_items = 0
    for cat in menu["categories"]:
        for item in cat["items"]:
            images = item.get("images", [])
            if not images:
                continue
            new_images = []
            for img in images:
                resolved = redirect.get(img, img)
                if resolved not in new_images:  # de-dupe within the same item's gallery
                    new_images.append(resolved)
            if new_images != images:
                print(f"REPOINT {item['name']!r}: {images} -> {new_images}")
                item["images"] = new_images
                changed_items += 1

    to_delete = sorted(redirect.keys())
    print(f"\n{len(dup_groups)} duplicate group(s), {changed_items} item(s) repointed, {len(to_delete)} file(s) to delete.")

    if dry_run:
        print("\n--dry-run: no changes were sent.")
        return

    username = input("\nStaff username or email: ").strip()
    password = getpass.getpass("Password: ")

    login_resp = session.post(f"{BASE}/api/auth/login", json={"username": username, "password": password})
    if not login_resp.ok:
        print(f"Login failed ({login_resp.status_code}): {login_resp.text}")
        sys.exit(1)
    print(f"Logged in as {login_resp.json().get('displayName')}")

    put_resp = session.put(f"{BASE}/api/menu", json=menu)
    if not put_resp.ok:
        print(f"Menu save failed ({put_resp.status_code}): {put_resp.text}")
        sys.exit(1)
    print("Menu references updated.")

    for url in to_delete:
        filename = url.rsplit("/", 1)[-1]
        del_resp = session.delete(f"{BASE}/api/uploads/{filename}")
        if del_resp.status_code == 204:
            print(f"DELETED {url}")
        else:
            print(f"FAILED to delete {url}: {del_resp.status_code} {del_resp.text}")


if __name__ == "__main__":
    main()
