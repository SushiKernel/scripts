#!/bin/bash
#
# Compile script for SushiKernel
# Copyright (C) 2024 Akari.

set -e
SECONDS=0

CLANG_VERSION="zyc-clang-21"
TC_DIR="$HOME/tc/$CLANG_VERSION"

export PATH="$TC_DIR/bin:$PATH"

export ARCH=arm64
export KBUILD_BUILD_USER=Sushi
export KBUILD_BUILD_HOST=Kernel

export LLVM=1
export LLVM_IAS=1
export LLVM_DIR="$TC_DIR/bin"

AK3_DIR="$HOME/AnyKernel3"
VARIANT="bangkk"
DEFCONFIGS=(
    vendor/holi-qgki_defconfig
    vendor/ext_config/lineage_moto-holi.config
    vendor/ext_config/moto-holi-bangkk.config
)
LOG_FILE="moe.log"
: > "$LOG_FILE"

PLACE_MODULES="$(pwd)/place-modules.sh"

ARGS="
ARCH=arm64
LLVM=1
LLVM_IAS=1
CC=clang
CROSS_COMPILE=aarch64-linux-gnu-
LD=ld.lld
AR=llvm-ar
NM=llvm-nm
OBJCOPY=llvm-objcopy
OBJDUMP=llvm-objdump
STRIP=llvm-strip
"

INCLUDE_DTB=0
INCLUDE_DTBO=0

usage() {
    echo "Use: BUILD=1 ANYKERNEL=1 $0 [--dtb] [--dtbo]" | tee -a "$LOG_FILE"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dtb)
            INCLUDE_DTB=1
            shift
            ;;
        --dtbo)
            INCLUDE_DTBO=1
            shift
            ;;
        *)
            echo "Argumento desconhecido: $1" | tee -a "$LOG_FILE"
            usage
            ;;
    esac
done

setup_toolchain() {
    if ! [ -d "${TC_DIR}" ]; then
        echo "ZyC Clang 21 not found! Downloading..."
        mkdir -p "$HOME/tc"

        git clone --depth=1 -b 21 \
            https://gitlab.com/clangsantoni/zyc_clang.git \
            "$TC_DIR"

        if [ $? -ne 0 ]; then
            echo "Failed to download ZyC Clang!" | tee -a "$LOG_FILE"
            exit 1
        fi

        echo "ZyC Clang setup completed!" | tee -a "$LOG_FILE"
    fi
}

configure() {
    echo -e "\nConfiguring for ${DEFCONFIGS[*]} with variant $VARIANT..." | tee -a "$LOG_FILE"
    mkdir -p out
    make ${ARGS} O=out "${DEFCONFIGS[@]}" | tee -a "$LOG_FILE"
    make ${ARGS} O=out olddefconfig | tee -a "$LOG_FILE"
}

build_image() {
    make ${ARGS} O=out -j$(nproc) | tee -a "$LOG_FILE"

    if [ ! -e "out/arch/arm64/boot/Image" ]; then
        echo "ERROR: Image binary not found. Compilation failed!" | tee -a "$LOG_FILE"
        exit 1
    fi
}

build_modules() {
    echo -e "\nBuilding modules...\n" | tee -a "$LOG_FILE"
    make ${ARGS} O=out -j$(nproc) modules | tee -a "$LOG_FILE"
}

modules_install() {
    rm -rf out/modules_install
    make ${ARGS} O=out modules_install INSTALL_MOD_PATH=modules_install | tee -a "$LOG_FILE"
}

make_anykernel() {
    echo -e "\nZipping up...\n" | tee -a "$LOG_FILE"

    if [ -d "$AK3_DIR" ]; then
        cp -r $AK3_DIR AnyKernel3
        git -C AnyKernel3 checkout bangkk_modules &> /dev/null
    else
        git clone -q https://github.com/MoeKernel/AnyKernel3 -b bangkk_modules
    fi

    cp out/.config AnyKernel3/config
    cp out/arch/arm64/boot/Image AnyKernel3/Image

    if [ "$INCLUDE_DTB" = 1 ]; then
        if [ -f out/arch/arm64/boot/dtb.img ]; then
            cp out/arch/arm64/boot/dtb.img AnyKernel3/dtb
        else
            echo "WARNING: --dtb passado mas dtb.img não encontrado!" | tee -a "$LOG_FILE"
        fi
    fi

    if [ "$INCLUDE_DTBO" = 1 ]; then
        if [ -f out/arch/arm64/boot/dtbo.img ]; then
            cp out/arch/arm64/boot/dtbo.img AnyKernel3/dtbo.img
        else
            echo "WARNING: --dtbo passado mas dtbo.img não encontrado!" | tee -a "$LOG_FILE"
        fi
    fi

    if [ ! -x "$PLACE_MODULES" ]; then
        echo "ERROR: place-modules.sh não encontrado/executável em $PLACE_MODULES" | tee -a "$LOG_FILE"
        exit 1
    fi

    mkdir -p AnyKernel3/modules/vendor/lib/modules

    "$PLACE_MODULES" \
        "out/modules_install/lib/modules"/* \
        AnyKernel3/modules/vendor/lib/modules \
        "/vendor/lib/modules" | tee -a "$LOG_FILE"

    if [ -f "AnyKernel3/modules/vendor/lib/modules/wlan.ko" ]; then
        echo "Creating qca_cld3_wlan.ko ..." | tee -a "$LOG_FILE"
        cp -f \
            "AnyKernel3/modules/vendor/lib/modules/wlan.ko" \
            "AnyKernel3/modules/vendor/lib/modules/qca_cld3_wlan.ko"
    else
        echo "WARNING: wlan.ko não encontrado!" | tee -a "$LOG_FILE"
    fi

    find AnyKernel3/modules -name "*.ko" -exec llvm-strip --strip-unneeded -g {} \;

    ZIPNAME="Sushi-$(date '+%Y%m%d-%H%M')-${VARIANT}.zip"

    cd AnyKernel3
    zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder | tee -a "../$LOG_FILE"
    cd ..

    echo "Zip: $ZIPNAME" | tee -a "$LOG_FILE"

    [ -f ./go-up ] || (wget https://raw.githubusercontent.com/GustavoMends/go-up/master/go-up && chmod +x go-up)
    ./go-up "$ZIPNAME"

    rm -rf AnyKernel3
}

setup_toolchain
configure

[ "$BUILD" = 1 ] && (build_image && build_modules && modules_install)

[ "$ANYKERNEL" = 1 ] && make_anykernel

echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!" | tee -a "$LOG_FILE"

# Build command:
# BUILD=1 ANYKERNEL=1 ./sushi.sh
# BUILD=1 ANYKERNEL=1 ./sushi.sh [--dtb] [--dtbo]
