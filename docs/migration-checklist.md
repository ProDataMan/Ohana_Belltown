```markdown
# Migration Checklist

This checklist summarizes actionable steps from the migration plan and acceptance criteria.

## Phase 1 — Static snapshot
- Run: `bash scripts/mirror-current-site.sh` (creates `static-snapshot/`)
- Verify: open `static-snapshot/www.ohanasushigrill.com` locally with a simple server.
- Commit snapshot on a branch: `migration/static-site-snapshot`.

## Phase 2 — Content audit
- Produce `docs/content-audit.md` listing each page, images, external widgets, and migration notes.
- Verify `reference-site/` contains the original mirror and the cleaned reference files.

## Phase 3 — Extract menu into JSON
- Run: `python3 scripts/extract-menu.py` (creates `database/menu.json`).
- Acceptance: JSON is valid, items represented, prices nullable, descriptions cleaned.

## Phase 4 — Static rebuild + Admin
- Build React frontend to read `database/menu.json`.
- Add admin route skeleton at `frontend/admin/` to later implement CRUD and image uploads.

## Phase 5 — API & DB
- Migrate from file-based JSON to a backend API and database (Postgres/SQLite/Supabase).

## Verification & Deploy
- Preserve legacy `.html` URLs with redirects or aliases.
- Verify PDF links (e.g. `catering_032725.pdf`) remain reachable or are redirected.

## Notes
- See `docs/migration-plan.md` and `docs/ohana-project-plan.md` for full context and data model.
```
