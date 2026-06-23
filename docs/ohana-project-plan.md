# Ohana Belltown Website Migration Project Plan

## Project Goal

Migrate the current Ohana Sushi Bar & Grill Weebly site into a modern, maintainable web application.

The immediate goal is to preserve the current site as a reference, then build a new menu-driven website where menu items, prices, descriptions, photos, availability, and specials can eventually be updated from a web form instead of editing static pages.

Current repository root:

```text
Menu/
```

Current branch:

```text
migration/react-cms
```

GitHub repository:

```text
https://github.com/ProDataMan/Ohana_Belltown.git
```

---

## Current Repository State

The existing Weebly site has been mirrored locally and reorganized into:

```text
Menu/
├── reference-site/
│   ├── pages/
│   ├── images/
│   ├── pdfs/
│   ├── css/
│   ├── js/
│   ├── original/
│   ├── README.md
│   └── inventory.md
├── docs/
├── scripts/
├── src/
└── README.md
```

The `reference-site/` folder is the preserved source material. Do not treat it as the future application. It exists so we can extract content, copy assets, compare layout, and verify migration accuracy.

---

## Existing Reference Pages

The current site has 8 HTML pages:

| Existing HTML File | Future Route | Purpose |
|---|---|---|
| `reference-site/pages/index.html` | `/` | Home page |
| `reference-site/pages/about-ohanas.html` | `/about` | Restaurant story |
| `reference-site/pages/menu.html` | `/menu` | Main food menu |
| `reference-site/pages/sushi.html` | `/sushi` or `/menu/sushi` | Sushi menu |
| `reference-site/pages/drinks.html` | `/drinks` or `/menu/drinks` | Drinks menu |
| `reference-site/pages/happy-hour.html` | `/happy-hour` | Happy hour menu |
| `reference-site/pages/local.html` | `/local` | Local/community page |
| `reference-site/pages/contact.html` | `/contact` | Address, map, contact info |

Recommended future route structure:

```text
/
 /about
 /menu
 /menu/sushi
 /menu/drinks
 /menu/happy-hour
 /local
 /contact
 /admin
```

---

## Important Migration Decision

Do not manually rebuild the menu as static HTML.

Instead, extract menu content into structured data first. The future React frontend should render menu pages from JSON or an API.

Initial data target:

```text
database/menu.json
```

Future backend target:

```text
backend/
```

Future database target:

```text
PostgreSQL, SQLite, or Supabase
```

---

## Proposed Final Project Structure

Build toward this structure:

```text
Menu/
├── reference-site/
│   ├── pages/
│   ├── images/
│   │   ├── content/
│   │   ├── hero-images/
│   │   ├── logos/
│   │   └── theme/
│   ├── pdfs/
│   ├── css/
│   ├── js/
│   └── original/
│       └── raw-wget-files/
│
├── frontend/
│   ├── public/
│   │   ├── images/
│   │   └── pdfs/
│   ├── src/
│   │   ├── assets/
│   │   ├── components/
│   │   ├── data/
│   │   ├── layouts/
│   │   ├── pages/
│   │   ├── routes/
│   │   ├── services/
│   │   └── styles/
│   ├── package.json
│   └── vite.config.js
│
├── backend/
│   ├── app/
│   │   ├── main.py
│   │   ├── models/
│   │   ├── routes/
│   │   ├── schemas/
│   │   └── services/
│   ├── uploads/
│   ├── requirements.txt
│   └── README.md
│
├── database/
│   ├── menu.json
│   ├── schema.sql
│   └── seed-data.sql
│
├── docs/
│   ├── migration-plan.md
│   ├── content-audit.md
│   ├── menu-data-model.md
│   └── deployment-plan.md
│
├── scripts/
│   ├── extract-menu.py
│   ├── audit-assets.py
│   └── mirror-current-site.sh
│
└── README.md
```

---

## Milestone 1: Freeze and Verify the Reference Site

### Goal

Make sure the current locally running reference site is preserved before any new application work begins.

### Tasks

- Verify `reference-site/pages/index.html` opens locally.
- Verify `reference-site/pages/about-ohanas.html` opens locally.
- Verify hero images display.
- Verify logo and in-page images display.
- Verify `reference-site/pdfs/catering_032725.pdf` exists.
- Verify `reference-site/original/raw-wget-files/` contains the raw mirror.

### Commands

```bash
git status
git add .
git commit -m "Organize Ohana reference site assets"
git push
```

### Acceptance Criteria

- Working tree is clean.
- Branch is pushed to GitHub.
- `reference-site/` contains both cleaned files and original raw mirror.
- No work is done directly inside `reference-site/original/raw-wget-files/`.

---

## Milestone 2: Create Content Audit

### Goal

Document what content exists on each current page before rebuilding anything.

### Output File

```text
docs/content-audit.md
```

### Tasks

Create a page-by-page audit with:

- Page title
- Current file
- Future route
- Hero image used
- Main content sections
- Images used
- External widgets
- Migration notes

### Suggested Content Audit Format

```markdown
# Content Audit

## Home

- Source: `reference-site/pages/index.html`
- Future route: `/`
- Hero image: `reference-site/images/hero-images/1739743111.jpg`
- Content images:
  - `reference-site/images/content/img-9531-3.jpg`
  - `reference-site/images/content/pngguru-com.png`
- External widgets:
  - ChowNow ordering script
- Migration notes:
  - Replace Weebly layout with React components.
  - Keep order online button linking to ChowNow.

## About Ohana's

- Source: `reference-site/pages/about-ohanas.html`
- Future route: `/about`
- Hero image: `reference-site/images/hero-images/1739743111.jpg`
- Content images:
  - `reference-site/images/content/11150804-10153515950889245-4886850445648827573-n.jpg`
```

### Acceptance Criteria

- Every page is listed.
- Every image is identified.
- External dependencies are documented.
- Pages that can be merged or simplified are called out.

---

## Milestone 3: Extract Menu Content into JSON

### Goal

Convert the Weebly menu HTML into structured menu data.

### Initial Input Files

```text
reference-site/pages/menu.html
reference-site/pages/sushi.html
reference-site/pages/drinks.html
reference-site/pages/happy-hour.html
```

### Output File

```text
database/menu.json
```

### Proposed JSON Shape

```json
{
  "restaurant": {
    "name": "Ohana Sushi Bar & Grill",
    "location": "Belltown, Seattle"
  },
  "categories": [
    {
      "id": "pupus",
      "name": "Pupus",
      "description": "Appetizers",
      "sortOrder": 10,
      "items": [
        {
          "id": "hawaiian-style-poke",
          "name": "Hawaiian Style Poke",
          "description": "Cubed fresh tuna and salmon, sliced onions tossed with sesame oil, soy sauce, red pepper flakes and green onions. Served with homemade taro chips.",
          "price": null,
          "image": null,
          "tags": [],
          "available": true,
          "featured": false
        }
      ]
    }
  ]
}
```

### Script to Create

```text
scripts/extract-menu.py
```

### Script Responsibilities

- Read each source HTML page.
- Extract section headings.
- Extract item names from `<strong>` tags.
- Extract descriptions following each item name.
- Normalize whitespace.
- Remove Weebly-specific markup.
- Generate stable URL-friendly IDs.
- Write `database/menu.json`.
- Preserve `price: null` where no price exists.
- Preserve `image: null` until photos are added.

### Suggested Dependencies

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install beautifulsoup4 lxml
```

### Acceptance Criteria

- `database/menu.json` is valid JSON.
- Menu items from `menu.html` are represented.
- Sushi, drinks, and happy hour items are included or marked for manual review.
- Prices are nullable.
- No Weebly HTML remains in descriptions.

---

## Milestone 4: Create Menu Data Model Documentation

### Goal

Document the data model before building the frontend or backend.

### Output File

```text
docs/menu-data-model.md
```

### Entities

#### Category

| Field | Type | Notes |
|---|---|---|
| `id` | string | URL-friendly unique ID |
| `name` | string | Display name |
| `description` | string/null | Optional |
| `sortOrder` | number | Controls display order |
| `items` | array | Menu items |

#### Menu Item

| Field | Type | Notes |
|---|---|---|
| `id` | string | URL-friendly unique ID |
| `name` | string | Display name |
| `description` | string/null | Customer-facing description |
| `price` | number/null | Nullable during migration |
| `image` | string/null | Relative image path |
| `tags` | array | Example: spicy, vegetarian, gluten-free |
| `available` | boolean | Allows item hiding |
| `featured` | boolean | For homepage/menu highlights |

### Future Admin Fields

- Name
- Description
- Category
- Price
- Photo
- Availability
- Featured
- Tags
- Sort order

### Acceptance Criteria

- Data model supports all existing menu pages.
- Data model supports future webform editing.
- Data model supports photos per menu item.
- Data model supports hiding unavailable items.

---

## Milestone 5: Create React Frontend

### Goal

Create a Vite React app that renders the new site.

### Commands

```bash
npm create vite@latest frontend -- --template react
cd frontend
npm install
npm run dev
```

### Required Packages

```bash
npm install react-router-dom
```

Optional later:

```bash
npm install axios
npm install lucide-react
```

### Frontend Folder Structure

```text
frontend/src/
├── components/
│   ├── Header.jsx
│   ├── Footer.jsx
│   ├── Hero.jsx
│   ├── MenuCategory.jsx
│   ├── MenuItemCard.jsx
│   └── OrderOnlineButton.jsx
├── pages/
│   ├── HomePage.jsx
│   ├── AboutPage.jsx
│   ├── MenuPage.jsx
│   ├── LocalPage.jsx
│   ├── ContactPage.jsx
│   └── AdminPage.jsx
├── data/
│   └── menu.json
├── layouts/
│   └── SiteLayout.jsx
├── styles/
│   └── site.css
├── App.jsx
└── main.jsx
```

### Initial Routes

```text
/               HomePage
/about          AboutPage
/menu           MenuPage
/menu/sushi     MenuPage filtered to Sushi
/menu/drinks    MenuPage filtered to Drinks
/happy-hour     MenuPage filtered to Happy Hour
/local          LocalPage
/contact        ContactPage
/admin          AdminPage placeholder
```

### Acceptance Criteria

- Vite app runs locally.
- Navigation works.
- Home page renders.
- About page renders.
- Menu page renders from `menu.json`.
- No page depends on Weebly scripts.

---

## Milestone 6: Copy Assets into the React App

### Goal

Move only the assets needed by the new React frontend into `frontend/public`.

### Suggested Structure

```text
frontend/public/
├── images/
│   ├── hero/
│   ├── content/
│   ├── logos/
│   └── menu/
└── pdfs/
```

### Tasks

Copy selected assets:

```bash
mkdir -p frontend/public/images/hero
mkdir -p frontend/public/images/content
mkdir -p frontend/public/images/logos
mkdir -p frontend/public/pdfs
```

Copy:

```text
reference-site/images/hero-images/*
reference-site/images/logos/ohana-logo.png
reference-site/images/content/*
reference-site/pdfs/catering_032725.pdf
```

### Acceptance Criteria

- React app uses assets from `frontend/public`.
- React app does not reference `reference-site/` directly.
- Asset filenames are clean and URL-friendly.
- Duplicate `%3F...` filenames are not used in the React app.

---

## Milestone 7: Build Public Menu Page

### Goal

Create a customer-friendly menu page rendered from structured data.

### Components

#### `MenuPage.jsx`

Responsibilities:

- Load `menu.json`.
- Render category navigation.
- Render menu categories.
- Render menu items.
- Support optional filtering by route or query string.

#### `MenuCategory.jsx`

Responsibilities:

- Display category name.
- Display description if available.
- Render item cards.

#### `MenuItemCard.jsx`

Responsibilities:

- Display item image if available.
- Display name.
- Display description.
- Display price if available.
- Display tags if available.
- Hide unavailable items.

### Display Rules

- If `price` is `null`, hide price.
- If `image` is `null`, use a tasteful placeholder or no image.
- If `available` is `false`, hide from public menu or show as unavailable based on config.
- Featured items can appear on the homepage.

### Acceptance Criteria

- Main menu renders from JSON.
- Sushi menu renders from same JSON.
- Drinks menu renders from same JSON.
- Happy hour renders from same JSON.
- Missing prices do not break layout.
- Missing photos do not break layout.

---

## Milestone 8: Build Page Shell and Branding

### Goal

Replace Weebly layout with a clean restaurant site layout.

### Components

#### Header

- Logo
- Navigation
- Order Online button
- Mobile menu

#### Footer

- Restaurant name
- Address
- Phone
- Hours
- Social links
- Copyright

#### Hero

- Page title
- Background image
- Optional subtitle
- Optional call-to-action button

### Suggested Brand Direction

- Keep Hawaiian/sushi personality.
- Use large food photography.
- Keep pages mobile-first.
- Make menu easy to scan.
- Make ordering button highly visible.

### Acceptance Criteria

- Site looks acceptable on mobile.
- Navigation works on desktop and mobile.
- Hero images render.
- Order Online link opens ChowNow in a new tab.

---

## Milestone 9: Create Backend Skeleton

### Goal

Create the future API structure, even if the first version uses JSON.

### Recommended Backend

FastAPI.

### Commands

```bash
mkdir -p backend/app/routes backend/app/models backend/app/schemas backend/app/services backend/uploads
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install fastapi uvicorn python-multipart
pip freeze > requirements.txt
```

### Files

```text
backend/app/main.py
backend/app/routes/menu.py
backend/app/schemas/menu.py
backend/README.md
```

### Initial API Endpoints

```text
GET    /api/menu
GET    /api/menu/categories
GET    /api/menu/items
GET    /api/menu/items/{id}
POST   /api/menu/items
PUT    /api/menu/items/{id}
DELETE /api/menu/items/{id}
POST   /api/menu/items/{id}/image
```

### Acceptance Criteria

- FastAPI starts locally.
- `GET /api/menu` returns menu JSON.
- CORS allows local React development.
- Backend can later replace static JSON file.

---

## Milestone 10: Admin Webform

### Goal

Create a simple admin page for editing menu data.

### Initial Version

The first admin version can be local/dev only.

Route:

```text
/admin
```

Features:

- View menu items.
- Add menu item.
- Edit menu item.
- Change category.
- Set price.
- Set availability.
- Mark featured.
- Upload or select image.

### Future Authentication

Do not overbuild authentication at first. Add later:

- Simple password auth
- Auth0
- Firebase Auth
- Supabase Auth
- Basic admin token

### Acceptance Criteria

- Admin page exists.
- Form can edit local state.
- Later milestone persists changes to backend.
- Form fields match data model.

---

## Milestone 11: Deployment Plan

### Goal

Decide deployment target after the React frontend and menu data are working locally.

### Options

#### Simple Static Deployment

Good for first public release.

- GitHub Pages
- Netlify
- Vercel
- Cloudflare Pages

Pros:

- Fast
- Cheap
- Easy

Cons:

- Admin form needs separate backend or manual JSON update.

#### Full App Deployment

Good for CMS/admin upload features.

- AWS Lightsail
- EC2
- Render
- Railway
- Fly.io
- DigitalOcean

Pros:

- Supports backend and uploads
- More flexible

Cons:

- More setup and maintenance

### Recommended Path

1. Build React frontend with JSON.
2. Deploy static version.
3. Add FastAPI backend.
4. Add admin form.
5. Move to full app hosting when admin editing is required.

---

## Milestone 12: Git Workflow

### Branches

Current working branch:

```text
migration/react-cms
```

Suggested future branches:

```text
feature/content-audit
feature/menu-extraction
feature/react-shell
feature/menu-page
feature/admin-form
feature/backend-api
feature/deployment
```

### Commit Style

Use small commits:

```bash
git add .
git commit -m "Add menu extraction script"
git push
```

Good commit examples:

```text
Add content audit document
Create menu JSON data model
Extract main menu items from Weebly HTML
Create Vite React frontend
Add shared site layout components
Render menu from JSON
Add admin menu item form
Create FastAPI menu endpoint
```

---

## Copilot Working Instructions

Use these prompts in VS Code Copilot Chat.

### Prompt 1: Content Audit

```text
Create docs/content-audit.md by reviewing the HTML files in reference-site/pages. For each page, list the source file, future route, title, hero image, content images, external widgets, and migration notes. Do not modify the reference-site files.
```

### Prompt 2: Menu Extraction Script

```text
Create scripts/extract-menu.py. It should parse reference-site/pages/menu.html, sushi.html, drinks.html, and happy-hour.html using BeautifulSoup. Extract headings as categories and strong tags as menu item names. Capture the following text as descriptions until the next strong tag or heading. Write valid JSON to database/menu.json using the data model described in docs/menu-data-model.md.
```

### Prompt 3: Menu Data Model

```text
Create docs/menu-data-model.md documenting the menu JSON structure, category fields, menu item fields, admin form fields, and future database tables. Include examples using Ohana menu items from reference-site/pages/menu.html.
```

### Prompt 4: React Frontend

```text
Create a Vite React app in the frontend folder. Add react-router-dom. Build a basic site layout with Header, Footer, Hero, and pages for Home, About, Menu, Local, Contact, and Admin. Use the existing route plan in docs/project-plan.md.
```

### Prompt 5: Menu Page

```text
Build frontend/src/pages/MenuPage.jsx and related components to render menu data from frontend/src/data/menu.json. Group items by category. Display item name, description, optional price, optional image, tags, and availability.
```

### Prompt 6: Asset Copy

```text
Copy selected assets from reference-site/images and reference-site/pdfs into frontend/public. Use clean filenames only. Update React components so they reference frontend/public assets, not reference-site paths.
```

### Prompt 7: Backend Skeleton

```text
Create a FastAPI backend skeleton in backend. Add app/main.py, app/routes/menu.py, app/schemas/menu.py, and requirements.txt. Implement GET /api/menu that returns database/menu.json.
```

---

## Definition of Done for First Release

The first releasable version should have:

- Modern React frontend.
- Home page.
- About page.
- Menu page generated from structured data.
- Contact page.
- Working mobile navigation.
- Order Online link to ChowNow.
- Existing images reused.
- Catering PDF linked.
- No dependency on Weebly scripts.
- Project pushed to GitHub.

Admin editing can be a second release if needed.

---

## Immediate Next Steps

1. Commit the current organized reference site.
2. Create `docs/project-plan.md` from this file.
3. Create `docs/content-audit.md`.
4. Create `docs/menu-data-model.md`.
5. Create `scripts/extract-menu.py`.
6. Generate `database/menu.json`.
7. Create the Vite React frontend.
8. Render the menu from JSON.
