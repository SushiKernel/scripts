#!/system/bin/sh

# ---- AK3 tools dir ----
TOOLS="${BIN:-${AKHOME:-/tmp/anykernel}/tools}"

# Aggiungi tools al PATH (per awk, tr, grep, ecc.)
export PATH="$TOOLS:$PATH"

# awk: la recovery non lo ha nel PATH
AWK="$TOOLS/busybox awk"
[ -x "$TOOLS/busybox" ] || AWK="$TOOLS/toybox awk"

ADD=94371840
TARGET_DEVICE="bangkk"

LINE="============================================================"
ERROR_LINE="############################################################"

section() {
    echo
    echo "$LINE"
    echo "$1"
    echo "$LINE"
}

error() {
    echo
    echo "$ERROR_LINE"
    echo "ERRORE: $1"
    echo "$ERROR_LINE"
    exit 1
}

ok() {
    echo "[ OK ] $1"
}

warn() {
    echo "[ WARN ] $1"
}

# HEADER

echo
echo "$LINE"
echo "BANGKK UNIVERSAL VENDOR RESIZE"
echo "$LINE"
echo "Target expansion: $ADD bytes (90 MiB)"

# ROOT CHECK

if [ "$(id -u)" != "0" ]; then
    error "Root richiesto."
fi

ok "Root access"

# ENVIRONMENT CHECK

section "ENVIRONMENT CHECK"

LPDUMP=$(command -v lpdump 2>/dev/null)
E2FSCK=$(command -v e2fsck 2>/dev/null)
RESIZE2FS=$(command -v resize2fs 2>/dev/null)
TUNE2FS=$(command -v tune2fs 2>/dev/null)

[ -n "$LPTOOLS" ] || LPTOOLS="$TOOLS/lptools_static"
[ -n "$LPTOOLS" ] || LPTOOLS="$TOOLS/lptools"
[ -n "$LPDUMP" ] || LPDUMP="$TOOLS/lpdump"
[ -n "$E2FSCK" ] || E2FSCK="$TOOLS/e2fsck"
[ -n "$RESIZE2FS" ] || RESIZE2FS="$TOOLS/resize2fs"
[ -n "$TUNE2FS" ] || TUNE2FS="$TOOLS/tune2fs"

# blockdev: in AK3 non è un binario singolo, ma toybox/busybox
if [ -z "$BLOCKDEV" ]; then
    if [ -x "$TOOLS/busybox" ]; then
        BLOCKDEV="$TOOLS/busybox blockdev"
    elif [ -x "$TOOLS/toybox" ]; then
        BLOCKDEV="$TOOLS/toybox blockdev"
    fi
fi

for TOOL in \
    "$LPTOOLS" \
    "$LPDUMP" \
    "$E2FSCK" \
    "$RESIZE2FS" \
    "$TUNE2FS"
do
    [ -x "$TOOL" ] || error "Tool mancante: $TOOL"
done

[ -n "$BLOCKDEV" ] || error "Tool mancante: blockdev (toybox/busybox)"

echo "lptools    : $LPTOOLS"
echo "lpdump     : $LPDUMP"
echo "e2fsck     : $E2FSCK"
echo "resize2fs  : $RESIZE2FS"
echo "tune2fs    : $TUNE2FS"
echo "blockdev   : $BLOCKDEV"
echo "awk        : $AWK"

SUPER=""

for X in \
    /dev/block/by-name/super \
    /dev/block/bootdevice/by-name/super
do
    if [ -e "$X" ]; then
        SUPER="$X"
        break
    fi
done

[ -n "$SUPER" ] || error "Super partition non trovata."

echo "super      : $SUPER"

# DEVICE DETECTION

section "DEVICE DETECTION"

PROP_BUILD_PRODUCT=$(getprop ro.build.product)
PROP_SKU=$(getprop ro.boot.product.hardware.sku)
PROP_HARDWARE=$(getprop ro.boot.product.hardware)
PROP_DEVICE=$(getprop ro.product.device)

echo "ro.build.product           = $PROP_BUILD_PRODUCT"
echo "ro.boot.product.hardware.sku = $PROP_SKU"
echo "ro.boot.product.hardware   = $PROP_HARDWARE"
echo "ro.product.device          = $PROP_DEVICE"

DEVICE_OK=0

for X in \
    "$PROP_BUILD_PRODUCT" \
    "$PROP_SKU" \
    "$PROP_HARDWARE" \
    "$PROP_DEVICE"
do
    if [ "$X" = "$TARGET_DEVICE" ]; then
        DEVICE_OK=1
    fi
done

[ "$DEVICE_OK" -eq 1 ] || error "Questo script è destinato a bangkk."

echo "Device verificato: bangkk"

# RECOVERY DETECTION

section "RECOVERY DETECTION"

RECOVERY="UNKNOWN"

BUILD_ID=$(getprop ro.build.display.id)
BUILD_DESC=$(getprop ro.build.description)

case "$(echo "$BUILD_ID $BUILD_DESC" | tr '[:upper:]' '[:lower:]')" in
    *orangefox*)
        RECOVERY="OrangeFox"
        ;;
    *twrp*)
        RECOVERY="TWRP"
        ;;
esac

echo "Recovery detected: $RECOVERY"

# ROM / LAYOUT DETECTION

section "ROM / LAYOUT DETECTION"

DISPLAY_ID=$(getprop ro.build.display.id)
DESCRIPTION=$(getprop ro.build.description)
INCREMENTAL=$(getprop ro.build.version.incremental)

echo "ro.build.display.id        = $DISPLAY_ID"
echo "ro.build.description       = $DESCRIPTION"
echo "ro.build.version.incremental = $INCREMENTAL"

ROM="UNKNOWN"

ALL_PROPS=$(getprop)

case "$(echo "$ALL_PROPS" | tr '[:upper:]' '[:lower:]')" in
    *lineage*)
        ROM="LineageOS"
        ;;
    *lunaris*)
        ROM="Lunaris OS"
        ;;
esac

echo "ROM detected: $ROM"

# SLOT DETECTION

section "SLOT DETECTION"

# Se $SLOT è già settato (da ak3-core.sh), non ri-rilevarlo
if [ -z "$SLOT" ]; then
    SLOT=$(getprop ro.boot.slot_suffix)
fi

if [ -z "$SLOT" ]; then
    SLOT_RAW=$(getprop ro.boot.slot)

    case "$SLOT_RAW" in
        a)
            SLOT="_a"
            ;;
        b)
            SLOT="_b"
            ;;
    esac
fi

# Fallback: guarda i mapper
if [ -z "$SLOT" ]; then
    if [ -e /dev/block/mapper/vendor_b ] && [ ! -e /dev/block/mapper/vendor_a ]; then
        SLOT="_b"
    elif [ -e /dev/block/mapper/vendor_a ] && [ ! -e /dev/block/mapper/vendor_b ]; then
        SLOT="_a"
    fi
fi

case "$SLOT" in
    _a|_b)
        ;;
    *)
        error "Slot attivo non rilevato."
        ;;
esac

VENDOR_NAME="vendor$SLOT"
VENDOR="/dev/block/mapper/$VENDOR_NAME"

echo "Active slot: $SLOT"
echo "Logical partition: $VENDOR_NAME"
echo "Mapper device   : $VENDOR"

[ -e "$VENDOR" ] || error "Mapper vendor non trovato: $VENDOR"

# PARTITION CHECK

section "PARTITION CHECK"

OLD=$($BLOCKDEV --getsize64 "$VENDOR" 2>/dev/null)

case "$OLD" in
    ''|*[!0-9]*)
        error "Impossibile leggere la dimensione di vendor."
        ;;
esac

NEW=$((OLD + ADD))

echo "Old vendor size: $OLD bytes"
echo "Add size       : $ADD bytes"
echo "New vendor size: $NEW bytes"

# EXT4 CHECK

section "EXT4 CHECK"

EXT4_INFO=$("$TUNE2FS" -l "$VENDOR" 2>&1)

echo "$EXT4_INFO" | grep -E \
"Filesystem magic number|Filesystem state|Block count|Free blocks|Block size"

MAGIC=$(echo "$EXT4_INFO" | \
    grep "Filesystem magic number" | \
    $AWK '{print $NF}' | \
    tr -d '[:space:]')

BLOCK_SIZE=$(echo "$EXT4_INFO" | \
    grep "^Block size:" | \
    $AWK '{print $NF}' | \
    tr -d '[:space:]')

BLOCK_COUNT=$(echo "$EXT4_INFO" | \
    grep "^Block count:" | \
    $AWK '{print $NF}' | \
    tr -d '[:space:]')

FREE_BLOCKS=$(echo "$EXT4_INFO" | \
    grep "^Free blocks:" | \
    $AWK '{print $NF}' | \
    tr -d '[:space:]')

case "$MAGIC" in
    0xEF53)
        ;;
        *)
        echo "Vendor EROFS detected"

        echo "========================================" >> /tmp/erofs-debug.log
        echo "[$(date)] RESIZE -> STARTING RO2RW" >> /tmp/erofs-debug.log

        /system/bin/erofs.sh >> /tmp/erofs-debug.log 2>&1
        EROFS_RC=$?

        echo "[$(date)] RO2RW FINISHED rc=$EROFS_RC" >> /tmp/erofs-debug.log
        echo "========================================" >> /tmp/erofs-debug.log

        exit $EROFS_RC
        ;;
esac

case "$BLOCK_SIZE" in
    ''|*[!0-9]*)
        error "Block size EXT4 non rilevato."
        ;;
esac

case "$BLOCK_COUNT" in
    ''|*[!0-9]*)
        error "Block count EXT4 non rilevato."
        ;;
esac

case "$FREE_BLOCKS" in
    ''|*[!0-9]*)
        error "Free blocks EXT4 non rilevati."
        ;;
esac

ok "Filesystem EXT4 verificato"

echo
echo "Parsed values:"
echo "Block size : $BLOCK_SIZE"
echo "Block count: $BLOCK_COUNT"
echo "Free blocks: $FREE_BLOCKS"

# RESIZE NECESSITY CHECK

section "RESIZE NECESSITY CHECK"

FREE_BYTES=$((FREE_BLOCKS * BLOCK_SIZE))
MIN_FREE=$((50 * 1024 * 1024))

echo "Vendor free space : $FREE_BYTES bytes"
echo "Minimum required  : $MIN_FREE bytes (50 MiB)"

if [ "$FREE_BYTES" -ge "$MIN_FREE" ]; then
    echo
    echo "$LINE"
    echo "RESIZE NOT NECESSARY"
    echo "$LINE"
    echo "Vendor ha gia almeno 50 MiB di spazio libero."
    echo "Free space: $FREE_BYTES bytes"
    echo
    echo "Nessun resize necessario. Uscita."
    exit 0
fi

echo "[ OK ] Vendor ha meno di 50 MiB liberi."
echo "[ OK ] Resize necessario. Continuazione dello script..."

# CURRENT LOGICAL PARTITION LAYOUT

section "CURRENT LOGICAL PARTITION LAYOUT"

"$LPDUMP" "$SUPER" || error "lpdump fallito."

# COW DETECTION

section "COW DETECTION"

COW_FOUND=0
COW_PARTITION=""
COW_SIZE=0

# Prima prova il COW direttamente associato a vendor
COW_NAME="${VENDOR_NAME}-cow"
COW_DEVICE="/dev/block/mapper/$COW_NAME"

if [ -e "$COW_DEVICE" ]; then

    echo "COW rilevato direttamente per vendor:"
    echo "COW name   : $COW_NAME"
    echo "COW device : $COW_DEVICE"

    COW_SIZE=$($BLOCKDEV --getsize64 "$COW_DEVICE" 2>/dev/null)

    echo "COW size   : $COW_SIZE bytes"

    COW_FOUND=1
    COW_PARTITION="$COW_NAME"

else

    echo "Nessun COW associato direttamente a $VENDOR_NAME."
    echo
    echo "Ricerca COW disponibili nello slot $SLOT..."

    # Cerca COW appartenenti alle altre logical partition
    for BASE in product system system_ext odm vendor; do

        TEST_COW="${BASE}${SLOT}-cow"

        if "$LPDUMP" "$SUPER" 2>/dev/null | \
            grep -q "Name: $TEST_COW"; then

            echo "COW trovato nel metadata:"
            echo "COW name: $TEST_COW"

            COW_PARTITION="$TEST_COW"
            TEST_DEVICE="/dev/block/mapper/$TEST_COW"

            if [ -e "$TEST_DEVICE" ]; then

                COW_SIZE=$($BLOCKDEV --getsize64 \
                    "$TEST_DEVICE" 2>/dev/null)

            else

                # Ricava la dimensione dai settori presenti in lpdump
                COW_SECTORS=$(
                    "$LPDUMP" "$SUPER" 2>/dev/null | \
                    $AWK -v name="$TEST_COW" '
                        $1=="Name:" && $2==name {
                            found=1
                            next
                        }

                        found && $1=="Extents:" {
                            next
                        }

                        found && $1 ~ /^[0-9]+$/ && $2==".." {
                            total += ($3 - $1 + 1)
                        }

                        found && /^------------------------/ {
                            if (total > 0) {
                                print total
                                exit
                            }
                        }
                    '
                )

                case "$COW_SECTORS" in
                    ''|*[!0-9]*)
                        COW_SIZE=0
                        ;;
                    *)
                        COW_SIZE=$((COW_SECTORS * 512))
                        ;;
                esac
            fi

            echo "COW size: $COW_SIZE bytes"

            COW_FOUND=1
            break
        fi
    done
fi

if [ "$COW_FOUND" -eq 1 ]; then
    ok "COW disponibile: $COW_PARTITION"
else
    warn "Nessun COW utilizzabile rilevato."
fi

# FREE SPACE CHECK

section "FREE SPACE CHECK"

"$LPTOOLS" free

FREE=$(
    "$LPTOOLS" free 2>/dev/null | \
    grep "Free space:" | \
    $AWK '{print $3}' | \
    tr -d '\r\n '
)

echo
echo "Detected free space: $FREE bytes"
echo "Requested expansion: $ADD bytes"

if [ -z "$FREE" ]; then
    error "Impossibile rilevare lo spazio libero."
fi

case "$FREE" in
    *[!0-9]*)
        error "Valore FREE non numerico: [$FREE]"
        ;;
esac

case "$ADD" in
    *[!0-9]*)
        error "Valore ADD non numerico: [$ADD]"
        ;;
esac

FREE_LEN=${#FREE}
ADD_LEN=${#ADD}

echo
echo "DEBUG COMPARISON:"
echo "FREE = [$FREE]"
echo "ADD  = [$ADD]"
echo "FREE digits = $FREE_LEN"
echo "ADD  digits = $ADD_LEN"

INSUFFICIENT=0

if [ "$FREE_LEN" -lt "$ADD_LEN" ]; then

    INSUFFICIENT=1

elif [ "$FREE_LEN" -eq "$ADD_LEN" ]; then

    A="$FREE"
    B="$ADD"

    while [ -n "$A" ]; do

        DA=${A%"${A#?}"}
        DB=${B%"${B#?}"}

        if [ "$DA" -lt "$DB" ]; then
            INSUFFICIENT=1
            break
        elif [ "$DA" -gt "$DB" ]; then
            break
        fi

        A=${A#?}
        B=${B#?}
    done
fi

# INSUFFICIENT SPACE - COW RECOVERY

if [ "$INSUFFICIENT" -eq 1 ]; then

    section "INSUFFICIENT SPACE - COW RECOVERY"

    echo "Spazio LP insufficiente per il resize."
    echo
    echo "Richiesti  : $ADD bytes"
    echo "Disponibili: $FREE bytes"
    echo

    if [ "$COW_FOUND" -ne 1 ]; then
        error "Spazio insufficiente e nessuna COW rilevata."
    fi

    case "$COW_SIZE" in
        ''|*[!0-9]*)
            error "Dimensione COW non valida: [$COW_SIZE]"
            ;;
    esac

    echo "COW selezionato: $COW_PARTITION"
    echo "COW size        : $COW_SIZE bytes"

    COW_LEN=${#COW_SIZE}
    COW_TOO_SMALL=0

    if [ "$COW_LEN" -lt "$ADD_LEN" ]; then

        COW_TOO_SMALL=1

    elif [ "$COW_LEN" -eq "$ADD_LEN" ]; then

        A="$COW_SIZE"
        B="$ADD"

        while [ -n "$A" ]; do

            DA=${A%"${A#?}"}
            DB=${B%"${B#?}"}

            if [ "$DA" -lt "$DB" ]; then
                COW_TOO_SMALL=1
                break
            elif [ "$DA" -gt "$DB" ]; then
                break
            fi

            A=${A#?}
            B=${B#?}
        done
    fi

    if [ "$COW_TOO_SMALL" -eq 1 ]; then
        error "Il COW $COW_PARTITION è troppo piccolo per liberare $ADD bytes."
    fi

    echo
    warn "Spazio insufficiente nel group."
    warn "Tentativo di recupero spazio dal COW:"
    echo
    echo "COW           : $COW_PARTITION"
    echo "COW attuale   : $COW_SIZE bytes"
    echo "Da liberare   : $ADD bytes"

    NEW_COW_SIZE=$((COW_SIZE - ADD))

    echo "Nuova COW size: $NEW_COW_SIZE bytes"

    if [ "$NEW_COW_SIZE" -le 0 ]; then
        error "Nuova dimensione COW non valida."
    fi

    echo
    echo "Ridimensionamento COW..."

    "$LPTOOLS" resize "$COW_PARTITION" "$NEW_COW_SIZE"
    RC=$?

    [ "$RC" -eq 0 ] || \
        error "Impossibile ridimensionare $COW_PARTITION. Exit code: $RC"

    ok "COW ridimensionato"

    echo
    echo "Nuovo spazio libero:"

    "$LPTOOLS" free

    FREE=$(
        "$LPTOOLS" free 2>/dev/null | \
        grep "Free space:" | \
        $AWK '{print $3}' | \
        tr -d '\r\n '
    )

    echo
    echo "Free space dopo COW recovery: $FREE bytes"

    if [ -z "$FREE" ]; then
        error "Impossibile rilevare lo spazio libero dopo COW recovery."
    fi

    case "$FREE" in
        *[!0-9]*)
            error "Valore FREE non numerico dopo COW recovery: [$FREE]"
            ;;
    esac

    FREE_LEN=${#FREE}
    INSUFFICIENT=0

    if [ "$FREE_LEN" -lt "$ADD_LEN" ]; then

        INSUFFICIENT=1

    elif [ "$FREE_LEN" -eq "$ADD_LEN" ]; then

        A="$FREE"
        B="$ADD"

        while [ -n "$A" ]; do

            DA=${A%"${A#?}"}
            DB=${B%"${B#?}"}

            if [ "$DA" -lt "$DB" ]; then
                INSUFFICIENT=1
                break
            elif [ "$DA" -gt "$DB" ]; then
                break
            fi

            A=${A#?}
            B=${B#?}
        done
    fi

    if [ "$INSUFFICIENT" -eq 1 ]; then
        error "Spazio ancora insufficiente dopo riduzione COW. Richiesti $ADD, disponibili $FREE."
    fi

    ok "Spazio recuperato dal COW."
fi

echo
ok "Spazio sufficiente."
echo "Disponibili: $FREE bytes"
echo "Richiesti : $ADD bytes"

# PRE-RESIZE SUMMARY

section "PRE-RESIZE SUMMARY"

echo "Vendor partition : $VENDOR_NAME"
echo "Mapper           : $VENDOR"
echo "Old size         : $OLD"
echo "Expansion        : $ADD"
echo "New size         : $NEW"
echo "Free LP space    : $FREE"

echo
echo "Procedura:"
echo "1. unmap $VENDOR_NAME"
echo "2. resize logical partition"
echo "3. map $VENDOR_NAME"
echo "4. e2fsck"
echo "5. resize2fs"
echo "6. verifica finale"

# UNMAP

section "UNMAP $VENDOR_NAME"

# Smonta vendor (e le altre logical) se montate, altrimenti l'unmap fallisce
umount /vendor 2>/dev/null

# Verifica che il mapper sia smontato
if mount | grep -q "$VENDOR"; then
    error "vendor risulta ancora montato dopo umount."
fi

"$LPTOOLS" unmap "$VENDOR_NAME"
RC=$?

[ "$RC" -eq 0 ] || error "unmap fallito. Exit code: $RC"

if [ -e "$VENDOR" ]; then
    error "vendor risulta ancora mapped dopo unmap."
fi

ok "$VENDOR_NAME unmapped"

# RESIZE LOGICAL PARTITION

section "RESIZE LOGICAL PARTITION"

echo "New size: $NEW bytes"

"$LPTOOLS" resize "$VENDOR_NAME" "$NEW"
RC=$?

[ "$RC" -eq 0 ] || error "Resize logical partition fallito. Exit code: $RC"

FREE_AFTER=$("$LPTOOLS" free 2>&1)

echo
echo "$FREE_AFTER"

ok "Logical partition resized"

# MAP

section "MAP $VENDOR_NAME"

"$LPTOOLS" map "$VENDOR_NAME"
RC=$?

[ "$RC" -eq 0 ] || error "map fallito. Exit code: $RC"

[ -e "$VENDOR" ] || error "Mapper vendor non creato dopo map."

MAPPED_SIZE=$($BLOCKDEV --getsize64 "$VENDOR" 2>/dev/null)

echo "Mapped vendor size: $MAPPED_SIZE bytes"

if [ "$MAPPED_SIZE" -ne "$NEW" ]; then
    error "Dimensione mapper non corretta. Atteso: $NEW, trovato: $MAPPED_SIZE"
fi

ok "Mapper verificato"

# E2FSCK

section "E2FSCK PRE-RESIZE"

"$E2FSCK" -fp "$VENDOR"
RC=$?

case "$RC" in
    0|1|2)
        ok "e2fsck completato. Exit code: $RC"
        ;;
    *)
        error "e2fsck fallito. Exit code: $RC"
        ;;
esac

# RESIZE EXT4

section "RESIZE EXT4 FILESYSTEM"

echo "Expanding EXT4 to device size..."

"$RESIZE2FS" "$VENDOR"
RC=$?

[ "$RC" -eq 0 ] || error "resize2fs fallito. Exit code: $RC"

ok "EXT4 filesystem expanded"

# FINAL EXT4 CHECK

section "FINAL EXT4 CHECK"

FINAL_INFO=$("$TUNE2FS" -l "$VENDOR" 2>&1)

echo "$FINAL_INFO" | grep -E \
"Filesystem magic number|Filesystem state|Block count|Free blocks|Block size"

FINAL_MAGIC=$(echo "$FINAL_INFO" | \
    grep "Filesystem magic number" | \
    $AWK '{print $NF}' | \
    tr -d '[:space:]')

FINAL_BLOCK_SIZE=$(echo "$FINAL_INFO" | \
    grep "^Block size:" | \
    $AWK '{print $NF}' | \
    tr -d '[:space:]')

FINAL_BLOCK_COUNT=$(echo "$FINAL_INFO" | \
    grep "^Block count:" | \
    $AWK '{print $NF}' | \
    tr -d '[:space:]')

FINAL_FREE_BLOCKS=$(echo "$FINAL_INFO" | \
    grep "^Free blocks:" | \
    $AWK '{print $NF}' | \
    tr -d '[:space:]')

FINAL_SIZE=$($BLOCKDEV --getsize64 "$VENDOR" 2>/dev/null)

EXPECTED_BLOCKS=$((FINAL_SIZE / FINAL_BLOCK_SIZE))

echo
echo "Final device size : $FINAL_SIZE"
echo "Expected blocks   : $EXPECTED_BLOCKS"
echo "Actual blocks     : $FINAL_BLOCK_COUNT"
echo "Free blocks       : $FINAL_FREE_BLOCKS"

[ "$FINAL_MAGIC" = "0xEF53" ] || \
    error "Filesystem finale non EXT4."

if [ "$FINAL_SIZE" -ne "$NEW" ]; then
    error "Dimensione finale errata."
fi

if [ "$FINAL_BLOCK_COUNT" -ne "$EXPECTED_BLOCKS" ]; then
    error "EXT4 non occupa l'intera nuova dimensione."
fi

# FINAL E2FSCK

section "FINAL E2FSCK"

"$E2FSCK" -fn "$VENDOR"
RC=$?

case "$RC" in
    0|1)
        ok "Filesystem finale verificato. Exit code: $RC"
        ;;
    *)
        error "Verifica finale e2fsck fallita. Exit code: $RC"
        ;;
esac

# REMOUNT VENDOR RW
section "REMOUNT VENDOR"

umount /vendor 2>/dev/null
mount -o rw /dev/block/mapper/$VENDOR_NAME /vendor 2>/dev/null || \
    mount -o rw -t ext4 /dev/block/mapper/$VENDOR_NAME /vendor 2>/dev/null || \
    warn "Impossibile rimontare /vendor in rw."

if mount | grep -q " /vendor "; then
    ok "/vendor rimontato in rw."
else
    warn "/vendor non rimontato (potrebbe servire a do_modules)."
fi

# FINAL LAYOUT

section "FINAL LOGICAL PARTITION LAYOUT"

"$LPDUMP" "$SUPER" 2>&1 | \
grep -A6 -B1 "Name: $VENDOR_NAME"

# SUCCESS

echo
echo "$LINE"
echo "SUCCESS"
echo "$LINE"

echo "Device             : bangkk"
echo "Recovery           : $RECOVERY"
echo "ROM                : $ROM"
echo "Active slot        : $SLOT"
echo "Vendor             : $VENDOR_NAME"
echo "Old vendor size    : $OLD bytes"
echo "Added              : $ADD bytes"
echo "New vendor size    : $FINAL_SIZE bytes"
echo "EXT4 block size    : $FINAL_BLOCK_SIZE"
echo "EXT4 block count   : $FINAL_BLOCK_COUNT"
echo "EXT4 free blocks   : $FINAL_FREE_BLOCKS"

echo
echo "Vendor resize completed successfully."
