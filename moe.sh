#!/bin/bash
#
# Compile script for SushiKernel
# Copyright (C) 2024 Shoiya A.

SECONDS=0
CLANG_VERSION="clang-20.0.0"
TC_DIR="$HOME/tc/$CLANG_VERSION"
PATH=$HOME/tc/$CLANG_VERSION/bin:$PATH
export modpath=AnyKernel3/modules/vendor/lib/modules
export ARCH=arm64
export KBUILD_BUILD_USER=Moe
export KBUILD_BUILD_HOST=Nyan
export LLVM_DIR=$HOME/tc/$CLANG_VERSION/bin
export LLVM=1

AK3_DIR="$HOME/AnyKernel3"
VARIANTS=("fogos" "fogos")
DEFCONFIGS=("vendor/fogos_defconfig" "vendor/fogos_defconfig")
ZIPNAME_PREFIX="sushi-$(date '+%Y%m%d-%H%M')"
LOG_FILE="moe.log"
: > "$LOG_FILE"

if [[ $# -ne 2 || $1 != "--variant" || ! " ${VARIANTS[@]} " =~ " $2 " ]]; then
    echo "Use: $0 --variant {fogos}" | tee -a "$LOG_FILE"
    exit 1
fi

VARIANT="$2"
if [[ "$VARIANT" == "fogos" ]]; then
    DEFCONFIG="${DEFCONFIGS[0]}"
elif [[ "$VARIANT" == "fogos" ]]; then
    DEFCONFIG="${DEFCONFIGS[1]}"
fi

if ! [ -d "${TC_DIR}" ]; then
    echo "Clang not found! Cloning to ${TC_DIR}..." | tee -a "$LOG_FILE"
    if ! git clone --depth=1 https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git ${TC_DIR} >> "$LOG_FILE" 2>&1; then
        echo "Cloning failed! Aborting..." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

echo -e "\nCompiling for $DEFCONFIG with variant $VARIANT..." | tee -a "$LOG_FILE"

mkdir -p out
make O=out ARCH=arm64 $DEFCONFIG | tee -a "$LOG_FILE"

ARGS='
CC=clang
LD='${LLVM_DIR}/ld.lld'
ARCH=arm64
AR='${LLVM_DIR}/llvm-ar'
NM='${LLVM_DIR}/llvm-nm'
AS='${LLVM_DIR}/llvm-as'
OBJCOPY='${LLVM_DIR}/llvm-objcopy'
OBJDUMP='${LLVM_DIR}/llvm-objdump'
READELF='${LLVM_DIR}/llvm-readelf'
OBJSIZE='${LLVM_DIR}/llvm-size'
STRIP='${LLVM_DIR}/llvm-strip'
LLVM_AR='${LLVM_DIR}/llvm-ar'
LLVM_DIS='${LLVM_DIR}/llvm-dis'
LLVM_NM='${LLVM_DIR}/llvm-nm'
LLVM=1
'

make ${ARGS} O=out $DEFCONFIG moto.config | tee -a "$LOG_FILE"
make ${ARGS} O=out -j$(nproc) | tee -a "$LOG_FILE"

if [ ! -e "out/arch/arm64/boot/Image" ]; then
    echo "ERROR: Image binary not found. Compilation failed!" | tee -a "$LOG_FILE"
    exit 1
fi

make O=out ${ARGS} -j$(nproc) INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install | tee -a "$LOG_FILE"
echo -e "\nKernel compiled successfully for $DEFCONFIG! Zipping up...\n" | tee -a "$LOG_FILE"

if [ -d "$AK3_DIR" ]; then
    cp -r $AK3_DIR AnyKernel3
    git -C AnyKernel3 checkout fogos &> /dev/null
else
    git clone -q https://github.com/MoeKernel/AnyKernel3 -b fogos
fi

cp out/.config AnyKernel3/config
cp out/arch/arm64/boot/Image AnyKernel3/Image
cp out/arch/arm64/boot/dtb.img AnyKernel3/dtb
cp out/arch/arm64/boot/dtbo.img AnyKernel3/dtbo.img

ZIPNAME="${ZIPNAME_PREFIX}-${VARIANT}.zip"

mkdir -p ${modpath}
kver=$(make kernelversion)
kmod=$(echo ${kver} | awk -F'.' '{print $3}')
mkdir -p AnyKernel3/modules/vendor/lib/modules 
kver=$(make kernelversion)
kmod=$(echo ${kver} | awk -F'.' '{print $3}')

cp out/.config AnyKernel3/config
cp out/arch/arm64/boot/Image AnyKernel3/Image
cp out/arch/arm64/boot/dtb.img AnyKernel3/dtb
cp out/arch/arm64/boot/dtbo.img AnyKernel3/dtbo.img
cp $(find out/modules/lib/modules/5.4* -name '*.ko') ${modpath}/
cp out/modules/lib/modules/5.4*/modules.{alias,dep,softdep} ${modpath}/
cp out/modules/lib/modules/5.4*/modules.order ${modpath}/modules.load

sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/vendor\/lib\/modules\/\2/g' ${modpath}/modules.dep
sed -i 's/.*\///; s/\.ko$//' ${modpath}/modules.load

for useles_modules in "${modules_to_nuke[@]}"; do
  grep -vE "$useles_modules" ${modpath}/modules.load > /tmp/templd && mv /tmp/templd ${modpath}/modules.load
done

cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder | tee -a "../$LOG_FILE"
cd ..

echo -e "\nCompleted compilation for $DEFCONFIG (variant $VARIANT) in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!" | tee -a "$LOG_FILE"
echo "Zip: $ZIPNAME" | tee -a "$LOG_FILE"
rm -rf AnyKernel3
