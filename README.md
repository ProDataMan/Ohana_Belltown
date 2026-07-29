# Ohana Belltown Website

[![Build and deploy](https://github.com/ProDataMan/Ohana_Belltown/actions/workflows/deploy-server.yml/badge.svg)](https://github.com/ProDataMan/Ohana_Belltown/actions/workflows/deploy-server.yml)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Vapor](https://img.shields.io/badge/Vapor-server-2ED0FF)
[![Live site](https://img.shields.io/badge/live%20site-ohanabelltown-ff2f8f)](https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io)

A Swift/Vapor server powering [Ohana Belltown](https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io)'s
full website: marketing pages, the complete food/sushi/drinks/happy-hour menu,
a staff editor, a digital punch card, a walk-in waitlist, and an events calendar
— deployed on Azure Container Apps.

This started as a static-site capture of the old Weebly site (see
`docs/migration-plan.md` and `docs/ohana-project-plan.md` for that history);
it has since been rebuilt as a real server-backed app and those early docs are
now historical background rather than the current plan.

### Contents

[Live site](#live-site) ·
[Architecture](#architecture) ·
[Pages & routes](#pages--routes) ·
[What's shipped](#whats-shipped) ·
[Known gaps](#known-gaps--not-yet-implemented) ·
[Google/Apple/Facebook Sign-In setup](#setting-up-googleapplefacebook-sign-in) ·
[Local development](#local-development) ·
[Other docs](#other-docs-in-this-repo)

## Live site

- **Site:** https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io
- **Staff login:** `/login`
- **Staff menu editor:** `/edit.html` (any logged-in employee)
- **Staff loyalty admin:** `/loyalty-admin.html` (any logged-in employee)
- **Staff events admin:** `/events-admin.html` (admin only)
- **Manage users:** `/manage-users.html` (admin only)
- **Printable table QR cards:** `/table-card.html`

## Architecture

- **Server:** Swift 6 / [Vapor](https://vapor.codes), single executable target (`server/Sources/App`)
- **Persistence:** plain JSON files on an Azure Files–backed volume (no database) —
  `menu.json`, `events.json`, `loyalty.json`, `users.json`, plus an `uploads/` directory for photos.
  Falls back to `Resources/seed-menu.json` on first boot if no persisted data exists yet.
- **Auth:** Vapor's built-in `Bcrypt` (password hashing) and `SessionsMiddleware` (`.memory` driver —
  sessions don't survive a restart, so a deploy logs everyone out; acceptable for a small internal team).
  Google/Apple/Facebook OAuth on top of that (see [Setting up Google/Apple/Facebook Sign-In](#setting-up-googleapplefacebook-sign-in)),
  using `swift-crypto`'s `P256.Signing` directly for Apple's required client-secret JWT signing.
- **Hosting:** Azure Container Apps (Consumption plan), resource group `Ohana`, app `ohana-belltown-server`
- **Images:** [ghcr.io/prodataman/ohana-belltown-server](https://ghcr.io/prodataman/ohana-belltown-server) (GitHub Container Registry, public)
- **CI/CD:** `.github/workflows/deploy-server.yml` — on push to `main`, builds and pushes the
  Docker image, then runs `az containerapp update` via OIDC federation (no stored Azure secrets).
  The Dockerfile copies both `Sources/` and `Tests/` into the build stage (SPM needs the test
  target's directory to exist even though the release image only builds `--product App`) —
  if you ever add another target, it needs the same treatment or you'll hit a confusing
  "overlapping sources" error.
- **Third-party integrations:** Google Places API (business photos), ChowNow (online ordering, linked out — not embedded)

### Required environment / secrets on the Container App

| Variable | Purpose |
|---|---|
| `DATA_DIR` | Path to the mounted persistent volume for JSON data + uploads |
| `PORT` | Server port (Container Apps sets this) |
| `GOOGLE_PLACES_API_KEY` | Server-side only, proxies Google Business photos |
| `GOOGLE_PLACE_ID` | Ohana Belltown's Google Place ID |
| `PUBLIC_BASE_URL` | The site's own public HTTPS origin, used to build OAuth redirect URIs. Defaults to the production URL above if unset — only needs overriding for local dev (`http://localhost:8080`). |
| `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` | Google Sign-In. Not set yet — see [`docs/oauth-setup.md`](docs/oauth-setup.md). |
| `APPLE_OAUTH_CLIENT_ID`, `APPLE_OAUTH_TEAM_ID`, `APPLE_OAUTH_KEY_ID`, `APPLE_OAUTH_PRIVATE_KEY` | Sign in with Apple. Not set yet — needs a paid Apple Developer Program enrollment first. See [`docs/oauth-setup.md`](docs/oauth-setup.md). |
| `FACEBOOK_OAUTH_APP_ID`, `FACEBOOK_OAUTH_APP_SECRET` | Facebook Login — free, no paid tier required. Not set yet — see [`docs/oauth-setup.md`](docs/oauth-setup.md). |

`STAFF_PIN` is no longer used — it was retired in favor of real per-user login (see below) and can be removed from the Container App if still set.

## Pages & routes

| Path | What it is |
|---|---|
| `/`, `/about`, `/local`, `/contact`, `/catering`, `/gallery` | Marketing pages |
| `/faq` | Common questions — reservations, hours, parking, dietary/allergen info, private events, gift cards |
| `/privacy`, `/terms` | Privacy Policy and Terms of Service — linked from every public page's footer and the signup form |
| `/menu`, `/sushi`, `/drinks`, `/happy-hour` | Menu sections (216 items total) — search box + allergen/dietary filter chips |
| `/specials` | Stable landing page (today's specials, "Popular Right Now" auto-ranked from real view data, Happy Hour hours, drinks teaser) for linking from social media/bio links |
| `/rewards` | Customer-facing sushi punch card: check a card by phone, submit a photo/social bonus claim |
| `/waitlist` | Join the walk-in waitlist from your phone before arriving |
| `/waitlist-admin.html` | Staff: view the live waitlist queue, text a guest their table's ready, remove entries. **Any logged-in employee.** |
| `/login` | Staff login. First run (zero accounts) shows a one-time "create the first admin" form instead. |
| `/account.html` | Self-service: view own profile, log out |
| `/change-password.html` | Self-service password change (requires current password) |
| `/edit.html` | Staff menu editor (bulk) — prices, descriptions, photos, tags, featured/sold-out/Happy-Hour toggles. **Any logged-in employee.** |
| `/edit-item.html?id=...` | Staff: single-item editor — same fields as above plus delete, for editing one item quickly. **Any logged-in employee.** |
| `/loyalty-admin.html` | Staff: punch a card, redeem a reward, approve/deny bonus claims. **Any logged-in employee.** |
| `/events-admin.html` | Staff: edit the events/specials shown on `/local`. **Admin only.** |
| `/create-account.html`, `/manage-users.html` | Admin: create staff accounts, change roles, reset passwords. **Admin only.** |
| `/table-card.html` | Printable QR-code table tents — one per real table/seat (43 total: dining room, bar, sushi bar, deck), each QR unique to its spot |
| `/scan` | Smart QR landing: redirects to `/happy-hour` during Happy Hour (Mon&ndash;Fri, 3&ndash;6pm Pacific) or `/menu` otherwise, carrying the table id along if the QR had one |
| `/table-orders-admin.html` | Staff: a visual floor map (flashes a table the moment it needs entry, again once it's awaiting delivery) plus "Needs Entry" and "Awaiting Delivery" list queues for dine-in table orders, and the staff-on-duty count used for prep-time estimates. **Any logged-in employee.** |
| `/signup`, `/account-login` | Customer registration and login (separate from staff accounts). `/account-login` links to `/login` for staff. |
| `/logged-in` | Shared post-login router — sends staff to `/edit.html` and customers to `/my-account.html`. Where Google Sign-In lands after a successful login. |
| `/my-account.html` | Customer's own account page — profile, password change |
| `/forgot-password.html`, `/reset-password.html` | Customer self-service password reset |
| `/api/menu`, `/api/events`, `/api/loyalty/*`, `/api/auth/*`, `/api/users/*`, `/api/account/*`, `/api/customer/*` | JSON API backing all of the above |

## What's shipped

<details open>
<summary><strong>Content & migration</strong></summary>

- Full real menu — 216 items across Food/Sushi/Drinks/Happy Hour, transcribed from the current printed menu
- 204/216 items have written descriptions; brand-name drinks researched and described
- Home, About, Local, Contact, Catering pages with real copy, ported from the old Weebly site
- `/faq` — reservations, hours, parking, dietary/allergen info, private events, gift cards. Deliberately doesn't state specific opening hours (not published anywhere in this codebase to begin with) — points to Google/a phone call instead of guessing, since a wrong published hour is worse than no hour at all.
- Catering page now also covers Private Events &mdash; booking Ohana's own space for a large party, distinct from off-site catering
- Legacy `.html` URL redirects preserved for SEO
- HTTPS + persistent storage (Azure Files-backed menu data and photos)

</details>

<details>
<summary><strong>Menu experience</strong></summary>

- Search box + allergen/dietary tag filter chips (`server/Public/menu-section.js`)
- Photo lightbox + per-item detail modal with a photo gallery (multiple photos per item, rotates in Google Places photos where matched)
- Daily specials / featured-item toggle, surfaced on the homepage
- Per-item sold-out ("86'd") toggle — item stays visible on the public menu, grayed out with a "Sold Out Today" badge, instead of disappearing or requiring deletion
- Staff editor (`/edit.html`) — prices, descriptions, multi-photo galleries (manual upload or pick from Google Places), tags, featured toggle, sold-out toggle. Requires login (any employee); saves directly to the live site.
- The editor covers all 24 categories across Food/Sushi/Drinks/Happy Hour on one long page — a jump-nav at the top links straight to each section (Happy Hour is last, after ~170 other items, easy to miss without it), and a "Today's specials" panel lists every currently-featured item with a click-to-jump link, so finding/changing daily specials doesn't mean scrolling the whole menu looking for checked boxes.
- Every menu item now has a stable id (auto-migrated on first load for items saved before this existed) plus a "Happy Hour" flag alongside the existing featured/sold-out toggles — editable from either the bulk editor or the new single-item editor below.
- `/edit-item.html?id=...` — a focused single-item editor (photos, price, description, tags, featured/sold-out/Happy-Hour toggles, delete) reached by clicking a small "Edit" link that now appears next to every item on the public menu pages (`/menu`, `/sushi`, `/drinks`, `/happy-hour`) whenever a staff member is logged in — invisible to everyone else. The original bulk editor at `/edit.html` (edit many prices, then one Save) still works exactly as before; this is an additional, faster path for touching one item at a time, e.g. from an analytics report link.
- The "Staff: edit menu →" link on `/menu`, `/sushi`, `/drinks`, and `/happy-hour` is hidden by default and only reveals itself (via `/api/auth/me`) if you're currently logged in as staff — anonymous visitors never see it.
- A "Staff ▾" dropdown appears in the main site header (every public page, injected by `nav.js`) whenever a staff member is logged in — the same links as the `.staff-tools-nav` on every admin page (Menu Editor, Table Orders, Loyalty, Waitlist, Events, Table Cards, Analytics, Staff Rewards, Manage Users, My Account), just also reachable from the customer-facing site without knowing a direct URL.
- Both editors now return to `/menu` once you're done, instead of leaving you stranded on the edit form: saving on `/edit.html` or `/edit-item.html` shows a brief "Saved!" message, then redirects to `/menu` (where the per-item Edit links are right there if something else needs a touch-up). `/edit.html` also has a **Cancel** button next to Save that returns to `/menu` immediately without saving; `/edit-item.html`'s "← Back to Menu" link does the same.

</details>

<details>
<summary><strong>Loyalty & engagement</strong></summary>

- Digital sushi punch card (`/rewards` + `/loyalty-admin.html`) — phone-number identity, 1 punch per sushi order,
  10 punches = free roll. Photo/social shares are staff-reviewed and worth 1/10 of a punch each (10 approved shares = 1 punch), capped at the first 2 approved shares per calendar day per phone number — extra shares that day can still be submitted and approved, they just don't add points, so posting many photos of one meal doesn't multiply the reward.
- Events & specials calendar (`/events-admin.html` + public display on `/local`)
- Real floor plan, digitized from the POS's own table map (2026-07-28): 43 tables/seats across the dining room (`24`&ndash;`49`), bar (rail seats `R1`&ndash;`R6`, bar tables `B1`&ndash;`B9`), sushi bar (`60`&ndash;`73`), and deck (`80`&ndash;`87`) — see `TableMap.swift` (`GET /api/table-map`, public) for the roster; positions are percentages of each section's canvas, so edit the coordinates there directly if the real layout ever changes.
- Printable QR-code table tents (`/table-card.html`) — one per real table/seat, each QR unique to its spot and encoding `/scan?table=<id>`. `/scan` checks the current day/time (Pacific) and sends the guest straight to `/happy-hour` during Happy Hour (Mon&ndash;Fri, 3&ndash;6pm) or `/menu` otherwise, carrying the table id along. Happy Hour's page carries a clear "See the Full Menu" link back out, since a scan-in visitor may not want to hunt for the section tabs. **Currently encoded against the live Azure hostname** (`ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io`) so the printed/QR codes are actually scannable for testing right now — swap back to `ohanasushigrill.com` (the restaurant's real domain) once DNS is pointed at this site and testing is done, by re-running the QR generation with that base URL.
- Table-side ordering, with a real lifecycle — once a guest has scanned a table's QR code, every menu item on `/menu`, `/sushi`, `/drinks`, and `/happy-hour` shows an "Order" button. Tapping it doesn't touch ChowNow or take payment (yet — this is designed to plug into a real order-entry system, or become one, later). It moves through three stages: **pending** (just tapped) → **entered** (staff checked with the table and actually entered it into the order system — it drops off the "Needs Entry" queue at this point) → **delivered** (confirmed by staff on `/table-orders-admin.html` *or* by the guest themselves, whose "Order" button becomes "Mark Received"). Full order-to-delivery timestamps are kept for 90 days, which is what powers the prep-time estimates and analytics KPIs below.
- Live floor map on `/table-orders-admin.html` — the real layout above, rendered section-by-section (Dining/Bar/Sushi/Deck tabs) with each table flashing gold the instant a guest taps "Order" there, then pink once staff confirm it's entered and it's awaiting delivery. Polls the same 15-second interval as the existing list queues, so both views always agree. Respects `prefers-reduced-motion` (a solid highlight instead of a flashing one).
- A new order in a section you're not currently viewing flashes that section's *tab* instead of silently waiting in a hidden tab. The site-wide "N table orders" alert (shown to any logged-in staff member, not just this page) links straight to `/table-orders-admin.html?section=<section>` for whichever table has waited longest — oldest new order first, falling back to the oldest one awaiting delivery — instead of always landing on Dining.
- Once an order is confirmed entered, its table shows a solid purple "Processing" color on the floor map — distinct from the gold "needs entry" flash and the pink "awaiting delivery" flash — so it's visually obvious a table has an order being cooked, even before it's plausibly ready.
- The "awaiting delivery" flash (and its spoken alert, below) doesn't start the instant an order is entered — that's before the kitchen could plausibly have it ready. It waits until whichever is greater: the average prep time of the single slowest dish still cooking at that table, or half the combined average prep time of everything cooking there (computed client-side from each order's own `enteredAt`/`estimatedReadyAt`, no extra API call).
- Spoken order alerts — logged-in staff hear "New order, table 84, deck" the moment a new table order appears, and "Order up, table 84, deck" once that table crosses the prep-time threshold above — via the browser's built-in text-to-speech, using the same 15-second poll and table-map lookup as the visual alert. Works site-wide (every page, including every staff admin page, not just `/table-orders-admin.html`) since it's driven from the shared `nav.js`. Best-effort only (some browsers won't play any audio until the page has had a click), so it's a supplement to the visual/tab alerts, not a replacement. A small "🔔 Alerts on"/"🔕 Alerts muted" toggle (top-right, next to the alert badges) lets a staff member mute just the spoken alerts on their own device — the visual badge and floor map still work while muted.
- Add-ons & upgrades on individual menu items (e.g. "Add Katsu +$6", "Yosh Size +$25.20") — staff define these per item from `/edit-item.html`, and a guest ordering that item from their table sees them as checkboxes right on the menu, with the selection carried through to the staff order queue. Not priced/charged automatically (this still isn't a payment system) — just makes sure the request actually reaches staff instead of getting lost.
- Checking an add-on updates that item's displayed price live, e.g. checking "Yosh Size" on a $28 Loco Moco shows "$53.20 ($28.00 + Yosh Size $25.20)" — so a guest sees the real total, and what's driving it, before they order. Unchecking everything reverts to the plain base price. Wraps onto multiple lines on a narrow screen instead of overflowing — checking every add-on on a dish at once (a long breakdown) stays fully on-screen at 390px wide.
- Shared Additions Catalog (`GET`/`PUT /api/additions-catalog`, staff-only) — every add-on ever typed into `/edit-item.html` is saved to one sitewide list, so staff adding the same addition to another item (e.g. "Add Bacon") can pick it from a dropdown instead of retyping the name and price from scratch. Picking an entry just pre-fills the existing name/price fields — still editable before confirming — since some add-ons (like "Yosh Size") legitimately cost a different amount per dish.
- "Scan for common add-ons" button on `/edit.html` (`POST /api/menu/seed-additions`) — one click seeds the additions catalog and applies matching modifiers to every item whose own description already spells out an upcharge (e.g. "Add bacon +$5.50", "YOSH size: $53.20"), curated from a full sweep of the menu rather than a live text parser. Safe to click more than once — anything already present (matched case-insensitively by name) is left untouched, so it only ever adds what's missing.
- Staff rewards (`/staff-rewards-admin.html`, admin only) — a points card (same redeem-when-you-have-enough mechanic as the customer loyalty card) earned by keeping the site itself up to date, at a deliberate **100 points ≈ $1** ratio (chosen over a 1:1 ratio so everyday actions accumulate in satisfying triple digits rather than single digits). Points are valued per category, scaled to real effort/business value: marking a special or updating a price = 100 points (trivial data entry), adding a photo or a new event = 200 points (real content-creation effort), a social media post = 300 points (the most effort — shoot, write, post — and the most marketing value). Editing a single menu item (via `/edit-item.html` or the inline "Edit" link — not the bulk `/edit.html` save, since that endpoint is also used by one-off migration scripts and shouldn't rack up points for those) auto-awards whichever categories actually changed, all independently, batched into one write per edit rather than one per category. Adding a new event on `/events-admin.html` auto-awards its points too. A staff member can log their own "other" activity right from `/account.html` for instant credit; a social media post instead requires a link and goes to a **Social Media Requests** queue on `/staff-rewards-admin.html` for admin approval (mirroring the existing customer loyalty bonus-request pattern) — no points land until approved, and approval is exempt from the daily cap since a human has verified it. Every other auto-award/self-report shares one cap of 1000 points/staff/day, so neither repeatedly toggling a field nor repeatedly self-logging can farm unlimited points. An admin can still grant any category by hand, exempt from the daily cap.
  - **Reward Catalog** — points are redeemed against an editable catalog (`GET`/`PUT /api/staff-rewards/catalog`) rather than one fixed threshold: the default seeds a Classic Ohana Roll/Happy Hour appetizer at 1000 points (priced against the real Happy Hour menu — those two lists average $8.90 and $11.00 respectively, ~$9.83 combined, as of 2026-07-28) plus **Ohana Hat**/**Ohana T-Shirt** placeholders with no point cost yet, pending real swag pricing. An admin edits names/costs (or adds/removes items) directly from the catalog panel; a placeholder can't be redeemed until it has a real cost. The account.html progress bar targets whichever catalog item is currently cheapest, so it always reflects something actually redeemable.
  - Pre-2026-07-28 data (flat 1-point-per-action, no catalog) decodes forward compatibly — no migration needed.
- Site-wide feedback widget — a small "Feedback" tab on every public page (no login needed) lets a guest rate and comment on the website, food, or service. If a customer or staff member is logged in when they submit, their account email is attached automatically server-side (overriding whatever, if anything, is typed into the optional email field) so a reply doesn't depend on them having typed it correctly. Logged-in staff see a floating "N new feedback" indicator the same way they do for table orders, a full report (with average rating) lives on `/analytics.html`, and a plain-text summary of the previous day's submissions goes out to admin staff each morning (once an email provider is configured — see the email caveat below).
- Prep-time estimation — once an order is marked "entered," a "should be ready around..." time is estimated and shown to staff. It prefers a dish's own real average (once at least 3 completed orders exist for it) over a rough per-section guess (drinks: 3 min, sushi/food: 12 min, Happy Hour: 7 min), and adjusts either one upward when more tables are currently occupied than the staff-on-duty count (set from `/table-orders-admin.html`) can comfortably keep up with. A small floating "N table orders (X new, Y ready)" indicator shows up anywhere on the site for a logged-in staff member — not just on the admin page — combining orders that still need entering with ones that are past their estimated ready time.
- Google/Yelp review buttons link directly to Ohana's actual listings (not a generic search)
- Embedded map on the Contact page (no API key/billing needed — uses the classic `maps.google.com/maps?...&output=embed` URL)
- `/gallery` — aggregates all distinct menu item photos and the rotating Google Places photos into one browsable page
- Call/text-to-reserve CTA on the homepage and Contact page (deliberately not a paid platform like OpenTable/Resy — see [Known gaps](#known-gaps--not-yet-implemented))
- Persistent Call / Order / Directions bar pinned to the bottom of the screen on mobile (every public page) — the "Order Online" button previously lived inside the collapsed hamburger menu, taking two taps on the device most visitors actually use
- Text-based waitlist (`/waitlist` + `/waitlist-admin.html`) — not a reservation, just lets a walk-in put their name in before arriving. Staff's "Text they're ready" button opens the staff member's own phone's messaging app with the number and a ready-made message pre-filled (no SMS gateway/automated texting — nothing is sent without a staff member hitting send themselves). Entries older than 4 hours drop off the live queue automatically.
- `/specials` — a stable page for social bio links / post links, so a marketing link doesn't have to point at the homepage or bounce between three different pages

</details>

<details>
<summary><strong>Staff accounts</strong></summary>

- Named username/password logins (bcrypt-hashed) with two roles: `admin` and `employee`
- First-run bootstrap creates the first admin when zero accounts exist, then permanently disables itself
- Admins manage the roster (`/manage-users.html`, `/create-account.html`): create accounts, change roles, force-reset a forgotten password, deactivate/reactivate an account
- Deactivation takes effect immediately — even an already-open session gets logged out, not just blocked on the next login attempt. An admin can't deactivate their own account.
- Anyone can change their own password (`/change-password.html`); new/reset accounts must change their password on next login
- Real audit trail by design — actions are tied to a named account, not a shared PIN
- Optional email per staff account, set from `/account.html` — not required, and not currently used for anything but sign-in (no notifications are actually sent yet). Once set, it works as an alternate login identifier alongside the username
- Log in with either your username or your email (`/login`) — same password, whichever's easier to remember
- Admins can fix a staff account's display name (`/manage-users.html`, `POST /api/users/:id/display-name`) — there was previously no way to correct a typo'd name at all, not even for the account owner. Trims whitespace, rejects a blank name.
- **Fixed a real production bug**: every page under `/staff/*.html` referenced its stylesheet and scripts with a relative `./` path (e.g. `./staff-auth.js`), which resolves to `/staff/staff-auth.js` — but every one of those files actually lives at the site root (`/staff-auth.js`). That 404s in a real browser, meaning **no staff page had ever actually loaded its CSS or JS in production** (unstyled, and none of the login form/menu editor/admin dashboards were interactive) since the single-item menu editor was introduced. Verification up to this point had only ever hit the JSON APIs directly, never loaded these pages in an actual browser, so it went unnoticed. Fixed by changing every reference to `../` across all 13 `/staff/*.html` files.

</details>

<details>
<summary><strong>Customer accounts</strong></summary>

- Separate from staff accounts — email/password identity only, no `admin`/`employee` role, no order history yet
- Self-service registration (`/signup`), login (`/account-login`), password change and reset (`/forgot-password.html` → `/reset-password.html`, 1-hour expiring token)
- The "Log In" link in the main site nav (every public page, via `nav.js`) automatically becomes "Log Out" when a customer or staff session is already active — checks `/api/customer/me` then `/api/auth/me` client-side and swaps the link's text/behavior, no page-specific code needed
- Email verification link on signup — **not actually delivered yet** (see gaps below), logged server-side instead
- Self-service account deactivation (`/my-account.html`) — immediately ends the session and blocks future login (password or OAuth)
- Birthday Club (`/my-account.html`) — optional month+day only (no birth year ever stored). Staff see who has a birthday in the next 7 days from `/loyalty-admin.html`, so a server can proactively treat a regular — deliberately a staff-visible list rather than an automated discount, since this account system has no connection to a checkout/POS to apply one automatically.
- Google sign-in now captures a profile photo (`/my-account.html` shows it) alongside the email it already captured — backfilled automatically on next login for any account that linked Google before this existed, without overwriting a photo that's already on file. Apple never supplies a photo, so Apple-only accounts simply don't have one.
- Rewards Card linking (`/my-account.html`) — a signed-in customer can link their phone number to their existing phone-based sushi punch card and see live punch/redemption status right on their account page, instead of having to look it up separately on `/rewards` every time.
- Customer profile page now summarizes everything on file in one place — photo, email/verified status, birthday, linked rewards phone, sign-in methods, and an Order History panel (table orders placed while signed in, with status and timestamp). Orders placed without being logged in aren't tied to any account, so they won't show up here — ordering never requires signing in.
- Staff accounts gained the same profile fields customers have: an optional birthday and phone number (both self-service from `/account.html`), and a profile photo *and* email captured from Google when linked — same backfill-on-login behavior as customer accounts (an account that linked Google before this existed gets both filled in on its next login, never overwriting one already on file), and now actually shown on the profile page instead of only living in the separate email-edit form.

</details>

<details>
<summary><strong>OAuth sign-in (Google + Apple + Facebook)</strong></summary>

- Customers: "Continue with Google" on `/signup` and `/account-login` — self-serve, first sign-in creates an account (or links to an existing email/password account with a matching verified email)
- Staff: link-only, not self-serve — an employee must already have a username/password account, log in, then link Google from `/account.html`. Only after linking does "Sign in with Google" work on `/login`. (Prevents anyone with a Google account from getting staff access.)
- `/account-login` (the customer-facing "Log In" linked from the main nav) is the one login page most visitors reach; a Customer/Staff tab pair at the top switches to `/login`, the separate staff login page (username-or-email + password, or linked Google)
- Google and Facebook sign-in each use a single shared callback URL (`/auth/google/callback`, `/auth/facebook/callback`) for both customers and staff — which account type it's handling is encoded in OAuth `state`, not the URL — so only one redirect URI needs registering per provider. Both flows land on `/logged-in` afterward, which routes staff to `/edit.html` and customers to `/my-account.html`.
- Apple's and Facebook's buttons are hidden site-wide for now (`hidden` attribute + a CSS rule, easy to re-enable per provider) until their credentials are actually set up — see [`docs/oauth-setup.md`](docs/oauth-setup.md)
- **Only Google is actually configured so far** — see [`docs/oauth-setup.md`](docs/oauth-setup.md). The Google button is live in the UI but returns a clear 503 until real credentials are set; Apple and Facebook are fully built underneath but hidden until their credentials exist. X/Twitter and Instagram were deliberately not built — X's API pricing for third-party login is unclear/likely paid, and Instagram isn't designed as a general-purpose login provider.

</details>

<details>
<summary><strong>SEO & technical</strong></summary>

- Per-page Open Graph / Twitter Card tags
- schema.org `Restaurant` JSON-LD on the homepage
- Live Google reviews embedded on the homepage (`/api/place-reviews`) — author, star rating, and text pulled from the Google Place Details API and cached for 6 hours, reusing the same `GOOGLE_PLACES_API_KEY`/`GOOGLE_PLACE_ID` already configured for the photo carousel (no extra credential, no extra API quota — photos and reviews share one cached call). Falls back to just the existing "Read Reviews on Google/Yelp" link buttons if the widget has nothing to show.
- `sitemap.xml` and `robots.txt`
- Cache-Control revalidation on every response (avoids stale-cache bugs after a deploy)
- Accessibility pass — fixed real WCAG AA contrast failures (brand pink/gold read ~3:1 as text on light backgrounds; added darker `--pink-text`/`--gold-text` variants used only for text, keeping the brighter originals for backgrounds/borders), a focus state that was fully removed without a visible replacement, and a heading-hierarchy skip on the Contact page. Alt text was already solid site-wide.
- Automated test suite (`server/Tests/AppTests`, 203 tests) — loyalty punch/redeem math, waitlist and table-order lifecycle behavior (including prep-time estimation and delivery-stats aggregation), analytics aggregation (including OS/browser/device-model user-agent parsing), single-item menu CRUD, staff and customer auth (including deactivation, OAuth linking/photo- and email-backfill for both account types, Facebook as an independent provider alongside Google/Apple, and rewards-card linking), menu backward-compat decoding, the Happy Hour time-window/QR-redirect logic (including table-id passthrough), and route-level permission boundaries. Run with `swift test` from `server/`.
- Self-hosted analytics (`/analytics.html`, admin only) — pageview counts by page and by day, device type (mobile/tablet/desktop), operating system (iPhone/iPad/Android/macOS/Windows/Linux), browser (Safari/Chrome/Firefox/Edge/Samsung Internet/Opera), best-effort Android hardware model (e.g. "Pixel 8" — parsed only when a browser's user-agent happens to include it; iOS never exposes a specific model, so there's no equivalent list for Apple devices), average time on page, and most-viewed menu items (detail-popup opens — a proxy for interest, not a sales figure, since this site has no access to real order data from ChowNow). No cookies, no third-party tracking script, no per-visitor identity anywhere. Bounded to 120 days of aggregated data.
- `/analytics.html` landing view is a grid of compact summary cards (one per section — peak day, most-viewed page/item, device/OS/browser split, sitewide missing-price/photo counts, etc.), not a long single-column scroll. Clicking a card — or a notification link like `/analytics.html?section=feedback` — expands just that section into a full detail view, so the target always lands exactly where intended (no other section's async-loaded content is above it to shift the page after the click).
- Table-order wait/prep/delivery time KPIs on `/analytics.html`, computed from real completed orders: wait (placed → entered), prep (entered → delivered), and total (placed → delivered), both overall and broken out per menu item.
- Estimated Table Occupancy on `/analytics.html` (`GET /api/table-orders/occupancy-stats`, staff-only) — a full seating-to-departure table-turnover estimate, since nothing tracks when a party actually leaves so it can't be measured directly. Orders at the same table are grouped into "dining sessions" (a gap of over 90 minutes between orders means a new party sat down); each completed session combines its own real wait+prep time (from the KPI above) with an eating-time estimate from what was actually ordered (`DiningTimeEstimator.swift` — per-section baselines combined the same way overlapping prep times are: the single slowest dish, or half the combined total, whichever is greater) and a fixed allowance for deciding what to order beforehand and for conversation/paying/leaving afterward, sized so the total lands within the 60–90 minute range industry research reports for casual full-service dining. Falls back to a clearly-labeled generic single-entree example until at least one dining session has actually completed.
- "Popular Right Now" on `/specials` — the top menu items by real view count over the last 30 days, computed fresh on every page load (`/api/analytics/popular-items`), automatically skipping anything sold out or removed from the menu. Sits alongside, not instead of, the staff-curated "Today's Specials" section — nothing here overwrites what staff manually feature.
- "Menu Items Missing a Price" / "Menu Items Missing a Photo" reports on `/analytics.html`, scanning the entire live menu (including Happy Hour) — grouped by category with a count at the top of each group, and each row links straight to that item's `/edit-item.html` page to fix it on the spot.
- Uploaded photos (menu editor, customer bonus-claim photos) are auto-resized (1600px long-edge cap) and re-compressed via ImageMagick, run off the event loop so it doesn't stall other requests. Fails closed — if optimization fails for any reason, the original upload is kept as-is rather than blocking the upload.
- `DELETE /api/uploads/:filename` — removes an uploaded photo file, requires login. Refuses (409) if any menu item still references it, so callers must repoint every referencing item first. Uploaded filenames are random UUIDs, so nothing else can guess a path to delete; login is still required since this is a real destructive action.

</details>

<details>
<summary><strong>Visual design refresh</strong></summary>

- New palette: neon pink (from the actual storefront sign) paired with the University of Washington's official purple as the secondary brand color — see `docs/visual-design-direction.md` for the full rationale
- Bold display face (Bungee) used sparingly for page `h1`s and the header logotype; body/UI copy moved from Georgia serif to a warmer, more modern sans (Nunito Sans)
- A subtle wave-shaped divider on every hero banner, a recurring nod to the restaurant's waterfront/tiki setting
- New color pairs re-verified against WCAG AA (4.5:1) for text usage, same methodology as the earlier accessibility pass

</details>

## Known gaps / not yet implemented

Pulled from `docs/feature-roadmap.md`'s original audit, updated for what's
actually shipped as of this README. Not in priority order.

**Trust & findability**
- Yelp reviews are linked, not embedded — a real embed needs a Yelp Fusion API key (free, separate signup at yelp.com/developers) that isn't configured. Google reviews now embed live on the homepage (see "SEO & technical" below) using the same key already set up for photos.

**Discovery & conversion**
- Self-serve/live reservation booking — deliberately not built. Evaluated OpenTable ($149–499/mo + $1–1.50/cover on network bookings), Resy ($0–399/mo flat, no per-cover fee on direct bookings), and Tock (merging into Resy); none are worth the cost against Ohana's walk-in-friendly positioning without a concrete signal (e.g. regularly turning away walk-in groups) that it's needed. Shipped the free call/text CTA instead — revisit if that signal shows up.
- Online gift card purchase (still "call us and we'll mail one")

**Engagement & retention**
- Email/SMS signup for specials
- Order history and "reorder your last meal" — still nothing here since this site has no real order data (ordering happens through ChowNow); customer accounts can now link their phone-based punch card (see "Accounts" above), but that's status, not history.
- Native delivery radius checking (delivery relies entirely on ChowNow's partners)

**Technical**
- Uptime/error monitoring/alerting — setup steps ready in [`docs/uptime-monitoring.md`](docs/uptime-monitoring.md), just needs a UptimeRobot account (can't be created on your behalf)
- Formal Lighthouse performance pass — no Node.js in this dev environment to run the actual CLI. Manually reviewed the usual Lighthouse-audited factors (image sizing/lazy-loading, render-blocking resources, cache headers) and found nothing actionable beyond what's already in place; a real run would still be worth doing from a machine with Node/Chrome.

**Admin & operations**
- Password reset is admin-only for staff (an admin resets it for you) — no self-service "forgot password" email flow for staff (customers have one; see the email caveat below for why it's not fully live yet)
- Staff accounts can be deactivated/reactivated (see above), but not deleted outright. Customers can self-deactivate their own account (`/my-account.html`), but reactivation isn't self-service (contact the restaurant) — and there's still no staff-facing UI to manage/browse customer accounts.
- ChowNow menu photo import — investigated, blocked by Cloudflare bot protection on ChowNow's API; not pursued further (see git history for details)

**Known deliberate tradeoffs (not bugs)**
- **No real email delivery yet.** `EmailSenderFactory` (`server/Sources/App/EmailSender.swift`) currently returns a placeholder that logs the email server-side instead of sending it — so customer email verification and password-reset links don't reach anyone's inbox right now. Swapping in a real provider (Resend, SendGrid, etc. — still deciding, was going to be GoDaddy but that isn't a transactional-email API provider in the usual sense) is a single-file change once an API key is available. Until then, self-service password reset for customers is not actually functional end-to-end.
- Sessions use Vapor's in-memory driver — a deploy or restart logs everyone out. Fine for a ~9-person staff team and low-stakes customer accounts; would need a persistent session store (e.g. file- or Redis-backed) to survive restarts.
- Every new/reset staff account gets a caller-chosen temporary password and must change it on next login — there's no forced password-strength policy beyond that.
- Bonus punch claims (photo/social shares) are staff-reviewed, not auto-verified — there's no reliable API to check a social tag automatically.
- Google Places photos are capped at 10 per API call (a hard Google limit, not a bug) and matched to menu items manually.
- Sign in with Apple needs a client-secret JWT that's re-signed on every token exchange (Apple doesn't accept a static secret like Google does) — implemented with `swift-crypto`'s `P256.Signing` rather than pulling in a full JWT library, since that's the only cryptographic operation needed.

## Setting up Google/Apple/Facebook Sign-In

All three are built underneath (buttons on `/signup`, `/account-login`,
`/login`, `/account.html`) but Apple and Facebook stay hidden in the UI, and
Google returns a `503`, until real credentials are set as Container App
secrets/env vars. Full step-by-step instructions for all three providers,
including exact links and where to paste each value, are in
[`docs/oauth-setup.md`](docs/oauth-setup.md).

## Local development

```bash
cd server
# GCC version workaround needed on this dev box (Swift picks up an incomplete
# GCC 12 over the fully-installed GCC 11 otherwise):
export CPLUS_INCLUDE_PATH="/usr/include/c++/11:/usr/include/x86_64-linux-gnu/c++/11"
export LIBRARY_PATH="/usr/lib/gcc/x86_64-linux-gnu/11"

swift build
DATA_DIR=./Data swift run App

# Run the test suite:
swift test
```

Then open `http://localhost:8080`. Without `GOOGLE_PLACES_API_KEY`/`GOOGLE_PLACE_ID`
set, the Google Photos carousel and picker will just come back empty.

Visiting `/login` on a fresh `DATA_DIR` (no `users.json` yet) shows a one-time
setup form instead of the login form — use it to create your first local admin
account, since staff pages all require login now.

Customer verification and password-reset links aren't emailed (see the email
caveat above) — after registering at `/signup` or requesting a reset at
`/forgot-password.html`, grab the link from the server's console output
(`EMAIL (not sent — no provider configured) ...`) to complete the flow locally.

## Other docs in this repo

- `docs/feature-roadmap.md` — original feature audit and phased plan (predates most of what's now shipped; see the gaps list above for current state)
- `docs/visual-design-direction.md` — the palette/type direction used for the visual refresh
- `docs/oauth-setup.md` — step-by-step Google/Apple/Facebook Sign-In credential setup
- `docs/uptime-monitoring.md` — how to point UptimeRobot (free) at the existing `/healthz` endpoint
- `docs/page-inventory.md`, `docs/migration-plan.md`, `docs/ohana-project-plan.md` — early planning docs from the static-site-capture phase, kept for history
- `reference-site/` — the original Weebly site mirror this project was migrated from
