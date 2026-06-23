#!/usr/bin/env bash
set -euo pipefail

# Run this from the repo root: Menu/
# It reorganizes the mirrored Weebly snapshot into a cleaner reference-site structure.

ROOT="$(pwd)"
SOURCE="static-snapshot/www.ohanasushigrill.com"
REFERENCE="reference-site"
RAW_DEST="$REFERENCE/original/raw-wget-files"

if [ ! -d "$SOURCE" ]; then
  echo "ERROR: Expected source folder not found: $SOURCE"
  echo "Run this script from the Menu repo root."
  exit 1
fi

if [ -d "$REFERENCE" ]; then
  BACKUP="$REFERENCE.backup.$(date +%Y%m%d-%H%M%S)"
  echo "Existing $REFERENCE found. Moving it to $BACKUP"
  mv "$REFERENCE" "$BACKUP"
fi

echo "Creating clean reference-site structure..."
mkdir -p \
  "$REFERENCE/pages" \
  "$REFERENCE/images/hero-images" \
  "$REFERENCE/images/content" \
  "$REFERENCE/images/logos" \
  "$REFERENCE/images/theme" \
  "$REFERENCE/pdfs" \
  "$REFERENCE/css" \
  "$REFERENCE/js" \
  "$REFERENCE/original"

# Preserve the fully working local snapshot exactly as-is.
echo "Copying raw working snapshot to $RAW_DEST..."
mkdir -p "$RAW_DEST"
cp -R "$SOURCE"/. "$RAW_DEST"/

# Copy HTML pages into reference-site/pages.
echo "Copying HTML pages..."
find "$SOURCE" -maxdepth 1 -type f -name "*.html" -exec cp {} "$REFERENCE/pages/" \;

# Copy PDFs.
echo "Copying PDFs..."
find "$SOURCE" -type f -iname "*.pdf" -exec cp {} "$REFERENCE/pdfs/" \;

# Copy CSS.
echo "Copying CSS..."
find "$SOURCE" -type f -iname "*.css" -exec cp {} "$REFERENCE/css/" \;

# Copy JS.
echo "Copying JavaScript..."
find "$SOURCE" -type f -iname "*.js" -exec cp {} "$REFERENCE/js/" \;

# Copy hero/background images.
echo "Copying hero images..."
if [ -d "$SOURCE/uploads/7/8/0/6/78067072/background-images" ]; then
  find "$SOURCE/uploads/7/8/0/6/78067072/background-images" -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) \
    -exec cp {} "$REFERENCE/images/hero-images/" \;
fi

# Copy logo files.
echo "Copying logo images..."
find "$SOURCE/uploads/7/8/0/6/78067072" -type f \
  \( -iname "*logo*.png" -o -iname "*logo*.jpg" -o -iname "*logo*.jpeg" -o -iname "*logo*.webp" \) \
  -exec cp {} "$REFERENCE/images/logos/" \; 2>/dev/null || true

# Copy other content images, excluding background-images.
echo "Copying content images..."
find "$SOURCE/uploads/7/8/0/6/78067072" -type f \
  \( -iname "*.jpg" -o -iname "*.jpg*" -o -iname "*.jpeg" -o -iname "*.jpeg*" -o -iname "*.png" -o -iname "*.png*" -o -iname "*.webp" -o -iname "*.webp*" -o -iname "*.gif" -o -iname "*.gif*" \) \
  ! -path "*/background-images/*" \
  -exec cp {} "$REFERENCE/images/content/" \; 2>/dev/null || true

# Copy theme images.
echo "Copying theme images..."
if [ -d "$SOURCE/files/theme/images" ]; then
  find "$SOURCE/files/theme/images" -type f -exec cp {} "$REFERENCE/images/theme/" \;
fi

# Create a simple inventory file.
echo "Creating inventory..."
cat > "$REFERENCE/README.md" <<'EOF'
# Ohana Reference Site

This folder contains the cleaned reference copy of the original Weebly site.

## Folders

- `pages/` - copied HTML pages from the original site
- `images/hero-images/` - page hero/background images
- `images/content/` - inline page images and food/content images
- `images/logos/` - logo assets
- `images/theme/` - Weebly theme images
- `pdfs/` - downloaded PDF files
- `css/` - copied stylesheet files
- `js/` - copied JavaScript files
- `original/raw-wget-files/` - full working local snapshot preserved exactly as captured

Use `original/raw-wget-files/` as the source of truth when checking how the old site behaved locally.
EOF

{
  echo "# Reference Site Inventory"
  echo
  echo "Generated: $(date)"
  echo
  echo "## Pages"
  find "$REFERENCE/pages" -type f | sort
  echo
  echo "## Images"
  find "$REFERENCE/images" -type f | sort
  echo
  echo "## PDFs"
  find "$REFERENCE/pdfs" -type f | sort
  echo
  echo "## CSS"
  find "$REFERENCE/css" -type f | sort
  echo
  echo "## JavaScript"
  find "$REFERENCE/js" -type f | sort
} > "$REFERENCE/inventory.md"

# Leave old static-snapshot in place for now; safer before first commit.
echo
echo "Done. New structure created at: $REFERENCE"
echo
echo "Next commands:"
echo "  tree -L 4 reference-site"
echo "  open reference-site/original/raw-wget-files/index.html"
echo
echo "After verifying everything, commit with:"
echo "  git add ."
echo "  git commit -m 'Organize Ohana reference site structure'"
