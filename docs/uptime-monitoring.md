# Uptime Monitoring Setup

The server already exposes a lightweight health-check endpoint that's
perfect for this:

- `https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io/healthz`
- Returns a plain `200 ok` with no auth required, no database/session
  overhead — safe to hit every few minutes forever.

This has to be set up through a third-party account (UptimeRobot), which
needs your email — not something that can be done for you from here.

## Steps (~5 minutes, free)

1. Go to [uptimerobot.com](https://uptimerobot.com/) and sign up for a free account.
2. Click **Add New Monitor**.
   - Monitor Type: **HTTP(s)**
   - Friendly Name: `Ohana Belltown`
   - URL: `https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io/healthz`
   - Monitoring Interval: 5 minutes (the free plan's fastest option)
3. Under **Alert Contacts**, make sure your email (and optionally phone via their SMS add-on) is selected so you actually get notified.
4. Save. UptimeRobot will now check the site every 5 minutes and email you the moment it goes down — and again when it recovers.

## Optional: a public status page

UptimeRobot's free tier also offers a simple public status page (toggle
"Public Status Page" for the monitor) if you ever want a `status.ohanabelltown.com`-style
link to share, though that's not necessary for basic monitoring.

## What this catches — and what it doesn't

- Catches: the container crashing, Azure having an outage, the app hanging.
- Doesn't catch: a specific broken *feature* (e.g. the loyalty punch button
  silently failing) — `/healthz` only proves the server is up and
  responding, not that every page/API works correctly. That would need a
  fuller synthetic-monitoring setup, which is real overkill for a
  single-location restaurant site.
