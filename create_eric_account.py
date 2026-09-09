#!/usr/bin/env python3
"""
Creates a staff account "Eric" (username: Eric, temp password: 12345,
role: employee) for the Island Nights promoter, so he can log in and manage
performers at /island-nights-admin.html.

Run this yourself, logged in as an ADMIN staff account — it asks for your
own username/password interactively (not stored, not passed as a
command-line arg). Creating users requires admin, not just any staff login.
Requires:
    pip install requests

Usage:
    python3 create_eric_account.py
"""
import getpass
import sys

import requests

BASE = "https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io"


def main():
    username = input("Admin username or email: ").strip()
    password = getpass.getpass("Password: ")

    session = requests.Session()
    login_resp = session.post(f"{BASE}/api/auth/login", json={"username": username, "password": password})
    if login_resp.status_code != 200:
        print(f"Login failed: {login_resp.status_code} {login_resp.text}")
        sys.exit(1)

    users_resp = session.get(f"{BASE}/api/users")
    if users_resp.status_code != 200:
        print(f"Couldn't list users (need an admin account, not just any staff login): {users_resp.status_code} {users_resp.text}")
        sys.exit(1)
    users = users_resp.json()

    existing = next((u for u in users if u["username"].lower() == "eric"), None)
    if existing:
        print(f"An account @{existing['username']} already exists ({existing['displayName']}, "
              f"{existing['role']}, {'active' if existing['active'] else 'DEACTIVATED'}). Not creating a duplicate.")
        return

    create_resp = session.post(f"{BASE}/api/users", json={
        "username": "Eric",
        "displayName": "Eric",
        "password": "12345",
        "role": "employee",
    })
    if create_resp.status_code != 200:
        print(f"Failed to create account: {create_resp.status_code} {create_resp.text}")
        sys.exit(1)

    created = create_resp.json()
    print(f"Created: {created['displayName']} (@{created['username']}), role {created['role']}.")
    print("He'll be required to set his own password on first login.")
    print(f"He can log in at {BASE}/login and manage performers at {BASE}/island-nights-admin.html")
    print("\nNote: this is a standard employee account, same access level as any other staff login —")
    print("it also reaches menu editing, table orders, and the other staff admin pages, since this app")
    print("doesn't have a more narrowly-scoped role today. Let me know if you'd rather he be restricted")
    print("to just Island Nights and I can build that out.")


if __name__ == "__main__":
    main()
