#!/usr/bin/env python3
"""
Creates a staff account on the Ohana Belltown website.

The new person signs in at <site>/login with the username and temporary
password you give here, and is made to choose their own password on first
sign-in. Before creating anything, it checks the existing staff accounts so
you don't make a duplicate.

You run it as an ADMIN: it asks for your own admin username/password
interactively. Your password is never taken as a command-line argument, so
it doesn't end up in your shell history. Creating accounts requires an admin
login, not just any staff login.

Requires:
    pip install requests

Usage:
    python3 create_employee.py --username ronnie --password 'Temp-pass-123'
    python3 create_employee.py --username eric --password 'Temp-pass-123' \\
        --display-name "Eric" --role entertainmentProvider
    python3 create_employee.py --username kai --password 'Temp-pass-123' --dry-run

Roles:
    employee               Menu editor, loyalty, waitlist, table orders, and
                           other day-to-day staff tools (the default).
    admin                  Everything, including Analytics and creating or
                           managing staff accounts.
    entertainmentProvider  Outside performers/promoters: can only manage their
                           own upcoming entertainment booking(s).

Tip: pick a temporary password that isn't easy to guess (not "12345"). It
only has to last until their first sign-in, but anyone who knows it could
sign in as them until then.
"""
import argparse
import getpass
import sys

import requests

DEFAULT_BASE = "https://www.ohanasushigrill.com"
ROLES = ["employee", "admin", "entertainmentProvider"]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Create a staff account on the Ohana Belltown website.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Your own admin password is always asked for interactively, never passed as an argument.",
    )
    parser.add_argument("--username", required=True, help="the new person's sign-in username (case doesn't matter)")
    parser.add_argument("--password", required=True, help="their temporary password; they must change it at first sign-in")
    parser.add_argument("--display-name", help="name shown in the staff tools (default: the username, capitalized)")
    parser.add_argument("--role", choices=ROLES, default="employee", help="account type (default: employee)")
    parser.add_argument("--admin-username", help="your admin username or email (asked for if not given)")
    parser.add_argument("--base-url", default=DEFAULT_BASE, help=f"website address (default: {DEFAULT_BASE})")
    parser.add_argument("--yes", action="store_true", help="don't ask for confirmation when a similar name already exists")
    parser.add_argument("--dry-run", action="store_true", help="sign in and check for duplicates, but don't create anything")
    return parser.parse_args()


def main():
    args = parse_args()
    base = args.base_url.rstrip("/")
    new_username = args.username.strip()
    display_name = (args.display_name or new_username.capitalize()).strip()
    if not new_username or not args.password:
        sys.exit("Username and password can't be blank.")

    # Sign in as an admin. A requests.Session keeps the login cookie for
    # the calls below.
    admin_username = (args.admin_username or input("Your admin username or email: ")).strip()
    admin_password = getpass.getpass("Your admin password: ")
    session = requests.Session()
    login = session.post(f"{base}/api/auth/login", json={"username": admin_username, "password": admin_password})
    if login.status_code != 200:
        sys.exit(f"Sign-in failed ({login.status_code}): {login.text}")

    # Listing accounts also confirms this login is an admin.
    users_resp = session.get(f"{base}/api/users")
    if users_resp.status_code != 200:
        sys.exit(f"Couldn't list staff accounts (this needs an admin login, not just any staff login): "
                 f"{users_resp.status_code} {users_resp.text}")
    users = users_resp.json()

    print(f"\n{len(users)} existing staff account(s):")
    for u in users:
        status = "active" if u["active"] else "DEACTIVATED"
        print(f"  - {u['displayName']} (@{u['username']}): {u['role']}, {status}")

    # An exact username match is always a duplicate. The server would refuse
    # it anyway, but this gives a clearer message.
    exact = next((u for u in users if u["username"].lower() == new_username.lower()), None)
    if exact:
        state = "active" if exact["active"] else "DEACTIVATED (reactivate it on Manage Users instead)"
        sys.exit(f"\n@{exact['username']} already exists ({exact['displayName']}, {exact['role']}, {state}). Not creating a duplicate.")

    # A similar name (e.g. "ron" vs "ronnie") might be the same person under
    # a different username, so ask before going ahead.
    needle = new_username.lower()[:3]
    similar = [u for u in users if needle and (needle in u["username"].lower() or needle in u["displayName"].lower())]
    if similar and not args.yes and not args.dry_run:
        names = ", ".join(f"{u['displayName']} (@{u['username']})" for u in similar)
        answer = input(f"\nSimilar account(s) already exist: {names}. Create @{new_username} anyway? [y/N] ")
        if answer.strip().lower() not in ("y", "yes"):
            sys.exit("Not created.")

    if args.dry_run:
        print(f"\n--dry-run: would create {display_name} (@{new_username}) as {args.role}. Nothing was changed.")
        return

    create = session.post(f"{base}/api/users", json={
        "username": new_username,
        "displayName": display_name,
        "password": args.password,
        "role": args.role,
    })
    if create.status_code != 200:
        sys.exit(f"Couldn't create the account ({create.status_code}): {create.text}")

    created = create.json()
    print(f"\nCreated {created['displayName']} (@{created['username']}) as {created['role']}.")
    print(f"They sign in at {base}/login with that username and the temporary password,")
    print("and will be asked to choose their own password right away.")


if __name__ == "__main__":
    main()
