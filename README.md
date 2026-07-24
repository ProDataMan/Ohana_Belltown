# Ohana Belltown Website

A Swift/Vapor server powering [Ohana Belltown](https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io)'s
full website: marketing pages, the complete food/sushi/drinks/happy-hour menu,
a staff editor, a digital punch card, and an events calendar — deployed on
Azure Container Apps.

This started as a static-site capture of the old Weebly site (see
`docs/migration-plan.md` and `docs/ohana-project-plan.md` for that history);
it has since been rebuilt as a real server-backed app and those early docs are
now historical background rather than the current plan.

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
  sessions don't survive a restart, so a deploy logs everyone out; acceptable for a small internal team)
- **Hosting:** Azure Container Apps (Consumption plan), resource group `Ohana`, app `ohana-belltown-server`
- **Images:** [ghcr.io/prodataman/ohana-belltown-server](https://ghcr.io/prodataman/ohana-belltown-server) (GitHub Container Registry, public)
- **CI/CD:** `.github/workflows/deploy-server.yml` — on push to `main`, builds and pushes the
  Docker image, then runs `az containerapp update` via OIDC federation (no stored Azure secrets)
- **Third-party integrations:** Google Places API (business photos), ChowNow (online ordering, linked out — not embedded)

### Required environment / secrets on the Container App

| Variable | Purpose |
|---|---|
| `DATA_DIR` | Path to the mounted persistent volume for JSON data + uploads |
| `PORT` | Server port (Container Apps sets this) |
| `GOOGLE_PLACES_API_KEY` | Server-side only, proxies Google Business photos |
| `GOOGLE_PLACE_ID` | Ohana Belltown's Google Place ID |

`STAFF_PIN` is no longer used — it was retired in favor of real per-user login (see below) and can be removed from the Container App if still set.

## Pages & routes

| Path | What it is |
|---|---|
| `/`, `/about`, `/local`, `/contact`, `/catering` | Marketing pages |
| `/menu`, `/sushi`, `/drinks`, `/happy-hour` | Menu sections (216 items total) — search box + allergen/dietary filter chips |
| `/rewards` | Customer-facing sushi punch card: check a card by phone, submit a photo/social bonus claim |
| `/login` | Staff login. First run (zero accounts) shows a one-time "create the first admin" form instead. |
| `/account.html` | Self-service: view own profile, log out |
| `/change-password.html` | Self-service password change (requires current password) |
| `/edit.html` | Staff menu editor — prices, descriptions, photos, tags, featured/sold-out toggles. **Any logged-in employee.** |
| `/loyalty-admin.html` | Staff: punch a card, redeem a reward, approve/deny bonus claims. **Any logged-in employee.** |
| `/events-admin.html` | Staff: edit the events/specials shown on `/local`. **Admin only.** |
| `/create-account.html`, `/manage-users.html` | Admin: create staff accounts, change roles, reset passwords. **Admin only.** |
| `/table-card.html` | Printable QR-code table tents linking to `/menu` |
| `/signup`, `/account-login` | Customer registration and login (separate from staff accounts) |
| `/my-account.html` | Customer's own account page — profile, password change |
| `/forgot-password.html`, `/reset-password.html` | Customer self-service password reset |
| `/api/menu`, `/api/events`, `/api/loyalty/*`, `/api/auth/*`, `/api/users/*`, `/api/account/*`, `/api/customer/*` | JSON API backing all of the above |

## What's shipped

**Content & migration**
- Full real menu — 216 items across Food/Sushi/Drinks/Happy Hour, transcribed from the current printed menu
- 204/216 items have written descriptions; brand-name drinks researched and described
- Home, About, Local, Contact, Catering pages with real copy, ported from the old Weebly site
- Legacy `.html` URL redirects preserved for SEO
- HTTPS + persistent storage (Azure Files-backed menu data and photos)

**Menu experience**
- Search box + allergen/dietary tag filter chips (`server/Public/menu-section.js`)
- Photo lightbox + per-item detail modal with a photo gallery (multiple photos per item, rotates in Google Places photos where matched)
- Daily specials / featured-item toggle, surfaced on the homepage
- Per-item sold-out ("86'd") toggle — item stays visible on the public menu, grayed out with a "Sold Out Today" badge, instead of disappearing or requiring deletion
- Staff editor (`/edit.html`) — prices, descriptions, multi-photo galleries (manual upload or pick from Google Places), tags, featured toggle, sold-out toggle. Requires login (any employee); saves directly to the live site.

**Loyalty & engagement**
- Digital sushi punch card (`/rewards` + `/loyalty-admin.html`) — phone-number identity, 1 punch per sushi order,
  10 punches = free roll, bonus punches for photo/social shares via a staff approval queue
- Events & specials calendar (`/events-admin.html` + public display on `/local`)
- Printable QR-code table tents linking straight to `/menu`
- Google/Yelp review buttons link directly to Ohana's actual listings (not a generic search)
- Call/text-to-reserve CTA on the homepage and Contact page (deliberately not a paid platform like OpenTable/Resy — see [Known gaps](#known-gaps--not-yet-implemented))

**Staff accounts**
- Named username/password logins (bcrypt-hashed) with two roles: `admin` and `employee`
- First-run bootstrap creates the first admin when zero accounts exist, then permanently disables itself
- Admins manage the roster (`/manage-users.html`, `/create-account.html`): create accounts, change roles, force-reset a forgotten password
- Anyone can change their own password (`/change-password.html`); new/reset accounts must change their password on next login
- Real audit trail by design — actions are tied to a named account, not a shared PIN

**Customer accounts**
- Separate from staff accounts — email/password identity only, no `admin`/`employee` role, no order history yet
- Self-service registration (`/signup`), login (`/account-login`), password change and reset (`/forgot-password.html` → `/reset-password.html`, 1-hour expiring token)
- Email verification link on signup — **not actually delivered yet** (see gaps below), logged server-side instead

**SEO & technical**
- Per-page Open Graph / Twitter Card tags
- schema.org `Restaurant` JSON-LD on the homepage
- `sitemap.xml` and `robots.txt`
- Cache-Control revalidation on every response (avoids stale-cache bugs after a deploy)

## Known gaps / not yet implemented

Pulled from `docs/feature-roadmap.md`'s original audit, updated for what's
actually shipped as of this README. Not in priority order.

**Trust & findability**
- Embedded map on the Contact page (currently just a "Get Directions" link out to Google Maps)
- Accessibility pass — alt text coverage, focus states, and contrast haven't been formally audited
- Reviews are linked, not embedded (no live Google/Yelp rating widget on-site)

**Discovery & conversion**
- Self-serve/live reservation booking — deliberately not built. Evaluated OpenTable ($149–499/mo + $1–1.50/cover on network bookings), Resy ($0–399/mo flat, no per-cover fee on direct bookings), and Tock (merging into Resy); none are worth the cost against Ohana's walk-in-friendly positioning without a concrete signal (e.g. regularly turning away walk-in groups) that it's needed. Shipped the free call/text CTA instead — revisit if that signal shows up.
- Online gift card purchase (still "call us and we'll mail one")
- General photo gallery page (ambiance/event photos exist but aren't collected into one gallery)

**Engagement & retention**
- Email/SMS signup for specials
- Order history, "reorder your last meal", and linking a customer account to the phone-based punch card (customer accounts exist now but are pure identity — no order data yet)
- Native delivery radius checking (delivery relies entirely on ChowNow's partners)

**Technical**
- Image optimization pipeline (uploaded photos aren't auto-resized/compressed to WebP)
- Analytics (no Plausible/GA4 or equivalent)
- Uptime/error monitoring/alerting
- Formal Lighthouse performance pass
- Automated test suite (no `AppTests` target currently — testing has been manual via curl + local `swift run`)

**Admin & operations**
- Password reset is admin-only for staff (an admin resets it for you) — no self-service "forgot password" email flow for staff (customers have one; see the email caveat below for why it's not fully live yet)
- Account deactivation/removal isn't built for staff or customer accounts — roles/passwords can be changed but accounts can't be disabled or deleted
- ChowNow menu photo import — investigated, blocked by Cloudflare bot protection on ChowNow's API; not pursued further (see git history for details)

**Known deliberate tradeoffs (not bugs)**
- **No real email delivery yet.** `EmailSenderFactory` (`server/Sources/App/EmailSender.swift`) currently returns a placeholder that logs the email server-side instead of sending it — so customer email verification and password-reset links don't reach anyone's inbox right now. Swapping in a real provider (Resend, SendGrid, etc. — still deciding, was going to be GoDaddy but that isn't a transactional-email API provider in the usual sense) is a single-file change once an API key is available. Until then, self-service password reset for customers is not actually functional end-to-end.
- Sessions use Vapor's in-memory driver — a deploy or restart logs everyone out. Fine for a ~9-person staff team and low-stakes customer accounts; would need a persistent session store (e.g. file- or Redis-backed) to survive restarts.
- Every new/reset staff account gets a caller-chosen temporary password and must change it on next login — there's no forced password-strength policy beyond that.
- Bonus punch claims (photo/social shares) are staff-reviewed, not auto-verified — there's no reliable API to check a social tag automatically.
- Google Places photos are capped at 10 per API call (a hard Google limit, not a bug) and matched to menu items manually.

## Local development

```bash
cd server
# GCC version workaround needed on this dev box (Swift picks up an incomplete
# GCC 12 over the fully-installed GCC 11 otherwise):
export CPLUS_INCLUDE_PATH="/usr/include/c++/11:/usr/include/x86_64-linux-gnu/c++/11"
export LIBRARY_PATH="/usr/lib/gcc/x86_64-linux-gnu/11"

swift build
DATA_DIR=./Data swift run App
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
- `docs/page-inventory.md`, `docs/migration-plan.md`, `docs/ohana-project-plan.md` — early planning docs from the static-site-capture phase, kept for history
- `reference-site/` — the original Weebly site mirror this project was migrated from
