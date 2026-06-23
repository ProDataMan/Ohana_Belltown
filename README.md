# Ohana Sushi Grill Site Migration Starter

This repo starter is intended to capture the existing Weebly/static site first, then evolve it into a new database-driven menu site.

## Current public pages found

- `/` Home
- `/about-ohanas.html`
- `/menu.html`
- `/sushi.html`
- `/happy-hour.html`
- `/drinks.html`
- `/local.html`
- `/contact.html`
- `/catering.html`
- `/uploads/7/8/0/6/78067072/catering_032725.pdf`

## Suggested branch workflow

```bash
git checkout -b migration/static-site-snapshot
git add .
git commit -m "Add static snapshot tooling for Ohana site migration"
git push -u origin migration/static-site-snapshot
```

After running the mirror script and verifying the pages locally:

```bash
git add static-snapshot docs
git commit -m "Capture current Ohana static site"
git push
```

## Run the static capture

From the repo root:

```bash
bash scripts/mirror-current-site.sh
```

Then test locally:

```bash
python3 -m http.server 8080 --directory static-snapshot/www.ohanasushigrill.com
```

Open:

```text
http://localhost:8080
```

## Next migration phases

1. Capture current site exactly.
2. Convert menu content into structured JSON.
3. Build new responsive menu pages with photos.
4. Add admin webform for menu updates.
5. Replace JSON with database-backed API.
6. Deploy on new hosting while preserving the domain and SEO paths.
