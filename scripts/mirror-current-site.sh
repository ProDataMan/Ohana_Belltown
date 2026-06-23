#!/usr/bin/env bash
set -euo pipefail

SITE="http://www.ohanasushigrill.com/"
OUT_DIR="static-snapshot"

mkdir -p "$OUT_DIR"

if ! command -v wget >/dev/null 2>&1; then
  echo "wget is required. On macOS: brew install wget"
  exit 1
fi

echo "Mirroring $SITE into $OUT_DIR ..."

wget \
  --mirror \
  --convert-links \
  --adjust-extension \
  --page-requisites \
  --no-parent \
  --domains www.ohanasushigrill.com,ohanasushigrill.com \
  --directory-prefix="$OUT_DIR" \
  "$SITE"

echo "Done. Snapshot is in $OUT_DIR/www.ohanasushigrill.com"
