#!/bin/bash
#
# Compile script for SushiKernel
# Copyright (C) 2024 Shoiya A.

SECONDS=0
CLANG_VERSION="clang-21.0.0"
TC_DIR="$HOME/tc/$CLANG_VERSION"
PATH=$HOME/tc/$CLANG_VERSION/bin:$PATH

export ARCH=arm64
export KBUILD_BUILD_USER=Moe
export KBUILD_BUILD_HOST=Nyan
export LLVM_DIR=$HOME/tc/$CLANG_VERSION/bin
export LLVM=1

AK3_DIR="$HOME/AnyKernel3"
VARIANTS=("fogos")
DEFCONFIGS=("vendor/fogos_defconfig")
ZIPNAME_PREFIX="sushi-$(date '+%Y%m%d-%H%M')"
LOG_FILE="moe.log"
: > "$LOG_FILE"

if [[ $# -ne 2 || $1 != "-v" || ! " ${VARIANTS[@]} " =~ " $2 " ]]; then
    echo "Use: $0 -v {fogos}" | tee -a "$LOG_FILE"
    exit 1
fi

VARIANT="$2"
DEFCONFIG="${DEFCONFIGS[0]}"

if ! [ -d "${TC_DIR}" ]; then
    echo "Clang not found! Downloading directly to ${TC_DIR}..." | tee -a "$LOG_FILE"
    mkdir -p "${TC_DIR}"

    if ! curl -L "https://git.codelinaro.org/clo/la/kernel_platform/prebuilts/build-tools/-/archive/android-16.0.0_r4/build-tools-android-16.0.0_r4.tar.gz?path=clang-r563880c" \
         | tar -xz -C "${TC_DIR}" --strip-components=2 >> "$LOG_FILE" 2>&1; then
        echo "Download failed! Aborting..." | tee -a "$LOG_FILE"
        exit 1
    fi
    echo "Clang setup completed successfully!" | tee -a "$LOG_FILE"
fi

echo -e "\nCompiling for $DEFCONFIG with variant $VARIANT..." | tee -a "$LOG_FILE"

mkdir -p out
make O=out ARCH=arm64 $DEFCONFIG | tee -a "$LOG_FILE"

ARGS="
CC=clang
LD=${LLVM_DIR}/ld.lld
ARCH=arm64
AR=${LLVM_DIR}/llvm-ar
NM=${LLVM_DIR}/llvm-nm
AS=${LLVM_DIR}/llvm-as
OBJCOPY=${LLVM_DIR}/llvm-objcopy
OBJDUMP=${LLVM_DIR}/llvm-objdump
READELF=${LLVM_DIR}/llvm-readelf
OBJSIZE=${LLVM_DIR}/llvm-size
STRIP=${LLVM_DIR}/llvm-strip
LLVM_AR=${LLVM_DIR}/llvm-ar
LLVM_DIS=${LLVM_DIR}/llvm-dis
LLVM_NM=${LLVM_DIR}/llvm-nm
LLVM=1
"

make ${ARGS} O=out $DEFCONFIG moto.config | tee -a "$LOG_FILE"
make ${ARGS} O=out -j$(nproc) | tee -a "$LOG_FILE"

if [ ! -e "out/arch/arm64/boot/Image" ]; then
    echo "ERROR: Image binary not found. Compilation failed!" | tee -a "$LOG_FILE"
    exit 1
fi

echo -e "\nKernel compiled successfully for $DEFCONFIG! Zipping up...\n" | tee -a "$LOG_FILE"

if [ -d "$AK3_DIR" ]; then
    cp -r $AK3_DIR AnyKernel3
    git -C AnyKernel3 checkout fogos &> /dev/null
else
    git clone -q https://github.com/MoeKernel/AnyKernel3 -b fogos
fi

cp out/.config AnyKernel3/config
cp out/arch/arm64/boot/Image AnyKernel3/Image
[ -f out/arch/arm64/boot/dtb.img ] && cp out/arch/arm64/boot/dtb.img AnyKernel3/dtb
[ -f out/arch/arm64/boot/dtbo.img ] && cp out/arch/arm64/boot/dtbo.img AnyKernel3/dtbo.img

ZIPNAME="${ZIPNAME_PREFIX}-${VARIANT}.zip"

cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder | tee -a "../$LOG_FILE"
cd ..

echo -e "\nCompleted compilation for $DEFCONFIG (variant $VARIANT) in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!" | tee -a "$LOG_FILE"
echo "Zip: $ZIPNAME" | tee -a "$LOG_FILE"

[ -f ./go-up ] || (wget https://raw.githubusercontent.com/GustavoMends/go-up/master/go-up && chmod +x go-up)
# ./go-up "$ZIPNAME"

upload_telegram_build() {
    if [[ -f ".env" ]]; then
        source .env
    else
        echo "Telegram upload disabled: .env not found." | tee -a "$LOG_FILE"
        return 0
    fi

    if [[ -z "$CHAT_ID" || -z "$BOT_TOKEN" ]]; then
        echo "Telegram upload disabled: missing CHAT_ID or BOT_TOKEN." | tee -a "$LOG_FILE"
        return 0
    fi

    build_count=0
    [[ -f build_count.txt ]] && build_count=$(cat build_count.txt)

    build_count=$((build_count + 1))
    echo "$build_count" > build_count.txt

    commit_id=$(git log --oneline -1 --pretty=format:'%h')
    commit_text=$(git log --oneline -1 --pretty=format:'%s')
    author_name=$(git log --format='%an' -1)
    kernel_version=$(make kernelversion 2>/dev/null)

    zip_file="$1"

    if [[ ! -f "$zip_file" ]]; then
        echo "Zip not found: $zip_file" | tee -a "$LOG_FILE"
        return 1
    fi

    caption=$(cat <<EOF
*SushiKernel build #${build_count}*

• *Kernel*: \`${kernel_version}\`
• *Commit*: \`${commit_id}\`
• *Message*: \`${commit_text}\`
• *Author*: \`${author_name}\`

@SushiKernel
EOF
)

    echo "Uploading $zip_file to Telegram..." | tee -a "$LOG_FILE"

    curl -s \
        -F chat_id="$CHAT_ID" \
        -F message_thread_id=$TOPIC_ID \
        -F document=@"$zip_file" \
        -F caption="$caption" \
        -F parse_mode="Markdown" \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
        >> "$LOG_FILE"

    echo "Telegram upload completed!" | tee -a "$LOG_FILE"
}

# upload_telegram_build "$ZIPNAME"
rm -rf AnyKernel3
