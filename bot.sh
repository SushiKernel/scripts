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
    -d text="*Compilation started... please wait.*" \
    -d parse_mode="Markdown")

start_time=$(date +%s)

# ./ksu_update.sh
./moe.sh --variant fogos

if [[ $? -eq 0 ]]; then
    commit_head=$(git log --oneline -1 --pretty=format:'%h - %an')
    commit_id=$(git log --oneline -1 --pretty=format:'%h')
    author_name=$(echo $commit_head | cut -d ' ' -f 3-)
    commit_hash=$(echo $commit_head | cut -d ' ' -f 1)
    
    message_commit=$(git log --oneline -1 | cut -d ' ' -f 2-)
    commit_text=$message_commit

	commit_link=$(cat <<EOF
[${commit_text}](https://github.com/MoeKernel/android_kernel_motorola_fogos/commit/${commit_hash})
EOF
)

    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))
    elapsed_minutes=$((elapsed_time / 60))
    elapsed_seconds=$((elapsed_time % 60))
    elapsed_minutes_formatted=$(printf "%.2f" $(echo "$elapsed_minutes + $elapsed_seconds / 60" | bc -l))

	completion_message=$(cat <<EOF
Completed in ${elapsed_minutes_formatted} minute(s) and ${elapsed_seconds} second(s)!"
EOF
)

	completed_compile_text=$(cat <<EOF
*Compilation completed!*

Commit: ${commit_link}

${completion_message}
EOF
)
	
    build_info=$(cat <<EOF
*fogos build (#${build_count}) has succeeded*
*Kernel Version*: ${kernel_version}
*Build Type*: \`${build_type}\` *(KSU/Fourteen)*
*Tag*: \`${tag}\`

*Duration*: ${elapsed_minutes} Minutes ${elapsed_seconds} Seconds

@MoeKernel #fogos #ksu
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
        -d chat_id="@MoeNyanCI" \
        -d text="$build_info" \
        -d parse_mode="Markdown"

    exit 0
else
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id=$CHAT_ID \
        -d text="Compilation failed." \
        -d parse_mode="Markdown"
    exit 1
fi

echo "bot is running..."

