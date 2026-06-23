# Content Audit

This audit summarizes each page in the preserved reference site and captures images, external widgets, and migration notes.

## Home
- Source: `reference-site/pages/index.html`
- Future route: `/`
- Hero image: `reference-site/uploads/7/8/0/6/78067072/background-images/1739743111.jpg` (set as header background)
- Content images:
  - `uploads/7/8/0/6/78067072/editor/ohana-logo.png`
  - `uploads/7/8/0/6/78067072/editor/img-9531-3.jpg`
  - `uploads/7/8/0/6/78067072/published/pngguru-com.png`
- External widgets / links:
  - Ordering links: `https://ordering.chownow.com/...`, `https://ohana-belltown.hrpos.heartland.us/`, `http://www.doordash.com`
  - Third-party CSS/JS served from `cdn2.editmysite.com` (Weebly CDN)
  - Buttons link to external ordering providers — keep or replace with unified ordering integration.
- Migration notes:
  - Keep the order-online links but consider centralizing into a configuration.
  - Hero background and logo images should be migrated into `frontend/public/images/` and referenced by new pages.

## About Ohana's
- Source: `reference-site/pages/about-ohanas.html`
- Future route: `/about`
- Hero image: `reference-site/uploads/7/8/0/6/78067072/background-images/1739743111.jpg`
- Content images:
  - `uploads/7/8/0/6/78067072/editor/11150804-10153515950889245-4886850445648827573-n.jpg`
- External widgets / links:
  - External ordering link in nav (ChowNow)
- Migration notes:
  - Preserve founder copy and photo; convert to React component with CMS-driven image field.
  - Remove Weebly inline styling and CDN references.

## Menu
- Source: `reference-site/pages/menu.html`
- Future route: `/menu`
- Hero image: `reference-site/uploads/7/8/0/6/78067072/background-images/1246011808.jpg`
- Content images: none directly embedded (background only)
- External widgets / links:
  - None explicit; menu is static HTML content.
- Migration notes:
  - Primary source to extract structured menu data. Use `scripts/extract-menu.py` to generate `database/menu.json` and manually review for categories, prices, and images.
  - Many menu items are marked with `<strong>` tags — extractor uses that heuristic.

## Sushi
- Source: `reference-site/pages/sushi.html`
- Future route: `/menu/sushi` or `/sushi`
- Hero image: `reference-site/uploads/7/8/0/6/78067072/background-images/1739743111.jpg`
- Content images: none embedded other than shared hero/background
- External widgets: none
- Migration notes:
  - Treat as a menu subcategory. Extract items into JSON under a `sushi` category.

## Drinks
- Source: `reference-site/pages/drinks.html`
- Future route: `/menu/drinks` or `/drinks`
- Hero image: `reference-site/uploads/7/8/0/6/78067072/background-images/1739743111.jpg`
- Content images: none embedded
- External widgets: none
- Migration notes:
  - Extract drinks into a `drinks` category in `database/menu.json` (prices not present).

## Happy Hour
- Source: `reference-site/pages/happy-hour.html`
- Future route: `/happy-hour`
- Hero image: `reference-site/uploads/7/8/0/6/78067072/background-images/87621964.png`
- Content images: none embedded
- External widgets: none
- Migration notes:
  - Extract happy-hour items and any special copy into the data model; add scheduling metadata in future (e.g., start/end times) if desired.

## Local
- Source: `reference-site/pages/local.html`
- Future route: `/local`
- Hero image: `reference-site/uploads/7/8/0/6/78067072/background-images/1955350441.jpg`
- Content images:
  - `uploads/7/8/0/6/78067072/screen-shot-2018-08-18-at-2-42-06-pm_1_orig.png`
  - `uploads/7/8/0/6/78067072/img-3270_orig.jpg`
  - `uploads/7/8/0/6/78067072/img-2307_orig.jpg`
- External widgets: none
- Migration notes:
  - Community content; move into a simple static page with image gallery component.

## Contact
- Source: `reference-site/pages/contact.html`
- Future route: `/contact`
- Hero image: `reference-site/uploads/7/8/0/6/78067072/background-images/1684423476.jpg`
- Content images: none besides logo references
- External widgets / links:
  - Embedded Google Map iframe (via Weebly map generator).
  - Email addresses obfuscated via Cloudflare/Weebly script (`cdn-cgi/l/email-protection`).
  - Contact form posting to `http://www.weebly.com/weebly/apps/formSubmit.php` (Weebly form backend).
- Migration notes:
  - Replace Weebly contact form with a new backend endpoint or integrate with a managed form provider. Preserve map embedding or replace with a direct Google Maps embed.
  - Preserve phone numbers and catering PDF link.

## Catering PDF
- Source: `reference-site/pdfs/catering_032725.pdf`
- Existing URL: `/uploads/7/8/0/6/78067072/catering_032725.pdf`
- Migration notes:
  - Keep the PDF accessible at the same path or create a redirect to the new public assets path. Add a dedicated `/catering` page that links to the PDF and contains catering copy.

## Assets and SEO
- Images are stored under `reference-site/images/` and `uploads/...`. Copy relevant images into `frontend/public/images/` during migration.
- Preserve legacy `.html` URLs with redirects or route aliases to maintain SEO.

## Outstanding manual checks
- Verify imagery licensing and quality before publishing.
- Manually confirm any prices or menu details that were ambiguous in the extraction.
- Confirm what ordering integrations should be surfaced (ChowNow, Heartland, DoorDash).

---

If you'd like, I can:
- Copy referenced images into `frontend/public/images/` and create an `assets-map.json` to track provenance.
- Produce a simple React preview that reads `database/menu.json` and renders the menu categories.
