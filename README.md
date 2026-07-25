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
  sessions don't survive a restart, so a deploy logs everyone out; acceptable for a small internal team).
  Google/Apple OAuth on top of that (see [Setting up Google/Apple Sign-In](#setting-up-googleapple-sign-in)),
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
| `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` | Google Sign-In. Not set yet — see [Setting up Google/Apple Sign-In](#setting-up-googleapple-sign-in). |
| `APPLE_OAUTH_CLIENT_ID`, `APPLE_OAUTH_TEAM_ID`, `APPLE_OAUTH_KEY_ID`, `APPLE_OAUTH_PRIVATE_KEY` | Sign in with Apple. Not set yet — needs a paid Apple Developer Program enrollment first. See below. |

`STAFF_PIN` is no longer used — it was retired in favor of real per-user login (see below) and can be removed from the Container App if still set.

## Pages & routes

| Path | What it is |
|---|---|
| `/`, `/about`, `/local`, `/contact`, `/catering` | Marketing pages |
| `/menu`, `/sushi`, `/drinks`, `/happy-hour` | Menu sections (216 items total) — search box + allergen/dietary filter chips |
| `/specials` | Stable landing page (today's specials, Happy Hour hours, drinks teaser) for linking from social media/bio links |
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
- Embedded map on the Contact page (no API key/billing needed — uses the classic `maps.google.com/maps?...&output=embed` URL)
- Call/text-to-reserve CTA on the homepage and Contact page (deliberately not a paid platform like OpenTable/Resy — see [Known gaps](#known-gaps--not-yet-implemented))
- `/specials` — a stable page for social bio links / post links, so a marketing link doesn't have to point at the homepage or bounce between three different pages

**Staff accounts**
- Named username/password logins (bcrypt-hashed) with two roles: `admin` and `employee`
- First-run bootstrap creates the first admin when zero accounts exist, then permanently disables itself
- Admins manage the roster (`/manage-users.html`, `/create-account.html`): create accounts, change roles, force-reset a forgotten password, deactivate/reactivate an account
- Deactivation takes effect immediately — even an already-open session gets logged out, not just blocked on the next login attempt. An admin can't deactivate their own account.
- Anyone can change their own password (`/change-password.html`); new/reset accounts must change their password on next login
- Real audit trail by design — actions are tied to a named account, not a shared PIN

**Customer accounts**
- Separate from staff accounts — email/password identity only, no `admin`/`employee` role, no order history yet
- Self-service registration (`/signup`), login (`/account-login`), password change and reset (`/forgot-password.html` → `/reset-password.html`, 1-hour expiring token)
- Email verification link on signup — **not actually delivered yet** (see gaps below), logged server-side instead
- Self-service account deactivation (`/my-account.html`) — immediately ends the session and blocks future login (password or OAuth)

**OAuth sign-in (Google + Apple)**
- Customers: "Continue with Google/Apple" on `/signup` and `/account-login` — self-serve, first sign-in creates an account (or links to an existing email/password account with a matching verified email)
- Staff: link-only, not self-serve — an employee must already have a username/password account, log in, then link Google/Apple from `/account.html`. Only after linking does "Sign in with Google/Apple" work on `/login`. (Prevents anyone with a Google account from getting staff access.)
- **Neither provider is actually configured yet** — see [Setting up Google/Apple Sign-In](#setting-up-googleapple-sign-in). The buttons are live in the UI but return a clear 503 until real credentials are set.

**SEO & technical**
- Per-page Open Graph / Twitter Card tags
- schema.org `Restaurant` JSON-LD on the homepage
- `sitemap.xml` and `robots.txt`
- Cache-Control revalidation on every response (avoids stale-cache bugs after a deploy)
- Automated test suite (`server/Tests/AppTests`, 42 tests) — loyalty punch/redeem math, staff and customer auth (including deactivation and OAuth linking), menu backward-compat decoding, and route-level permission boundaries. Run with `swift test` from `server/`.
- Self-hosted analytics (`/analytics.html`, admin only) — pageview counts by page and by day, no cookies or third-party tracking script. Server-side only, bounded to 120 days of aggregated (not raw per-visit) data.
- Uploaded photos (menu editor, customer bonus-claim photos) are auto-resized (1600px long-edge cap) and re-compressed via ImageMagick, run off the event loop so it doesn't stall other requests. Fails closed — if optimization fails for any reason, the original upload is kept as-is rather than blocking the upload.

## Known gaps / not yet implemented

Pulled from `docs/feature-roadmap.md`'s original audit, updated for what's
actually shipped as of this README. Not in priority order.

**Trust & findability**
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
- Uptime/error monitoring/alerting
- Formal Lighthouse performance pass

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

## Setting up Google/Apple Sign-In

Both are built and live in the UI (buttons on `/signup`, `/account-login`,
`/login`, `/account.html`) but return a `503` until real credentials are set
as Container App secrets/env vars.

**Google** (free, ~10 minutes):
1. In [Google Cloud Console](https://console.cloud.google.com/), create (or reuse) a project → **APIs & Services → Credentials**.
2. Configure the OAuth consent screen if you haven't already (External, basic app info — no verification needed for a small user base).
3. Create an **OAuth client ID** of type "Web application."
4. Add these to **Authorized redirect URIs**:
   - `https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io/auth/google/customer/callback`
   - `https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io/auth/google/staff/callback`
   - (optionally) `http://localhost:8080/auth/google/customer/callback` and `.../staff/callback` for local dev
5. Set `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` on the Container App.

**Apple** (has a real cost — $99/year Apple Developer Program):
1. Enroll at [developer.apple.com/programs](https://developer.apple.com/programs/) if you haven't already.
2. **Certificates, IDs & Profiles → Identifiers**: register an App ID (if you don't have one) with "Sign in with Apple" enabled, then register a **Services ID** (e.g. `com.ohanabelltown.web`) — this is your `APPLE_OAUTH_CLIENT_ID`. Configure it with the same redirect URIs as the Google step above (`/auth/apple/customer/callback`, `/auth/apple/staff/callback`), and register the site domain.
3. **Keys**: create a new key with "Sign in with Apple" enabled, associated with that Services ID. Download the `.p8` file **immediately** — Apple only lets you download it once. Note the Key ID shown on screen.
4. You'll also need your **Team ID** (top-right of the developer portal, or Membership page).
5. Set on the Container App: `APPLE_OAUTH_CLIENT_ID` (the Services ID), `APPLE_OAUTH_TEAM_ID`, `APPLE_OAUTH_KEY_ID`, and `APPLE_OAUTH_PRIVATE_KEY` (the full contents of the `.p8` file, including the `-----BEGIN/END PRIVATE KEY-----` lines).

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
- `docs/page-inventory.md`, `docs/migration-plan.md`, `docs/ohana-project-plan.md` — early planning docs from the static-site-capture phase, kept for history
- `reference-site/` — the original Weebly site mirror this project was migrated from
