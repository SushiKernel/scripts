#!/bin/bash
set -e

SRC="$1"
DST="$2"
PREFIX="$3"

if [ -z "$SRC" ] || [ -z "$DST" ] || [ -z "$PREFIX" ]; then
    echo "Usage: $0 <src_dir> <dst_dir> <prefix>"
    exit 1
fi

mkdir -p "$DST"

# Copy .ko files
find "$SRC" -type f -name "*.ko" -exec cp {} "$DST" \;

# Copy metadata except modules.load (we regenerate)
for f in modules.alias modules.dep modules.softdep; do
    [ -f "$SRC/$f" ] && cp "$SRC/$f" "$DST/"
done

# Rewrite modules.dep
tmp="$DST/modules.dep.tmp"
> "$tmp"

while IFS= read -r line; do
    mod=$(echo "$line" | cut -d: -f1)
    deps=$(echo "$line" | cut -d: -f2-)

    mod_base=$(basename "$mod")
    new="$PREFIX/$mod_base"

    dep_out=""
    for d in $deps; do
        dep_out="$dep_out $PREFIX/$(basename "$d")"
    done

    echo "$new:$dep_out" >> "$tmp"
done < "$DST/modules.dep"

mv "$tmp" "$DST/modules.dep"

# Create modules.load
out="$DST/modules.load"
> "$out"

if [ -f "$SRC/modules.load" ]; then
    # Rewrite existing modules.load (basenames only)
    while IFS= read -r line; do
        base=$(basename "$line")
        echo "$base" >> "$out"
    done < "$SRC/modules.load"
elif [ -f "$SRC/modules.order" ]; then
    # Generate from modules.order
    while IFS= read -r line; do
        base=$(basename "$line")
        echo "$base" >> "$out"
    done < "$SRC/modules.order"
fi
