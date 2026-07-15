# Ohana Belltown — Feature Roadmap

A feature audit and phased build plan for the site, covering what a modern
restaurant website is expected to have versus what Ohana already ships.

## Already Live

- Full real menu (118 items across 4 sections: Food Menu, Sushi, Drinks, Happy Hour)
- Staff editor (`/edit.html`) with photo upload per item
- Mobile nav + responsive layout
- ChowNow online ordering link
- Home, About, Local, Contact, Catering pages with real copy
- Legacy `.html` URL redirects (SEO-safe migration from the old Weebly site)
- HTTPS + persistent storage (Azure Files-backed menu data and photos)
- Catering PDF + gift card info

## Feature Audit

Priority: **Must** blocks trust or conversion today · **Should** meaningfully
grows the business · **Could** is a nice differentiator once the basics are done.

Effort: **S** small · **M** medium · **L** large (needs new infrastructure, e.g. a database).

### Foundation & Trust

| Feature | Description | Priority | Effort |
|---|---|---|---|
| SEO meta & Open Graph tags | Per-page title/description exist; missing Open Graph/Twitter card tags so shared links show a real preview image. | Must | S |
| Structured data (schema.org) | Restaurant + Menu + LocalBusiness JSON-LD so Google can show ratings, hours, and menu items directly in search results. | Must | M |
| Sitemap.xml & robots.txt | Helps search engines find every page, especially the section pages. | Must | S |
| Embedded map + directions | A real map on the Contact page, not just a "Get Directions" link. | Must | S |
| Google/Yelp reviews on-site | Social proof shoppers check before ordering. | Must | S |
| Accessibility pass (WCAG AA) | Alt text on food photos, focus states, color contrast check, semantic heading order. | Must | M |

### Discovery & Conversion

| Feature | Description | Priority | Effort |
|---|---|---|---|
| Menu search & filter | With 118 items across 4 sections, a search box and dietary/allergen filter chips turn "scroll forever" into "find it in 2 seconds." | Must | M |
| Dietary & allergen tags | Small tags per item (GF, V, Spicy); the data model already supports a tags array. | Should | M |
| Online reservations | Embed OpenTable/Resy/Tock, or a simple "call to reserve" CTA. | Should | S |
| Online gift card purchase | Currently "call us and we'll mail one" — a Toast/Square widget lets people buy one anytime. | Should | M |
| Events & specials calendar | Live Hawaiian/Reggae music and karaoke nights get a reason to check back. | Should | M |
| Photo gallery | Food + ambiance + event photos, reusing the existing upload pipeline. | Could | M |

### Engagement & Retention

| Feature | Description | Priority | Effort |
|---|---|---|---|
| Email/SMS signup | Capture contacts for a monthly specials email. | Should | S |
| Loyalty program | Points or punch-card rewards. Needs real user accounts and a database. | Could | L |
| User profiles & order history | Foundation for loyalty and "reorder your last meal." Needs auth + a real database (the free Azure SQL Database is sitting unused and could serve this). | Could | L |
| Reorder your last meal | One-tap repeat of a saved order into ChowNow. Depends on user profiles + order history. | Could | M |
| Delivery within 1 mile | Native delivery with a radius check, instead of relying only on ChowNow's delivery partners. | Could | L |

### Technical Excellence

| Feature | Description | Priority | Effort |
|---|---|---|---|
| Image optimization | Auto-resize/compress uploaded photos to WebP so pages stay fast as more photos are added. | Should | M |
| Analytics | Privacy-friendly analytics (Plausible or GA4) to see which menu pages/items get looked at. | Should | S |
| Performance budget | Lighthouse score check as part of the redesign. | Should | S |
| Uptime/error monitoring | A basic alert if the site or `/api/menu` goes down. | Could | S |

### Admin & Operations

| Feature | Description | Priority | Effort |
|---|---|---|---|
| Daily specials toggle | Mark an item as "today's special" so it surfaces on the homepage automatically. | Should | S |
| Availability toggle per item | 86 an item (sold out, seasonal) without deleting it from the menu. | Should | S |
| Multi-staff editor accounts | `/edit.html` intentionally has no login today. Named logins add accountability if more than one person edits regularly. | Could | M |

## Implementation Roadmap

Four phases, each buildable on top of what's already live. Numbered because
the order matters — SEO plumbing and the visual refresh both pay off more once
they're in place before the engagement features launch.

### Phase 1 — Trust & Findability
*1–2 weeks · no visual changes*

- Open Graph tags + schema.org Restaurant/Menu markup
- Sitemap.xml, robots.txt
- Embedded map on Contact
- Google/Yelp review strip
- Accessibility pass (alt text, focus states, contrast)

### Phase 2 — Visual Refresh
*2–3 weeks · the redesign itself*

- New palette, type, and component styling (see `visual-design-direction.md`)
- Menu search + dietary/allergen filter chips
- Image optimization pipeline for uploaded photos
- Performance pass (Lighthouse budget) once the new styles land

### Phase 3 — Discovery & Engagement
*3–4 weeks · gives people a reason to come back*

- Email/SMS signup for specials
- Events & specials calendar (live music, karaoke nights)
- Online gift card purchase
- Reservations embed or CTA
- Photo gallery (reuses the existing upload pipeline)
- Daily specials + per-item availability toggle in the editor

### Phase 4 — Accounts & Loyalty
*The big one · needs a real database*

- User accounts (auth) — candidate to finally use the free Azure SQL Database
- Order history + "reorder your last meal"
- Loyalty points / rewards
- Delivery within 1 mile with address-radius checking

## Before Building

1. Confirm the phase order, or reprioritize (e.g. pull reservations earlier if that's a bigger pain point than SEO).
2. Sign off on the visual direction in `visual-design-direction.md`.
3. Flag any feature above that's a hard "no" so it's dropped instead of estimated.
