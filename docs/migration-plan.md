# Ohana Menu Migration Plan

## Goal

Move from Weebly static page editing to a menu system where staff can update items, prices, photos, categories, and availability from a webform.

## Phase 1: Static snapshot

- Mirror the current public site.
- Keep the snapshot in `static-snapshot/`.
- Commit it on a new branch.
- Use it as the baseline for page content, photos, and SEO paths.

## Phase 2: Static rebuild

- Build modern static pages first.
- Use JSON for menu data.
- Render menu cards from data.
- Add photo placeholders where needed.

## Phase 3: Admin menu editor

- Add `/admin/menu`.
- Support item create/edit/delete.
- Add image upload.
- Add availability toggle.
- Export menu JSON first, then later save to database.

## Phase 4: API/database

Suggested tables:

- `menu_categories`
- `menu_items`
- `menu_item_images`
- `daily_specials`
- `admin_users`

## Phase 5: Deployment

- Preserve existing URLs with redirects.
- Move domain after staging review.
- Keep old PDF URLs working or redirect them.
