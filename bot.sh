#!/bin/bash

if [[ -f ".env" ]]; then
    source .env
else
    echo "Error: .env file not found."
    exit 1
fi

export CHAT_ID="${CHAT_ID:-}"
export API_ID="${API_ID:-}"
export API_HASH="${API_HASH:-}"
export BOT_TOKEN="${BOT_TOKEN:-}"

if [[ -z "$CHAT_ID" || -z "$API_ID" || -z "$API_HASH" || -z "$BOT_TOKEN" ]]; then
    echo "Error: Environment variables not set correctly."
    exit 1
fi

if [[ -f "build_count.txt" ]]; then
    build_count=$(cat build_count.txt)
else
    build_count=0
fi
build_count=$((build_count + 1))
echo $build_count > build_count.txt

commit_head=$(git log --oneline -1 --pretty=format:'%h - %an')
commit_id=$(git log --oneline -1 --pretty=format:'%h')
author_name=$(echo $commit_head | cut -d ' ' -f 3-)
commit_hash=$(echo $commit_head | cut -d ' ' -f 1)

kernel_version=$(make kernelversion 2>/dev/null)

build_type="release"
tag="fogos_${commit_hash:0:7}_$(date +%Y%m%d)"

start_message=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id=$CHAT_ID \
    -d text="*Compilation Start... Please Wait!*" \
    -d parse_mode="Markdown")

start_time=$(date +%s)

./moe.sh --variant fogos > build_log.txt 2>&1

if [[ $? -eq 0 ]]; then
    commit_head=$(git log --oneline -1 --pretty=format:'%h - %an')
    commit_id=$(git log --oneline -1 --pretty=format:'%h')
    author_name=$(echo $commit_head | cut -d ' ' -f 3-)
    commit_hash=$(echo $commit_head | cut -d ' ' -f 1)
    
    message_commit=$(git log --oneline -1 | cut -d ' ' -f 2-)
    commit_text=$message_commit

    commit_link="[${commit_text}](https://github.com/SushiKernel/android_kernel_motorola_fogos/commit/${commit_hash})"

    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))
    elapsed_minutes=$((elapsed_time / 60))
    elapsed_seconds=$((elapsed_time % 60))
    elapsed_minutes_formatted=$(printf "%.2f" $(echo "$elapsed_minutes + $elapsed_seconds / 60" | bc -l))

    completed_compile_text=$(cat <<EOF
*Compilation completed!*

Commit: ${commit_link}

Completed in ${elapsed_minutes_formatted} minute(s) and ${elapsed_seconds} second(s)!
EOF
)
    
    build_info=$(cat <<EOF
*fogos build (#${build_count}) has succeeded*
*Kernel Version*: ${kernel_version}
*Build Type*: \`${build_type}\` *(Sixteen)*
*Tag*: \`${tag}\`

*Duration*: ${elapsed_minutes} Minutes ${elapsed_seconds} Seconds

@SushiKernel #fogos
EOF
)

    zip_file=$(ls *.zip | head -n 1)
    if [[ -n "$zip_file" ]]; then
        caption=$(cat <<EOF
*Build Info*

• *Commit*: \`${commit_id}\`
• *Message*: \`${commit_text}\`
• *Author*: \`${author_name}\`
EOF
)
        curl -s -F chat_id=$CHAT_ID \
            -F document=@"$zip_file" \
            -F caption="$caption" \
            -F parse_mode="Markdown" \
            "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"
    fi

    message_id=$(echo $start_message | jq .result.message_id)
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/editMessageText" \
        -d chat_id=$CHAT_ID \
        -d message_id=$message_id \
        -d text="$completed_compile_text" \
        -d parse_mode="Markdown"

    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="@SushiKernelCI" \
        -d text="$build_info" \
        -d parse_mode="Markdown"

    exit 0
else
    log_file="error_log_#${build_count}_${commit_hash}.txt"
    mv build_log.txt "$log_file"

    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id=$CHAT_ID \
        -d text="❌ *Compilation failed!* See the log below." \
        -d parse_mode="Markdown"

    curl -s -F chat_id=$CHAT_ID \
        -F document=@"$log_file" \
        -F caption="Build log for #$build_count (Commit: $commit_id)" \
        -F parse_mode="Markdown" \
        "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"
    
    exit 1
fi
