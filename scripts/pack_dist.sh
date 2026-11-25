#!/usr/bin/env bash
set -euo pipefail

NOVEL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$NOVEL_ROOT/dist"
ASSETS_DIR="${1:-$NOVEL_ROOT/../novel-reader/app/src/main/assets/novels}"

mkdir -p "$DIST_DIR"

for book_dir in "$NOVEL_ROOT"/*/; do
    [ -d "$book_dir/chapters" ] || continue
    book_id="$(basename "$book_dir")"
    out_zip="$DIST_DIR/${book_id}.zip"
    rm -f "$out_zip"

    echo "Packing $book_id -> $out_zip"
    (
        cd "$book_dir"
        files=("chapters")
        [ -f "book.yaml" ] && files+=("book.yaml")
        [ -f "book.yml" ] && files+=("book.yml")
        zip -rq "$out_zip" "${files[@]}"
    )
done

if [ -d "$ASSETS_DIR" ]; then
    echo "Syncing dist/*.zip -> $ASSETS_DIR"
    cp -f "$DIST_DIR"/*.zip "$ASSETS_DIR"/
fi

echo "Done!"
