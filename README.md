# Ohana Belltown Website

[![Build and deploy](https://github.com/ProDataMan/Ohana_Belltown/actions/workflows/deploy-server.yml/badge.svg)](https://github.com/ProDataMan/Ohana_Belltown/actions/workflows/deploy-server.yml)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Vapor](https://img.shields.io/badge/Vapor-server-2ED0FF)
[![Live site](https://img.shields.io/badge/live%20site-ohanabelltown-ff2f8f)](https://www.ohanasushigrill.com)

A Swift/Vapor server powering [Ohana Belltown](https://www.ohanasushigrill.com)'s
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
[Payment Processing](#payment-processing-square) ·
[Google/Apple/Facebook Sign-In setup](#setting-up-googleapplefacebook-sign-in) ·
[Local development](#local-development) ·
[Suggestions for future development](#suggestions-for-future-development) ·
[Design/UX recommendations](#high-impact-designux-recommendations) ·
[Other docs](#other-docs-in-this-repo)

## Live site

- **Site:** https://www.ohanasushigrill.com
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
- **Auth:** Vapor's built-in `Bcrypt` (password hashing) and a custom file-backed session driver
  (`FileSessions`/`FileSessionsStore`, `server/Sources/App/FileSessions.swift`) — one JSON file per
  session under `<DATA_DIR>/sessions/`, so a deploy or restart no longer logs everyone out (replaces
  the original in-memory driver). Stale session files (30+ days untouched) are pruned daily.
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
| `GOOGLE_PLACES_API_KEY` | Server-side only — proxies Google Business photos/reviews and (new) Nearby Search for the Competitor Pricing restaurant picker. The same key covers all three; Nearby Search additionally needs the "Places API" enabled on whichever Google Cloud project the key belongs to. |
| `GOOGLE_PLACE_ID` | Ohana Belltown's Google Place ID |
| `ANTHROPIC_API_KEY` | Server-side only — powers AI menu-photo extraction on Competitor Pricing (Claude's vision API). Not set yet. **This is a separate credential from a claude.ai chat subscription** — get one with its own billing at [console.anthropic.com](https://console.anthropic.com) (API Keys page). Usage is pay-per-use (typically a fraction of a cent to a few cents per photo extracted), not a subscription. |
| `PUBLIC_BASE_URL` | The site's own public HTTPS origin, used to build OAuth redirect URIs. Defaults to the production URL above if unset — only needs overriding for local dev (`http://localhost:8080`). |
| `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` | Google Sign-In. Not set yet — see [`docs/oauth-setup.md`](docs/oauth-setup.md). |
| `APPLE_OAUTH_CLIENT_ID`, `APPLE_OAUTH_TEAM_ID`, `APPLE_OAUTH_KEY_ID`, `APPLE_OAUTH_PRIVATE_KEY` | Sign in with Apple. Not set yet — needs a paid Apple Developer Program enrollment first. See [`docs/oauth-setup.md`](docs/oauth-setup.md). |
| `FACEBOOK_OAUTH_APP_ID`, `FACEBOOK_OAUTH_APP_SECRET` | Facebook Login — free, no paid tier required. Not set yet — see [`docs/oauth-setup.md`](docs/oauth-setup.md). |
| `SQUARE_ACCESS_TOKEN` | Server-side only — powers real card checkout on Shop (`/shop`) and Gift Cards (`/gift-cards`), Square's Payment Links API. **Set, but currently the sandbox token** (2026-08-02) — swap for the production token (Developer Dashboard → Credentials → Production Access Token) when ready to take real payments. See [Payment Processing](#payment-processing-square). |
| `SQUARE_LOCATION_ID` | Which Square location Shop/Gift Card sales post to. **Set** (2026-08-02, sandbox test location) — find your real location's ID under Account & Settings → Business → Locations, or via Square's `GET /v2/locations` API. |
| `SQUARE_WEBHOOK_SIGNATURE_KEY` | Server-side only — verifies that `POST /api/swag/square-webhook` calls genuinely came from Square before marking a Shop/Gift Card order paid. **Set** (2026-08-02, sandbox webhook subscription) — created via a webhook subscription in the Square Developer Dashboard pointed at `<PUBLIC_BASE_URL>/api/swag/square-webhook`, subscribed to `payment.updated`. |
| `SQUARE_ENVIRONMENT` | **Set to `sandbox`** (2026-08-02) — requests go to `connect.squareupsandbox.com`, fake test cards only. Unset (or set to anything else) to hit production (`connect.squareup.com`) once the token above is swapped too. |
| `RESEND_API_KEY` | Server-side only — powers real delivery of customer email-verification and password-reset emails via [Resend](https://resend.com)'s REST API (`server/Sources/App/EmailSender.swift`). **Not set yet.** Until it is, emails are only logged server-side (`ConsoleEmailSender`) — see the email caveat below. Get a key at resend.com; the fast path (no domain verification) works immediately with the default `RESEND_FROM_ADDRESS`. |
| `RESEND_FROM_ADDRESS` | The `From:` address on outgoing email. Defaults to Resend's own `onboarding@resend.dev`, which works without verifying `ohanasushigrill.com`'s DNS. Set to a real `@ohanasushigrill.com` address once that domain is verified with Resend (needs DNS moved to a host that exposes TXT records — see "Suggestions for future development" below). |
| `TUYA_ACCESS_ID`, `TUYA_ACCESS_SECRET` | Server-side only — Tuya IoT Platform Cloud project credentials, powering the optional Feit/Tuya station-light table-order notifications (see "What's shipped" below). **Not set yet** — entirely dormant/no-op until both are set, same pattern as every other optional integration. |
| `TUYA_REGION` | Which Tuya data-center region to call (`us` default, or `us-e`/`eu`/`in`/`cn`) — must match wherever the Tuya Smart Life account/devices were actually registered. |
| `TUYA_DEVICE_ID_SERVER`, `TUYA_DEVICE_ID_KITCHEN`, `TUYA_DEVICE_ID_SUSHI`, `TUYA_DEVICE_ID_BAR` | Tuya device IDs for each physical bulb (server-station, kitchen, sushi bar, service bar). `TUYA_DEVICE_ID` also works as a single fallback for just the server-station bulb if that's all that's wired up initially. Any fixture with no device ID configured is simply skipped. |
| `TUYA_COLOUR_CODE` | Which Tuya DP (data point) code the bulbs expect for color — `colour_data` (default) or `colour_data_v2`, depending on the specific bulb model. Check the device's DP schema in the Tuya IoT Platform if colors come out wrong. |

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
| `/shop` | Public: buy Ohana merch (bandanas, hats, t-shirts) online via Square Checkout — real card payment |
| `/swag-admin.html` | Staff: manage the Shop product list (name, price, availability, photos), mark paid orders delivered. **Any logged-in employee.** |
| `/gift-cards` | Public: pay online for a physical Ohana gift card, $5&ndash;$500, via Square Checkout |
| `/gift-cards-admin.html` | Staff: see paid gift-card orders, activate the physical card, mark fulfilled. **Any logged-in employee.** |
| `/staff-rewards-admin.html` | Staff: points card for keeping the site up to date — award points, review social-media point requests, edit point values/reward catalog. **Admin only.** |
| `/competitor-pricing-admin.html` | Staff: find/add nearby competitor restaurants, upload photos of their menus, review the price comparison report. **Admin only.** |
| `/competitor-pricing-findings.html` | Staff: written summary of what the price comparison data means and what's worth acting on. **Admin only.** |
| `/help.html` | Staff: setup guides and reference notes (e.g. Tuya Cloud account setup for the table-order station lights), linked from the `.staff-tools-nav` on every admin page. **Any logged-in employee.** |
| `/signup`, `/account-login` | Customer registration and login (separate from staff accounts). `/account-login` links to `/login` for staff. |
| `/logged-in` | Shared post-login router — sends staff to `/edit.html` and customers to `/my-account.html`. Where Google Sign-In lands after a successful login. |
| `/my-account.html` | Customer's own account page — profile, password change |
| `/order-history` | Public: table order history for this browser (by device id), no login required |
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
- Photo lightbox + per-item detail modal with a photo gallery. Once an item has 2+ of its own photos, the bottom gallery shows only those (a real gallery for a dish with real photo coverage); below that, it falls back to rotating in Google Places' general restaurant photos as before, so a sparsely-photographed item still shows something.
- The item-detail modal now mirrors the menu list's ordering controls — add-on checkboxes (with the same live price breakdown) and an Add to Order/Mark Received button, so a guest can pick add-ons and add the item to their pending order without leaving the modal. Adding it there updates the same button on the menu list instantly (and vice versa), since both are just views over one shared pending-cart state. Successfully adding an item (not blocked by a missing required add-on/choice selection) closes the modal automatically, dropping the guest back on the menu page they were browsing rather than leaving it open over their selection.
- Daily specials / featured-item toggle, surfaced on the homepage
- Per-item sold-out ("86'd") toggle — item stays visible on the public menu, grayed out with a "Sold Out Today" badge, instead of disappearing or requiring deletion
- Staff editor (`/edit.html`) — prices, descriptions, multi-photo galleries (manual upload or pick from Google Places), tags, featured toggle, sold-out toggle. Requires login (any employee); saves directly to the live site.
- The editor covers all 24 categories across Food/Sushi/Drinks/Happy Hour on one long page — a jump-nav at the top links straight to each section (Happy Hour is last, after ~170 other items, easy to miss without it), and a "Today's specials" panel lists every currently-featured item with a click-to-jump link, so finding/changing daily specials doesn't mean scrolling the whole menu looking for checked boxes.
- Every menu item now has a stable id (auto-migrated on first load for items saved before this existed) plus a "Happy Hour" flag alongside the existing featured/sold-out toggles — editable from either the bulk editor or the new single-item editor below.
- `/edit-item.html?id=...` — a focused single-item editor (photos, price, description, tags, featured/sold-out/Happy-Hour toggles, delete) reached by clicking a small "Edit" link that now appears next to every item on the public menu pages (`/menu`, `/sushi`, `/drinks`, `/happy-hour`) whenever a staff member is logged in — invisible to everyone else. The original bulk editor at `/edit.html` (edit many prices, then one Save) still works exactly as before; this is an additional, faster path for touching one item at a time, e.g. from an analytics report link.
- The "Staff: edit menu →" link on `/menu`, `/sushi`, `/drinks`, and `/happy-hour` is hidden by default and only reveals itself (via `/api/auth/me`) if you're currently logged in as staff — anonymous visitors never see it.
- Clicking any photo thumbnail in either editor's gallery (`/edit.html` or `/edit-item.html`) opens a preview with resolution, file size, date added, and who added it (`GET /api/uploads/:filename/info`, staff-only) — resolution/size are read live off the file itself, date/uploader come from a new `UploadMetadataStore` that `POST /api/upload` writes to going forward. Since that upload endpoint is also used by the anonymous customer loyalty photo-share flow (`/rewards`), "added by" is best-effort (whoever's logged in at upload time, blank for a guest) rather than a hard requirement — and photos uploaded before this store existed simply show "Unknown (uploaded before tracking was added)" instead of a guess.
- A "Staff ▾" dropdown appears in the main site header (every public page, injected by `nav.js`) whenever a staff member is logged in — the same links as the `.staff-tools-nav` on every admin page (Menu Editor, Table Orders, Loyalty, Waitlist, Events, Table Cards, Analytics, Staff Rewards, Competitor Pricing, Swag, Gift Cards, Manage Users, My Account, Help), just also reachable from the customer-facing site without knowing a direct URL.
- **Fixed**: the "Menu ▾"/"Staff ▾" nav dropdowns could get stuck open on iPad and not close on a second tap. The CSS also opened the menu on `:hover`, and a tap on a touchscreen leaves a synthetic `:hover` state stuck active — OR'd with that rule, the menu stayed visually open even after the JS toggle removed its `.open` class. Hover-to-open is now scoped to `@media (hover: hover) and (pointer: fine)` (real mouse/trackpad only), and a tap anywhere outside an open dropdown now closes it as a second safety net.
- Both editors now return to `/menu` once you're done, instead of leaving you stranded on the edit form: saving on `/edit.html` or `/edit-item.html` shows a brief "Saved!" message, then redirects to `/menu` (where the per-item Edit links are right there if something else needs a touch-up). Both also have a **Cancel** button next to Save that returns to `/menu` immediately without saving.
- Prices are hidden site-wide (`/menu`, `/sushi`, `/drinks`, `/happy-hour`, `/specials`, and the homepage's featured-items widget — plus the page's schema.org structured data, so they don't leak into search results either) until a table's QR code has actually been scanned this session (Yosh's call). A logged-in staff member still sees prices everywhere regardless, so editing/previewing your own changes on `/menu` still works without needing to scan anything.

</details>

<details>
<summary><strong>Loyalty & engagement</strong></summary>

- **Fixed**: the "Choose a photo" / "Link to your post" fields on the `/rewards` bonus-share form (and the matching "Link to your post" field on staff `/account.html`'s Log Activity form) were both visible at all times regardless of which radio button/category was selected — a global `label { display: flex }` CSS rule was silently overriding the JS toggling each field's `hidden` attribute, since an author-stylesheet rule always beats the browser's own `[hidden]` rule unless explicitly re-declared. Added a `label[hidden] { display: none; }` override so the fields now correctly show/hide with the selection everywhere on the site, not just these two spots.
- Digital sushi punch card (`/rewards` + `/loyalty-admin.html`) — phone-number identity, 1 punch per sushi order,
  10 punches = free roll. Photo/social shares are staff-reviewed and worth 1/10 of a punch each (10 approved shares = 1 punch), capped at the first 2 approved shares per calendar day per phone number — extra shares that day can still be submitted and approved, they just don't add points, so posting many photos of one meal doesn't multiply the reward. A photo share must be tagged to a menu item (a `<datalist>`-powered search field, since there are ~250 items — required for a photo, optional for a social tag since a social post isn't always about one specific dish) — approving a photo claim (`/loyalty-admin.html`) publishes that photo straight into the linked dish's own gallery (`MenuItem.images`, best-effort — a deleted/renamed item just skips this without blocking the punch award), so a good customer photo can end up on the public menu without staff ever having to re-upload it themselves.
- Events & specials calendar (`/events-admin.html` + public display on `/local`)
- Real floor plan, digitized from the POS's own table map (2026-07-28): 43 tables/seats across the dining room (`24`&ndash;`49`), bar (rail seats `R1`&ndash;`R6`, bar tables `B1`&ndash;`B9`), sushi bar (`60`&ndash;`73`), and deck (`80`&ndash;`87`) — see `TableMap.swift` (`GET /api/table-map`, public) for the roster; positions are percentages of each section's canvas, so edit the coordinates there directly if the real layout ever changes.
- Printable QR-code table tents (`/table-card.html`) — one per real table/seat, each QR unique to its spot and encoding `/scan?table=<id>`. `/scan` checks the current day/time (Pacific) and sends the guest straight to `/happy-hour` during Happy Hour (Mon&ndash;Fri, 3&ndash;6pm) or `/menu` otherwise, carrying the table id along. Happy Hour's page carries a clear "See the Full Menu" link back out, since a scan-in visitor may not want to hunt for the section tabs. Encoded against `www.ohanasushigrill.com` now that DNS points here — regenerated from the old Azure-hostname test batch once the domain went live. Card reads "Scan for Menu" on a dark card with the brand pink→purple gradient heading; `print-color-adjust: exact` (plus the `-webkit-`/unprefixed variants) is set on the print stylesheet so that background color and the gradient-clipped heading text actually survive printing instead of the browser silently stripping them to plain black-on-white, which is the default print behavior for anything relying on `background`/`background-clip` for its color.
- Two more QR cards print alongside the table ones, not tied to any table: **"While You Wait"** (front door/host stand) encodes `/scan?prices=1` — same Happy-Hour-aware redirect as a table scan, but shows real prices without a table id and deliberately does *not* unlock ordering/modifiers/choice groups (`getPriceViewFlag()` in `menu-section.js`, OR'd into the existing price-visibility checks only — the "Add to Order" button and modifier/choice-group UI stay gated on an actual `tableId`, since there'd be nowhere to deliver an order placed here). **"Shop Ohana Swag"** just encodes `/shop` directly, no special logic. Both QR images (`qr-view-menu.png`, `qr-shop.png`) live in `server/Public/images/`, generated the same ad hoc way as the table ones (a throwaway `python3` + `qrcode` script, not checked into the repo).
- Table-side ordering, with a real lifecycle — once a guest has scanned a table's QR code, every menu item on `/menu`, `/sushi`, `/drinks`, and `/happy-hour` shows an "Add to Order" button, plus an on-page hint ("Tap **Add to Order** on anything you'd like... then tap **Review & Send** once you're done picking") so the two-step flow is clear before they even try it. Tapping it doesn't touch ChowNow or take payment (yet — this is designed to plug into a real order-entry system, or become one, later); it just adds that dish to a pending order (tap again to remove it) that persists across menu pages, so a guest can pick a roll from `/sushi`, an entree from `/menu`, and a cocktail from `/drinks`, then send all of it together. A floating "🛒 Your Order (N)" button (bottom-left) opens a review screen listing everything picked so far, with a **Send Order** button and a note that a staff member will come confirm it — it hasn't been sent to the kitchen yet. Sending shows an on-screen confirmation ("Staff have been notified... someone will be by shortly to confirm it") and moves every item through the same three stages as before: **pending** (just sent) → **entered** (staff checked with the table and actually entered it into the order system — it drops off the "Needs Entry" queue at this point) → **delivered** (confirmed by staff on `/table-orders-admin.html` *or* by the guest themselves, whose button becomes "Mark Received"). A **Cancel** button sits next to Confirm Entered/Confirm Delivered on every row of `/table-orders-admin.html` (staff-only, `POST /api/table-orders/:id/cancel`) — for when a server actually talks to the table and they no longer want some or all of what they sent. Confirms first, then asks for an optional reason (kept for the record, not shown to the guest) before flipping the entry to a fourth status, **cancelled**, which drops it out of both queues immediately; refuses (409) once an item's already been delivered, since that's a different situation this isn't meant to handle. An order nobody ever acts on doesn't just silently vanish from the queues either — a scheduled sweep (`TableOrdersStore.cancelStaleOrders()`, every 30 minutes) auto-cancels anything past the same staleness window that already drops it off `needsEntry()`/`awaitingDelivery()` (4h unentered, 2h entered-not-delivered), stamping a system reason like "never delivered within 2h of being entered" — so staleness is always a real, auditable "cancelled" state, never an order left indefinitely "still open" with nothing anywhere resolving it. That matters beyond tidiness: if a future feature ever charges a table's card off an order's status, an order that's silently open forever is exactly the kind of thing that could get double-charged or charged for nothing. Full order-to-delivery timestamps are kept for 90 days, which is what powers the prep-time estimates and analytics KPIs below.
- Live floor map on `/table-orders-admin.html` — the real layout above, rendered section-by-section (Dining/Bar/Sushi/Deck tabs) with each table flashing gold the instant a guest taps "Order" there, then pink once staff confirm it's entered and it's awaiting delivery. Polls the same 15-second interval as the existing list queues, so both views always agree. Respects `prefers-reduced-motion` (a solid highlight instead of a flashing one).
- A new order in a section you're not currently viewing flashes that section's *tab* instead of silently waiting in a hidden tab. The site-wide "N table orders" alert (shown to any logged-in staff member, not just this page) links straight to `/table-orders-admin.html?section=<section>` for whichever table has waited longest — oldest new order first, falling back to the oldest one awaiting delivery — instead of always landing on Dining.
- Once an order is confirmed entered, its table shows a solid purple "Processing" color on the floor map — distinct from the gold "needs entry" flash and the pink "awaiting delivery" flash — so it's visually obvious a table has an order being cooked, even before it's plausibly ready.
- The "awaiting delivery" flash (and its spoken alert, below) doesn't start the instant an order is entered — that's before the kitchen could plausibly have it ready. It waits until whichever is greater: the average prep time of the single slowest dish still cooking at that table, or half the combined average prep time of everything cooking there (computed client-side from each order's own `enteredAt`/`estimatedReadyAt`, no extra API call).
- Spoken order alerts — logged-in staff hear "3 new items added to order at table 84, deck, waiting for 2 to be delivered" whenever a table has items not yet entered by a server (batched into one announcement per table, not one per item — the new-item count is items still `pending`, the waiting count is items already `entered` but not yet `delivered`; the "waiting for..." clause is omitted entirely when that count is 0), and "Order up, table 84, deck" once that table crosses the prep-time threshold above — via the browser's built-in text-to-speech, using the same 15-second poll and table-map lookup as the visual alert. Works site-wide (every page, including every staff admin page, not just `/table-orders-admin.html`) since it's driven from the shared `nav.js`. Best-effort only (some browsers won't play any audio until the page has had a click), so it's a supplement to the visual/tab alerts, not a replacement. A small "🔔 Alerts on"/"🔕 Alerts muted" toggle (top-right, next to the alert badges) lets a staff member mute just the spoken alerts on their own device — the visual badge and floor map still work while muted. Both alerts repeat roughly once a minute for as long as a table has any unaddressed items (still not entered, or still not delivered) rather than announcing once and going silent, so a reminder can't get missed in a busy room — each repeat re-reads the table's current counts, so it stays accurate if more items get added in between. On mobile (≤860px) the alert badges sit just below the header instead of at its very top-right corner, so they don't cover the hamburger menu button that lives in that same corner there.
- iOS reliability (every browser there — Chrome included — runs on Apple's WebKit engine, not its own): speech only plays at all if `speak()` has fired at least once inside a real tap, so the first tap anywhere on the page after logging in (or unmuting) silently "primes" it by speaking "Voice alerts on" — normal use of the site unlocks it without staff needing to know to do anything special. A [Screen Wake Lock](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API) is requested while alerts are on, since iOS suspends a locked/backgrounded tab's timers entirely (stopping the poll, not just the audio) — best-effort, silently no-ops on older browsers. Returning to the tab also clears a well-known iOS bug where the speech queue gets permanently stuck reporting "still speaking" after being backgrounded. None of this can fully replace a real push notification, though — if staff genuinely need an alert while the phone is locked or another app is in front, that needs an installed PWA with the Web Push API, a meaningfully bigger feature than this.
- Physical station lights (Feit/Tuya smart bulbs, `server/Sources/App/LightNotifier.swift`/`TuyaCloudClient.swift`/`PrepStation.swift`, see `docs/feit-bulb-table-order-lights.md`) — an optional, entirely physical echo of the spoken/visual alerts above, for a kitchen/bar that isn't looking at a screen. A new order pulses the server-station bulb in that area's color (gold/kitchen, teal/sushi, blue/bar) for 30 seconds or until confirmed entered; confirming entry triple-flashes both that station's bulb and the server bulb purple; an order crossing the "should be ready" prep-time threshold triple-flashes pink at the station and holds the server bulb pulsing pink until delivered. Polls the same `readyForDelivery()` data as the visual/spoken alerts every 5 seconds. `GET /api/table-orders/lights` (any logged-in staff) reports whether it's actually enabled and which fixtures/colors are configured, without exposing the Tuya credentials themselves. Entirely optional and a no-op unless `TUYA_*` credentials are set (see env table above) — **not configured yet**.
- Add-ons & upgrades on individual menu items (e.g. "Add Katsu +$6", "Yosh Size +$25.20") — staff define these per item from `/edit-item.html`, and a guest ordering that item from their table sees them as checkboxes right on the menu, with the selection carried through to the staff order queue. Not priced/charged automatically (this still isn't a payment system) — just makes sure the request actually reaches staff instead of getting lost.
- Checking an add-on updates that item's displayed price live, e.g. checking "Yosh Size" on a $28 Loco Moco shows "$53.20 ($28.00 + Yosh Size $25.20)" — so a guest sees the real total, and what's driving it, before they order. Unchecking everything reverts to the plain base price. Wraps onto multiple lines on a narrow screen instead of overflowing — checking every add-on on a dish at once (a long breakdown) stays fully on-screen at 390px wide.
- Required choice groups on composite dishes (`MenuItemChoiceGroup` — e.g. Shogun Bento's "your choice of chicken or beef") — staff define a label + comma-separated options per item on `/edit-item.html`, same "Required Choices" section, right below Add-Ons. Unlike a modifier, this renders as radio buttons (not checkboxes) since exactly one option must be picked and none of them change the price — the "Add to Order" button refuses to add the item (with an inline "Please make a selection" note) until every required choice group on it has a pick. The selection travels to staff the same way a modifier does — as a plain string like "Choice of Protein: Beef" appended to the order's `modifiers` list — so the kitchen queue needed no changes to show it. Reserved for a choice that's genuinely bundled into one dish; two dishes that happen to cost the same (e.g. "Chicken Teriyaki" vs. "Spicy Chicken Teriyaki") are simpler as two separate menu items instead (see `/edit.html`) — added 2026-08-02 after realizing several menu items were listed as "X or Y" in a single name/price, uneditable as a real choice at order time.
- `MenuItem.requiresModifierSelection` (added 2026-08-02) — for an item that's *all* optional add-ons with no real base price of its own (e.g. Extra Sauces: 6 checkboxes, $2 each, base price $0), checking "Require at least one add-on to be checked" on `/edit-item.html` blocks "Add to Order" until at least one modifier is checked, same inline-error pattern as required choice groups. False (i.e. every modifier really is optional) for the vast majority of items — this only matters for the rare item where ordering with nothing checked wouldn't make sense.
- Where a description's addition text (`"Add X +$Y"`, `"YOSH size: $Z"`, `"your choice of A or B"`) exactly matched what a modifier/choice group already conveys, the redundant text was trimmed from the description (2026-08-02) — the interactive checkbox/radio now shows the same information live, with better functionality (an actual selectable control, not just static text) than the sentence ever did. Left alone wherever the numbers didn't cleanly reconcile (see Yakisoba's "With chicken: $27 / YOSH $51.30," which doesn't match simple base+modifier addition — a pre-existing pricing inconsistency, not something this pass fixed) or where non-addition info shared the same sentence (e.g. Ohana Sliders/Gyoza's "(Set of 2)"/"(pork dumplings)," which stayed).
- Shared Additions Catalog (`GET`/`PUT /api/additions-catalog`, staff-only) — every add-on ever typed into `/edit-item.html` is saved to one sitewide list, so staff adding the same addition to another item (e.g. "Add Bacon") can pick it from a dropdown instead of retyping the name and price from scratch. Picking an entry just pre-fills the existing name/price fields — still editable before confirming — since some add-ons (like "Yosh Size") legitimately cost a different amount per dish.
- "Scan for common add-ons" button on `/edit.html` (`POST /api/menu/seed-additions`) — one click seeds the additions catalog and applies matching modifiers to every item whose own description already spells out an upcharge (e.g. "Add bacon +$5.50", "YOSH size: $53.20"), curated from a full sweep of the menu rather than a live text parser. Safe to click more than once — anything already present (matched case-insensitively by name) is left untouched, so it only ever adds what's missing.
- Staff rewards (`/staff-rewards-admin.html`, admin only) — a points card (same redeem-when-you-have-enough mechanic as the customer loyalty card) earned by keeping the site itself up to date. Points are valued per category, scaled to real effort/business value: marking a special or updating a price = 10 points (trivial data entry), adding a photo = 25, adding an event = 35 (real content-creation effort), a social media post = 30 (the most effort — shoot, write, post — and real marketing value). Editing a single menu item (via `/edit-item.html` or the inline "Edit" link — not the bulk `/edit.html` save, since that endpoint is also used by one-off migration scripts and shouldn't rack up points for those) auto-awards whichever categories actually changed, all independently, batched into one write per edit rather than one per category. Adding a new event on `/events-admin.html` auto-awards its points too. A staff member can log their own "other" activity right from `/account.html` for instant credit (20 points); a social media post instead requires a link and goes to a **Social Media Requests** queue on `/staff-rewards-admin.html` for admin approval (mirroring the existing customer loyalty bonus-request pattern) — no points land until approved, and approval is exempt from the daily cap since a human has verified it. Every other auto-award/self-report shares one cap of 100 points/staff/day, so neither repeatedly toggling a field nor repeatedly self-logging can farm unlimited points. An admin can still grant any category by hand, exempt from the daily cap.
  - **Photo bounty** — adding an item's first-ever photo pays double the regular photo rate (50 points instead of 25), so closing a real gap in menu photo coverage is worth more than touching up an item that already had one. Detected by comparing the item's image list before/after the edit (`awardForMenuEdit`), not by category choice — it's automatic.
  - **Point Values panel** (`/staff-rewards-admin.html`, `GET`/`PUT /api/staff-rewards/point-values`) — an admin can edit how many points each category is worth directly from the page, no code change needed. Persists as an override on top of the built-in defaults, so a category added later in code (like the photo bounty) always has a value even if it postdates the last time someone saved a custom set. The "Award Points" reason dropdown and the self-report dropdown on `/account.html` both pull their displayed point counts live from this, so they can't go stale after an edit.
  - **Reward Catalog** — points are redeemed against an editable catalog (`GET`/`PUT /api/staff-rewards/catalog`) rather than one fixed threshold: the default seeds a Classic Ohana Roll/Happy Hour appetizer at 1000 points (rescaled alongside the July 2026 point-value rescale) plus the current Shop swag, priced at that same ~100 points per $1 — **Bandana** (1000 pts, $10), **26th Anniversary T-Shirt** (2500 pts, $25), **Straw Hat** (5000 pts, $50). An admin edits names/costs (or adds/removes items) directly from the catalog panel; an item with no cost set can't be redeemed until it has one. The account.html progress bar targets whichever catalog item is currently cheapest, so it always reflects something actually redeemable.
  - Pre-2026-07-28 data (flat 1-point-per-action, no catalog) decodes forward compatibly — no migration needed. Values were rescaled roughly 1/10th smaller on 2026-07-29 (was a 100:1 points-to-dollar ratio) now that most menu items already have a photo, so an individual action reads as a smaller slice of the whole reward rather than the same big jump it used to be.
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
- Customer profile page now summarizes everything on file in one place — photo, email/verified status, birthday, linked rewards phone, sign-in methods, and an Order History panel (table orders placed while signed in, with status and timestamp).
- Order history without signing in, too (`/order-history.html`) — every `POST /api/table-orders` now also carries a `deviceId`, a random UUID the browser generates once and keeps in `localStorage` (`getDeviceId()` in `menu-section.js`/`order-history.js`; the only persistent, cross-session client-side key on the site — everything else, `ohana_table_id`/`ohana_active_orders`/`ohana_pending_cart`/`ohana_price_view`, deliberately uses `sessionStorage` instead and clears on tab close). `GET /api/table-orders/device-history?deviceId=<id>` (public — the id itself, unguessable, is the only thing that can look its orders up, same trust model as a capability link) returns everything ordered from that browser, logged in or not. Linked from the cart modal ("See your past orders"/"See your order history" — both the empty-cart and just-sent states). Not a real identity: no account, no PII, just enough to remember "this browser" across visits — worth noting this is now the one genuinely persistent, per-visitor-ish identifier on the site, a narrower/different thing than the analytics privacy stance below (which has no identifier of any kind, persistent or otherwise).
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
- Live Google reviews embedded on the homepage (`/api/place-reviews`) — author, star rating, and text pulled from the Google Place Details API and cached for 6 hours, reusing the same `GOOGLE_PLACES_API_KEY`/`GOOGLE_PLACE_ID` already configured for the photo carousel (no extra credential, no extra API quota — photos and reviews share one cached call). Falls back to just the existing "Read Reviews on Google/Yelp" link buttons if the widget has nothing to show. 1-star reviews are filtered out of this on-site widget (the review itself is untouched on Google, just not amplified here) — the overall star rating and review count shown alongside it still reflect Google's real, unfiltered totals.
- `sitemap.xml` and `robots.txt`
- Cache-Control revalidation on every response (avoids stale-cache bugs after a deploy)
- Accessibility pass — fixed real WCAG AA contrast failures (brand pink/gold read ~3:1 as text on light backgrounds; added darker `--pink-text`/`--gold-text` variants used only for text, keeping the brighter originals for backgrounds/borders), a focus state that was fully removed without a visible replacement, and a heading-hierarchy skip on the Contact page. Alt text was already solid site-wide.
- Automated test suite (`server/Tests/AppTests`, 257 tests) — loyalty punch/redeem math, waitlist and table-order lifecycle behavior (including prep-time estimation, delivery-stats aggregation, and cancellation), analytics aggregation (including OS/browser/device-model user-agent parsing), single-item menu CRUD, staff and customer auth (including deactivation, OAuth linking/photo- and email-backfill for both account types, Facebook as an independent provider alongside Google/Apple, and rewards-card linking), menu backward-compat decoding, the Happy Hour time-window/QR-redirect logic (including table-id passthrough), competitor-photo review tracking, station-light cue planning, and route-level permission boundaries. Run with `swift test` from `server/` — see [Local development](#local-development) for the GCC-version workaround this sandbox needs to actually build/link locally rather than relying only on CI.
- **Fixed**: `/analytics.html` itself has always been admin-only at the page level, but 3 of the API endpoints behind it (`delivery-stats`, `occupancy-stats`, `feedback` list/acknowledge) only required *some* staff login underneath — meaning a non-admin employee could still pull that data by calling the API directly, bypassing the page gate. All now require admin. The site-wide "N new feedback" badge every staff member sees (not just admins) is unaffected — that one only ever exposed a bare count, not the feedback content.
- Self-hosted analytics (`/analytics.html`, admin only) — pageview counts by page and by day, device type (mobile/tablet/desktop), operating system (iPhone/iPad/Android/macOS/Windows/Linux), browser (Safari/Chrome/Firefox/Edge/Samsung Internet/Opera), best-effort Android hardware model (e.g. "Pixel 8" — parsed only when a browser's user-agent happens to include it; iOS never exposes a specific model, so there's no equivalent list for Apple devices), average time on page, and most-viewed menu items (detail-popup opens — a proxy for interest, not a sales figure, since this site has no access to real order data from ChowNow). No cookies, no third-party tracking script, no per-visitor identity anywhere. Bounded to 120 days of aggregated data.
- `/analytics.html` landing view is a grid of compact summary cards (one per section — peak day, most-viewed page/item, device/OS/browser split, sitewide missing-price/photo counts, etc.), not a long single-column scroll. Clicking a card — or a notification link like `/analytics.html?section=feedback` — expands just that section into a full detail view, so the target always lands exactly where intended (no other section's async-loaded content is above it to shift the page after the click).
- Table-order wait/prep/delivery time KPIs on `/analytics.html`, computed from real completed orders: wait (placed → entered), prep (entered → delivered), and total (placed → delivered), both overall and broken out per menu item.
- Estimated Table Occupancy on `/analytics.html` (`GET /api/table-orders/occupancy-stats`, staff-only) — a full seating-to-departure table-turnover estimate, since nothing tracks when a party actually leaves so it can't be measured directly. Orders at the same table are grouped into "dining sessions" (a gap of over 90 minutes between orders means a new party sat down); each completed session combines its own real wait+prep time (from the KPI above) with an eating-time estimate from what was actually ordered (`DiningTimeEstimator.swift` — per-section baselines combined the same way overlapping prep times are: the single slowest dish, or half the combined total, whichever is greater) and a fixed allowance for deciding what to order beforehand and for conversation/paying/leaving afterward, sized so the total lands within the 60–90 minute range industry research reports for casual full-service dining. Falls back to a clearly-labeled generic single-entree example until at least one dining session has actually completed.
- "Popular Right Now" on `/specials` — the top menu items by real view count over the last 30 days, computed fresh on every page load (`/api/analytics/popular-items`), automatically skipping anything sold out or removed from the menu. Sits alongside, not instead of, the staff-curated "Today's Specials" section — nothing here overwrites what staff manually feature.
- "Menu Items Missing a Price" / "Menu Items Missing a Photo" reports on `/analytics.html`, scanning the entire live menu (including Happy Hour) — grouped by category with a count at the top of each group, and each row links straight to that item's `/edit-item.html` page to fix it on the spot.
- Competitor Menu Pricing (`/competitor-pricing-admin.html`, admin only, plus a summary on `/analytics.html`) — compares our prices for a dish (e.g. "Ohana Burger," "Spicy Tuna Roll") against nearby restaurants' published prices for the same/similar item, so pricing can be checked against the neighborhood instead of guessing. The restaurant list is sourced from Google Maps' own Nearby Search (`GET /api/competitor-pricing/nearby-restaurants`, real distance computed from Ohana's own coordinates via the Google Place Details `geometry` field, 3 miles by default) — staff pick from real, current nearby restaurants instead of typing a name/address by hand, shown as a mobile-friendly card grid (reusing the same `.shop-grid`/`.shop-card` pattern as `/shop`) rather than a table, since the actual workflow is "find a restaurant, snap photos of their menu" from a phone, not desk data entry. **Redesigned 2026-08-15** around that reality: the old one-dish-at-a-time "Comparison Groups"/"Price Entries" forms are still there (moved below, framed as "Manual Corrections") but pricing is now expected to get filled in by periodically pointing a Claude Code session at whatever menu photos are still unreviewed (`GET /api/competitor-pricing/photos/unreviewed`) and having it read prices/dishes off them directly via the existing `PUT /api/competitor-pricing/entries` API, then `POST /api/competitor-pricing/photos/mark-reviewed`. Each newly uploaded photo (tracked in a small separate store, `CompetitorPhotoReviewStore`/`Data/competitor-photo-review.json`, keyed by photo URL — kept in sync automatically whenever `CompetitorPricingStore.saveRestaurants` runs, not by the shared `/api/upload` route, since that route is used site-wide) shows a small pink dot until reviewed, and drives a site-wide staff notification badge (`GET /api/competitor-pricing/unreviewed-photo-count`, admin-only, same pattern as the table-order/feedback badges in `nav.js`) so the owner knows there's photo-review work waiting. A staff member can also dismiss a photo's unreviewed flag by hand (a ✓ button on the thumbnail) without waiting on a Claude session. The report shows our price (pulled live so it can't go stale) alongside the competitor average/min/max and how far off we are (in dollars and %), per comparison.
- Pricing Findings & Suggestions (`/competitor-pricing-findings.html`, admin only, linked from the Price Comparison Report panel on `/competitor-pricing-admin.html`) — a written, static read of the live comparison data: which price gaps look real vs. which are single-restaurant noise, ranked by sample size rather than by size of the gap, plus concrete suggested actions (e.g. raise/hold/investigate-further) and the caveats behind the current dataset (stale menu photos, conflicting price sheets, staff-estimated distances). This is a snapshot written by hand, not auto-generated from the report — re-read and update it as more competitor entries get added, especially for anything currently flagged as a thin (n=1) sample.
- Shop (`/shop`, public) + `/swag-admin.html` (staff) — sells physical merch (bandanas, hats, t-shirts) alongside the food menu, on purpose kept as a separate `SwagProduct`/`SwagStore` model rather than folded into the food `MenuStore`: menu prices are deliberately hidden until a table's QR is scanned (Yosh's call) and menu sections feed `PrepTimeEstimator`/`DiningTimeEstimator` for kitchen timing — neither rule makes sense for a t-shirt, so Shop prices always show and swag never gets a prep-time estimate. Staff manage the product list (name, price, availability, photos via the same shared `/api/upload`) on `/swag-admin.html` — any logged-in staff member, not admin-only, matching how the food menu itself is edited. A product with more than one photo (e.g. a t-shirt's front and back) cross-fades through all of them on its Shop card every 4 seconds — same absolute-stack/opacity-crossfade technique as the menu item detail modal's photo gallery, just sized for a grid tile; one shared interval walks every multi-photo card, so counts differing between products doesn't matter. Customers add items to a cart (`sessionStorage`, mirrors the food-order cart pattern) and pay with a real card via **Square Checkout** (Payment Links API — chosen over Stripe since the restaurant already has an active Square account, no new merchant signup needed) — unlike food orders (which just queue for staff and get paid in person when the check comes), this is actual online payment, so it requires a scanned table (`?table=` from the same QR-scan flow food ordering uses) so staff know where to deliver it. `POST /api/swag/checkout` creates a pending `SwagOrder` and a Square-hosted payment link; Square's own page collects the card (this app never touches a card number); `POST /api/swag/square-webhook` — signature-verified against `SQUARE_WEBHOOK_SIGNATURE_KEY` — is the *only* thing that marks an order paid (never the browser redirect back, which a guest could reach without actually paying by hitting back/forward). Paid-but-undelivered orders show on `/swag-admin.html` for staff to mark delivered once dropped off. Entirely gated behind `SQUARE_ACCESS_TOKEN`/`SQUARE_LOCATION_ID`/`SQUARE_WEBHOOK_SIGNATURE_KEY` (see env table above) — until those are set, the Shop page shows products and prices but the checkout button stays hidden (`GET /api/swag/checkout-status`), same "hidden until configured" pattern as AI menu extraction / Apple / Facebook Sign-In.
- Gift Cards (`/gift-cards`, public) + `/gift-cards-admin.html` (staff) — lets a customer pay online for an Ohana Belltown gift card, any amount from $5–$500 (three preset buttons plus a custom-amount field). Deliberately does **not** call Square's Gift Card / Gift Card Activities API to create or activate a card — Ohana already sells physical gift cards in person, so this only needed to solve "collect payment online," not "issue a card," and building the create/activate flow would have been solving a problem that didn't exist. It's also deliberately *not* tied to a table like Shop is — most gift cards are bought as a gift, not while dining in — so the buyer instead gives their name/email (and optionally who it's for + a note) at checkout, and a staff member follows up directly (activates a physical card for the paid amount and mails it / holds it for pickup / brings it to their table if they happen to be dining in) once the order shows "Paid" on `/gift-cards-admin.html`. Shares `SQUARE_ACCESS_TOKEN`/`SQUARE_LOCATION_ID` and even the webhook subscription with Shop checkout (`POST /api/swag/square-webhook` now checks both `SwagOrdersStore` and `GiftCardOrdersStore` for a matching order id — Square only needs one `payment.updated` subscription registered, not two) — same hidden-until-configured pattern, checked via the same `GET /api/swag/checkout-status`.
- AI menu-photo extraction on Competitor Pricing (`POST /api/competitor-pricing/extract-menu`, gated behind `ANTHROPIC_API_KEY` — a separate credential from any claude.ai chat subscription, not set yet) — reads a competitor's uploaded menu photo with Claude's vision API and returns item names/prices, shown in an editable review list (never trusted blindly) with a "Compare To" picker for an existing comparison group or a fresh one, and an "Add as Price Entry" button that saves the restaurant (if it was only just added via the picker and never explicitly saved), the group, and the entry together. The "Extract Items" button itself only appears once `GET /api/competitor-pricing/ai-extraction-status` reports the key is configured — same "hidden until configured" pattern as Apple/Facebook Sign-In.
- Uploaded photos (menu editor, customer bonus-claim photos) are auto-resized (1600px long-edge cap) and re-compressed via ImageMagick, run off the event loop so it doesn't stall other requests. Fails closed — if optimization fails for any reason, the original upload is kept as-is rather than blocking the upload.
- **Fixed**: `POST /api/upload` was capped at 8mb, well under what a real phone photo often is — staff were seeing a bare "Upload failed" with no explanation. Raised to 20mb, and every upload call site now surfaces the server's actual error message (e.g. "Payload Too Large," "Only jpg, png, webp, gif, or heic/heif images are allowed") instead of a bare status code. Also added HEIC/HEIF support (the default format iPhones save photos in, which no major browser can render) — the upload is converted to JPEG server-side via ImageMagick rather than saved with an extension nothing can display; if the container's ImageMagick build lacks the HEIF delegate, it fails with a clear "try a JPEG or PNG instead" message rather than silently linking a broken image.
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

**Needs a follow-up action, not a code change**
- **Google Sign-In's redirect URI may still point at the old Azure hostname.** When the site's canonical domain moved to `https://www.ohanasushigrill.com` (see `PublicBaseURL.swift`), the app started requesting `https://www.ohanasushigrill.com/auth/google/callback` as the OAuth redirect URI instead of the old Azure one. If that exact URL hasn't been added to **Authorized redirect URIs** in the Google Cloud Console yet (`docs/oauth-setup.md` has the steps), Google sign-in fails with `redirect_uri_mismatch`. Quick to confirm/fix, but can't be verified or done from this codebase — needs a login to the Google Cloud Console.

**Known deliberate tradeoffs (not bugs)**
- **AI menu-photo extraction is built but not live yet.** Needs `ANTHROPIC_API_KEY` (see the env table above) — a separate credential/billing setup from any claude.ai chat subscription, not yet configured. Until then, the "Extract Items" button on Competitor Pricing simply doesn't appear (checked via `GET /api/competitor-pricing/ai-extraction-status`), same pattern as Apple/Facebook Sign-In staying hidden until their credentials exist.
- **Shop and Gift Card checkout are configured against Square's SANDBOX, not production yet** — see [Payment Processing](#payment-processing-square) below for the full picture and exactly what's needed to go live.
- **No real email delivery yet.** `EmailSenderFactory` (`server/Sources/App/EmailSender.swift`) now has a real `ResendEmailSender` implementation (Resend's REST API, no SDK dependency) wired in and ready — it's just inactive until `RESEND_API_KEY` is set (see the env table above), same "built but hidden/inactive until configured" pattern as Square/Apple/Facebook. Until then, `ConsoleEmailSender` still logs the email server-side instead of sending it, so customer email verification and password-reset links don't reach anyone's inbox. Verification/reset links are now absolute (`PublicBaseURL.get()` + path) so they'll actually work once emailed, rather than the bare relative paths that only made sense read off the server console.
- Sessions are now file-backed (`FileSessions`/`FileSessionsStore` in `server/Sources/App/FileSessions.swift`), persisted as one JSON file per session under `<DATA_DIR>/sessions/` — the same Azure Files–backed volume every other store uses — so a deploy or restart no longer logs everyone out. Stale session files (untouched 30+ days) are pruned daily. Replaces the prior in-memory driver, which lost every session on restart.
- Every new/reset staff account gets a caller-chosen temporary password and must change it on next login — there's no forced password-strength policy beyond that.
- Bonus punch claims (photo/social shares) are staff-reviewed, not auto-verified — there's no reliable API to check a social tag automatically.
- Google Places photos are capped at 10 per API call (a hard Google limit, not a bug) and matched to menu items manually.
- Sign in with Apple needs a client-secret JWT that's re-signed on every token exchange (Apple doesn't accept a static secret like Google does) — implemented with `swift-crypto`'s `P256.Signing` rather than pulling in a full JWT library, since that's the only cryptographic operation needed.

## Payment Processing (Square)

Real online card payments exist in exactly two places on this site: **Shop**
(`/shop`, swag) and **Gift Cards** (`/gift-cards`). Both were built
2026-08-01/02, both go through **Square**, and both share the same
credentials, the same "is checkout configured" check, and even the same
webhook subscription.

**Why Square (not Stripe):** the integration was originally built against
Stripe, then switched the same day after confirming — by having the user log
into `app.squareup.com/dashboard` — that the restaurant already has an active
Square account. That meant no new merchant signup, unlike Stripe. The Stripe
code was fully removed, not kept alongside.

**Current state: SANDBOX, not production.** `SQUARE_ACCESS_TOKEN` /
`SQUARE_LOCATION_ID` / `SQUARE_WEBHOOK_SIGNATURE_KEY` are all set on the
Container App with `SQUARE_ENVIRONMENT=sandbox` — checkout works completely
end-to-end (verified with a real sandbox purchase) but only with Square's fake
test card (`4111 1111 1111 1111`, any future expiry/CVV, any ZIP). **No real
money has moved yet.**

**To go live**, two changes on the Container App:
1. Swap `SQUARE_ACCESS_TOKEN` for the **production** access token — Square
   Developer Dashboard → your app → **Credentials** → Production Access Token
   (click "Show" to reveal it; it's hidden by default). The token the user
   first provided turned out to be the *sandbox* token (`EAAAl...`, confirmed
   by calling `GET /v2/locations` and getting back a fake "Default Test
   Account" location, not Ohana) — worth double-checking which one gets
   copied next time, since sandbox and production tokens look similar.
2. Unset `SQUARE_ENVIRONMENT` (or set it to anything other than `sandbox`) so
   requests hit `connect.squareup.com` instead of
   `connect.squareupsandbox.com`.

No code changes needed for either step — both are pure environment/secret
changes on the existing Container App (`az containerapp secret set` +
`az containerapp update --set-env-vars`, same pattern as every other
credential in the env table above).

**How it actually works** (`server/Sources/App/SquareCheckout.swift`):
- Calls Square's plain REST API directly (`https://connect.squareup.com/v2/...`)
  — no SDK dependency, mirroring how `GoogleOAuth.swift`/`AppleOAuth.swift`
  already call their providers with `req.client`. API version is pinned
  (`Square-Version: 2026-07-15`) rather than left to drift.
- **Payment Links API** (`POST /v2/online-checkout/payment-links`) creates a
  Square-hosted checkout page with the cart's line items; the customer is
  redirected there to enter their card. This app **never touches a raw card
  number** — Square's own page collects it.
- A `SwagOrder`/`GiftCardOrder` is created as `pendingPayment` *before* the
  redirect, with Square's returned `order_id` attached. The customer landing
  back on `/shop` or `/gift-cards` with `?checkout=success` is **not** what
  marks it paid — that's just a redirect URL a guest could reach without
  actually paying (hitting back/forward). Only the signature-verified webhook
  does that.
- **Webhook**: `POST /api/swag/square-webhook` (one shared endpoint despite
  the "swag" in the path — Square only allows one subscription per
  `payment.updated` event per notification URL, and both features fire that
  same event, so splitting into two endpoints would just mean two
  subscriptions to keep in sync for no benefit). Verifies
  `x-square-hmacsha256-signature` — `base64(HMAC-SHA256(signature key,
  notification URL + raw body))` — using `swift-crypto`, then checks the
  payment's `order_id` against both `SwagOrdersStore` and
  `GiftCardOrdersStore` for a match. Whichever store has it gets marked paid.
- **Gift Cards deliberately doesn't call Square's Gift Card / Gift Card
  Activities API** to create or activate a real Square gift card. Ohana
  already sells physical gift cards in person — the ask was "let customers
  pay for one online," not "issue one via API" — so it only needed to solve
  payment collection. A staff member activates a physical card by hand once
  an order shows "Paid" on `/gift-cards-admin.html`. Building the real
  create/activate flow is a plausible future upgrade (see below) but wasn't
  needed to satisfy the actual request.
- Neither checkout requires a customer account/login. **Shop requires a
  scanned table** (`?table=`, same QR-scan flow as food ordering) so staff
  know where to deliver the merch; **Gift Cards deliberately does not** —
  most gift cards are bought as a gift, not while dining in, so the buyer
  gives name/email/optional-recipient-name/note at checkout instead, and
  staff follow up directly.

**Resolved loose end:** the earlier mention of a card processor called
"spaced" (misheard over the phone) was clarified to **Echelon**
(echelonpayments.com) — a real traditional payment processor with its own
online-payment products. Whether Echelon would actually be cheaper than
Square for this site's web purchases is unresolved (Echelon doesn't publish
pricing) — see `docs/payment-processing-plan.md` for the full comparison,
what's verified about each, and exactly what to ask Echelon for before
deciding whether to switch.

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

## Suggestions for future development

Roughly in priority order — not a committed roadmap, just where the next
session's effort would likely pay off most. Written 2026-08-02, refreshed
2026-09-02 after the domain went live, Competitor Pricing was redesigned
around photo upload, and station-light table-order notifications shipped.

1. **Confirm Google Sign-In's redirect URI is registered for the real
   domain.** Two minutes, and currently the single most likely thing to be
   actively broken for a real user — see "Needs a follow-up action" above.
   Add `https://www.ohanasushigrill.com/auth/google/callback` in the Google
   Cloud Console (steps in `docs/oauth-setup.md`) if not already done.
2. **Flip Square to production.** Still the highest-leverage *money* item:
   Shop and Gift Cards are fully built and tested, just sitting behind a
   sandbox flag. See [Payment Processing](#payment-processing-square) above
   for the exact two-step swap. Nothing else blocks this.
3. **Set `RESEND_API_KEY`.** Code is done: `ResendEmailSender`
   (`server/Sources/App/EmailSender.swift`) is implemented and
   `EmailSenderFactory.make` already branches on `RESEND_API_KEY`.
   Self-service password reset and email verification are still dead ends
   until that key exists (the link just gets logged server-side, never
   delivered). Two paths, don't let one block the other:
   - **Fast path (do this first):** skip domain verification, send from
     Resend's own `onboarding@resend.dev` address (the current default for
     `RESEND_FROM_ADDRESS`). Five minutes, unblocks real delivery today,
     just not `@ohanasushigrill.com`-branded.
   - **Branded path:** verify `ohanasushigrill.com` (or a subdomain) with
     Resend — now unblocked, since DNS has moved off Weebly and the domain
     is live (see below) — then set `RESEND_FROM_ADDRESS` to a real address
     on it.
4. ~~**Move DNS / bind the real domain**~~ — **done.**
   `ohanasushigrill.com`/`www.ohanasushigrill.com` are live, bound as
   custom domains on the Container App with a managed cert, and every
   hardcoded reference to the old Azure hostname (canonical/og tags,
   sitemap, `PublicBaseURL.swift`'s fallback, the 43 printed table-card QR
   codes) has been swept to the real domain. This is what unblocked the
   branded-email path in item 3 above.
5. **Get a real Echelon quote** — `docs/payment-processing-plan.md` has the
   full comparison and exactly what to ask for (effective online rate,
   pricing model, gateway/monthly/PCI fees, contract terms). Re-checked
   2026-09-02: still no public pricing from Echelon, so this is still
   blocked on getting a written quote. Square's rates are already verified
   and documented in that file for comparison.
6. **Quick-win OAuth credentials, if still wanted:** Facebook Login is free
   and ~10 minutes (steps in `docs/oauth-setup.md`) — the backend and hidden
   UI are already built and tested, just needs `FACEBOOK_OAUTH_APP_ID`/
   `FACEBOOK_OAUTH_APP_SECRET`. Apple Sign-In needs a paid ($99/yr) Developer
   Program enrollment first, so it's a real cost decision, not just a
   time cost — confirm it's still wanted before spending on it.
7. **`ANTHROPIC_API_KEY` for AI menu-photo extraction** — cheap (pay-per-use,
   fractions of a cent per photo), fully built, just needs billing set up at
   console.anthropic.com (separate from any claude.ai chat subscription).
   Note this is now a *bonus* on Competitor Pricing rather than the primary
   workflow there — see the redesign described in "What's shipped" above,
   where a periodic Claude Code session reads unreviewed menu photos
   directly instead.
8. **Wire up the Tuya station lights, if the physical bulbs are ready.**
   Built and merged (`LightNotifier.swift`/`TuyaCloudClient.swift`, see
   `docs/feit-bulb-table-order-lights.md`), fully dormant until `TUYA_*`
   credentials are set (see env table above) — needs a Tuya IoT Platform
   Cloud project plus each bulb's device ID pulled from the Tuya/Smart Life
   app. Purely physical/optional — nothing else depends on this.
9. **Decide on the Yakisoba pricing inconsistency** found during the
   description-cleanup pass (2026-08-02): its "With chicken: $27 / YOSH
   $51.30" note doesn't reconcile with simple base+modifier math (base $23 +
   Add Chicken $4 + Yosh Size $20.70 = $47.70, not $51.30) — left as-is
   pending a human call on which number is actually correct, since silently
   "fixing" a real menu price without knowing the intent seemed riskier than
   flagging it. Still unresolved.
10. **Consider real Square Gift Card API integration** as a later upgrade —
    today, `/gift-cards` only collects payment; a staff member manually
    activates a physical card. If volume justifies it, Square's Gift Cards +
    Gift Card Activities API could auto-create and activate a real,
    scannable digital gift card server-side once a webhook confirms
    payment, emailing (or displaying) the resulting GAN to the buyer.
    Bigger build — this is why it was deliberately skipped for the initial
    version.
11. **Uptime monitoring** — steps are ready in `docs/uptime-monitoring.md`,
    just needs a free UptimeRobot account created (can't be done on your
    behalf) pointed at the existing `/healthz` endpoint.
12. ~~**Session persistence**~~ — done: sessions are now file-backed
    (`server/Sources/App/FileSessions.swift`), persisted under
    `<DATA_DIR>/sessions/` on the same Azure Files volume every other store
    uses, so a deploy no longer logs everyone out.
13. **The bigger long-term idea worth naming:** table ordering
    (`/menu` → "Add to Order" → `/table-orders-admin.html`) is currently just
    a "heads up" queue — staff still ring everything up on the real POS, and
    payment happens the traditional way. Now that real Square payment rails
    exist in this codebase (Payment Links, webhooks, signature verification,
    all proven out by Shop/Gift Cards), a natural next evolution — if ever
    wanted — is extending that same pattern to actual dine-in checkout:
    charge the table's card for the full order Square already knows about,
    rather than just notifying staff. Not scoped or estimated, just flagged
    as the logical next step once the smaller payment surfaces (Shop, Gift
    Cards) have some real usage behind them. Worth noting: the cancel/
    auto-cancel-stale-orders work above was partly done with this in mind —
    an order's `status` needs to be a trustworthy, always-resolved signal
    (never silently "still open" forever) before anything should ever key a
    real charge off of it.

See [High-impact design/UX recommendations](#high-impact-designux-recommendations)
below for suggestions on the site's usability/visual design rather than its
feature backlog.

## High-impact design/UX recommendations

Observations from working across the whole site this session, not tied to
any specific bug report — worth considering, not urgent, no action taken
yet. Roughly ordered by expected impact for the effort involved.

1. **Add a dark mode, at least for customer-facing pages.** `style.css` hard-codes
   `color-scheme: light` with no `@media (prefers-color-scheme: dark)` or
   `[data-theme]` handling anywhere in the site. This matters more than
   usual for a restaurant: a guest is often pulling up `/menu` at a table in
   a dimly-lit room at night, on their phone, at full brightness because the
   page assumes daylight. The brand palette (`--pink`, `--purple`, `--gold`)
   already has WCAG-AA-safe text variants (`--pink-text`, `--gold-text`)
   from the earlier accessibility pass — a dark palette could reuse the same
   verification method. Start with `/menu`, `/sushi`, `/drinks`,
   `/happy-hour`, `/specials` (what a seated guest actually looks at);
   staff admin pages are lower priority since they're used in a lit
   back-of-house environment.
2. **Bring the rest of the staff admin pages' tables to mobile.** Competitor
   Pricing's restaurant list was rebuilt this session as a `.shop-grid` card
   layout instead of a `<table>` that only handled narrow screens via
   `overflow-x: auto` sideways scroll (see "What's shipped" above) — because
   staff actually use that page from a phone. The same sideways-scroll
   pattern is still how every *other* admin table works (`swag-admin.html`,
   `loyalty-admin.html`, `events-admin.html`, `staff-rewards-admin.html`,
   etc.), and staff are just as likely to be on a phone there too. Worth
   auditing which of those get used away from a desk and giving the
   highest-traffic ones the same card-based treatment.
3. **Consolidate the growing stack of staff notification badges.** There are
   now five separate "something needs attention" signals surfacing as
   individual pills in the same top-right corner via `nav.js`: table orders,
   customer feedback, and competitor menu photos as visible badges, plus the
   spoken-alert system layered on top of the first. Fine at this count, but
   each new one (the next might be staff-reward approval requests, or
   something else) makes the corner more cluttered and harder to scan at a
   glance. Worth collapsing into a single "N notifications" dropdown/badge
   before adding a fourth or fifth, rather than after it starts feeling
   crowded.
4. **A unified staff "home" dashboard.** With four different "needs
   attention" data sources now (table orders, feedback, competitor photos,
   staff-reward approvals) spread across different admin pages, there's no
   single place a manager can glance at to see everything waiting on them —
   they have to know to check each page out of habit, or wait for whichever
   badge happens to catch their eye. A simple landing page summarizing all
   of them (reusing the counts each badge already computes) could replace
   that habit-based checking with one real answer.
5. **Resolve Square/Echelon and flip on real online checkout.** Already the
   top item in "Suggestions for future development" above, but worth
   repeating here as the single biggest *customer-facing* UX gap: Shop and
   Gift Cards currently show real products/prices but can't actually take a
   real payment yet, and dine-in table ordering (`/menu` → "Add to Order")
   is a heads-up queue rather than real checkout. The UX is otherwise fully
   built for all three — this is a credentials/business decision away from
   being a materially better experience, not more engineering.

## Other docs in this repo

- `docs/payment-processing-plan.md` — Square vs. Echelon comparison for web-purchase card processing (Shop/Gift Cards) — Echelon doesn't publish pricing, so this is a research/decision-framework doc pending a real quote, not a completed comparison
- `docs/feit-bulb-table-order-lights.md` — how the optional Tuya station-light table-order notifications work and how to configure real bulbs (`TUYA_*` env vars)
- `docs/feature-roadmap.md` — original feature audit and phased plan (predates most of what's now shipped; see the gaps list above for current state)
- `docs/visual-design-direction.md` — the palette/type direction used for the visual refresh
- `docs/oauth-setup.md` — step-by-step Google/Apple/Facebook Sign-In credential setup
- `docs/loyalty-points-migration.md` — future plan for switching the customer punch card to a points system (to support variable rewards and sellable/giveaway swag) once the punch card has real launch feedback — not scheduled yet
- `docs/uptime-monitoring.md` — how to point UptimeRobot (free) at the existing `/healthz` endpoint
- `docs/pricing-review-2026-08-06.md` — suggested menu price changes with reasoning, based on the real competitor data already gathered in the Competitor Pricing admin tool (`/competitor-pricing-admin.html`) plus general judgment where no local comparison data exists yet — not yet acted on
- `docs/page-inventory.md`, `docs/migration-plan.md`, `docs/ohana-project-plan.md` — early planning docs from the static-site-capture phase, kept for history
- `reference-site/` — the original Weebly site mirror this project was migrated from
