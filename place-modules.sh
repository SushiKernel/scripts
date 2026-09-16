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

VENDOR_RAMDISK_DIR="vendor_ramdisk/lib/modules"
RECOVERY_LIST="modules-load-recovery.txt"

echo ""
echo ">>> Creazione $VENDOR_RAMDISK_DIR ..."
mkdir -p "$VENDOR_RAMDISK_DIR"

if [ ! -f "$RECOVERY_LIST" ]; then
    echo "ERROR: $RECOVERY_LIST non trovato!"
    exit 1
fi

while IFS= read -r mod; do
    [ -z "$mod" ] && continue

    if [ -f "$SRC/$mod" ]; then
        cp -f "$SRC/$mod" "$VENDOR_RAMDISK_DIR/"
        echo "  [SRC] $mod"
    elif [ -f "$DST/$mod" ]; then
        cp -f "$DST/$mod" "$VENDOR_RAMDISK_DIR/"
        echo "  [DST] $mod"
    else
        echo "  WARN: $mod non trovato in SRC né in DST"
    fi
done < "$RECOVERY_LIST"
echo ""
echo ">>> Generazione metadata per $VENDOR_RAMDISK_DIR ..."

VR_PREFIX="/lib/modules"

# Lista basename per i confronti con alias/softdep
RECOVERY_BASENAMES="$(mktemp)"
while IFS= read -r mod; do
    [ -z "$mod" ] && continue
    echo "${mod%.ko}"
done < "$RECOVERY_LIST" > "$RECOVERY_BASENAMES"

# --- modules.load (VUOTO) ---
: > "$VENDOR_RAMDISK_DIR/modules.load"

# --- modules.load.recovery ---
: > "$VENDOR_RAMDISK_DIR/modules.load.recovery"

while IFS= read -r mod; do
    [ -z "$mod" ] && continue
    echo "$mod" >> "$VENDOR_RAMDISK_DIR/modules.load.recovery"
done < "$RECOVERY_LIST"

# --- modules.dep (modules.load.recovery order, path /lib/modules/) ---
: > "$VENDOR_RAMDISK_DIR/modules.dep"
while IFS= read -r mod; do
    [ -z "$mod" ] && continue

    # Cerca la riga per questo modulo nel vendor modules.dep
    line=$(grep -E "^/vendor/lib/modules/${mod}:" "$DST/modules.dep" 2>/dev/null || true)
    if [ -z "$line" ]; then
        line=$(grep -E "/${mod}:" "$DST/modules.dep" 2>/dev/null | head -n1 || true)
    fi

    if [ -n "$line" ]; then
        deps=$(echo "$line" | cut -d: -f2-)
        dep_out=""
        for d in $deps; do
            dep_base=$(basename "$d")
            if grep -qxF "$dep_base" "$RECOVERY_LIST"; then
                dep_out="$dep_out $VR_PREFIX/$dep_base"
            fi
        done
        echo "$VR_PREFIX/$mod:$dep_out" >> "$VENDOR_RAMDISK_DIR/modules.dep"
    else
        echo "  WARN: nessuna riga per $mod nel vendor modules.dep"
    fi
done < "$RECOVERY_LIST"

# --- modules.alias (stripped, with header) ---
: > "$VENDOR_RAMDISK_DIR/modules.alias"
if [ -f "$DST/modules.alias" ]; then
    echo "# Aliases extracted from modules themselves." >> "$VENDOR_RAMDISK_DIR/modules.alias"
    while IFS= read -r line; do
        case "$line" in
            \#*|"") continue ;;
        esac
        mod=$(echo "$line" | awk '{print $NF}')
        if grep -qxF "$mod" "$RECOVERY_BASENAMES"; then
            pattern=$(echo "$line" | awk '{print $2}')
            echo "alias $pattern $mod" >> "$VENDOR_RAMDISK_DIR/modules.alias"
        fi
    done < "$DST/modules.alias"
fi

# --- modules.softdep (Stripped) ---
: > "$VENDOR_RAMDISK_DIR/modules.softdep"
if [ -f "$DST/modules.softdep" ]; then
    echo "# Soft dependencies extracted from modules themselves." >> "$VENDOR_RAMDISK_DIR/modules.softdep"
    while IFS= read -r line; do
        case "$line" in
            \#*|"") continue ;;
        esac
        mod=$(echo "$line" | awk '{print $2}')
        if grep -qxF "$mod" "$RECOVERY_BASENAMES"; then
            new_line=$(echo "$line" | sed -E "s#(^|[[:space:]])[^[:space:]]*/([^/[:space:]]+\.ko)#\1$VR_PREFIX/\2#g")
            echo "$new_line" >> "$VENDOR_RAMDISK_DIR/modules.softdep"
        fi
    done < "$DST/modules.softdep"
fi

rm -f "$RECOVERY_BASENAMES"

echo ""
echo ">>> Contenuto $VENDOR_RAMDISK_DIR:"
ls -la "$VENDOR_RAMDISK_DIR"
