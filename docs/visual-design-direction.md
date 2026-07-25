# Ohana Belltown — Visual Design Direction

Ohana's real mark is the neon sign out front — magenta and violet against a
dark Belltown night — next to the black-and-white mon crest logo. The site's
visual identity is built from that instead of a stock "modern restaurant"
template, refreshed with a bolder type pairing and a deeper, more deliberate
purple.

## Palette

| Name | Hex | Usage |
|---|---|---|
| Neon Pink | `#FF2F8F` | Primary accent — buttons, links, category dividers, gradient starts. Lifted directly from the storefront sign. |
| Husky Purple | `#4B2E83` | Secondary accent — University of Washington's official purple, a nod to Yosh (a UW grad). Pairs with pink in the brand gradient, borders, hover states. |
| Purple Bright | `#8F5FD6` | Lighter companion to Husky Purple for gradient text and glow effects on dark hero photos, closer in tone to the sign's actual neon glow. |
| Sunset Gold | `#D9860F` / bright `#F2A93C` | Tertiary accent — prices, "popular"/"new" tags |
| Belltown Ink | `#14101C` | Dark ground for hero banners, header/nav, footer |
| Warm Paper | `#FBF6EE` | Light ground for long-form content (menu, about, contact) |

`--pink-text` (`#DC0066`) and `--gold-text` (`#A0630B`) are darkened variants
of pink/gold used specifically for *text* on light backgrounds — the
brand colors above read at roughly 3:1 against white/paper, which fails
WCAG AA for text (4.5:1 required). Husky Purple already clears 4.5:1 on its
own, so it needs no separate text variant. Backgrounds, gradients, and
borders keep using the un-darkened brand colors, since that contrast rule
doesn't apply there.

Long menu-scanning pages stay on the warm paper ground for legibility — the
neon treatment is reserved for hero banners, buttons, and dividers, so
scanning a 118-item menu doesn't mean reading white text on black for ten
minutes.

## Typography

| Role | Stack | Notes |
|---|---|---|
| Display (page `h1`s, brand wordmark) | `'Bungee', -apple-system, "SF Pro Display", "Segoe UI", system-ui, sans-serif` | A bold, blocky, vintage-sign display face — used sparingly, only for hero titles and the header logotype, so it reads as a signature rather than wallpaper |
| Body & UI (paragraphs, nav, buttons, labels, tags) | `'Nunito Sans', -apple-system, "SF Pro Display", "Segoe UI", system-ui, sans-serif` | Warm, rounded, highly legible sans — replaced the previous Georgia-serif body treatment for a more modern feel while keeping things approachable rather than corporate |

Both are loaded from Google Fonts via a single `@import` at the top of
`style.css`, so every page picks them up automatically.

## Layout Principles

- Dark neon-gradient hero banners on the homepage and section pages, using
  the actual logo and photography, not stock imagery.
- A subtle wave-shaped bottom edge on every hero banner (a CSS mask, filled
  with the page's paper color) — a quiet, recurring "ocean" signature that
  ties the tiki-bar-by-the-water setting into the layout itself without
  relying on an illustrated graphic.
- Warm paper background for menu, about, contact, and other text-heavy pages
  so long lists of dishes stay easy to scan.
- Gold reserved for prices and short callout tags so it reads as a signal,
  not a third competing brand color.
- Category dividers and buttons use the pink-to-purple gradient as the one
  bold, recognizable brand element — everything else stays quiet around it.

## Rationale

The pink-to-purple gradient is lifted directly from the storefront sign, so
the site reads as *this specific restaurant* at a glance, not a template —
and the purple specifically nods to Yosh's UW ties rather than being a
generic "AI gradient" violet. That's the difference between "a modern
restaurant website" and "Ohana Belltown's website" — the goal is the latter.
