#!/bin/bash
send_discord_notification() {
    local content="$1"
    local webhook_url="$2"
    local msg_type="$3"

    if [ -z "$content" ]; then
        echo "⚠️  Content is empty — skipping Discord notification."
        return
    fi     
    if [ -z "$webhook_url" ]; then
        echo "⚠️  Webhook URL not set — skipping Discord notification."
        return
    fi
    
    if [ -z "$msg_type" ]; then
        echo "⚠️  Notification type not specified — skipping Discord notification."
        return
    fi 

    local message="\`\`\`$content\`\`\`"

    local avatar_url=""
    local username="Notification"

    case "$msg_type" in
        error)
            username="Error Alert"
            avatar_url="https://cdn-icons-png.flaticon.com/512/463/463612.png"
            ;;
        backup)
            username="Backup Notification"
            avatar_url="https://cdn.icon-icons.com/icons2/1381/PNG/512/mega_93685.png"
            ;;
        archive)
            username="Archive Notification"
            avatar_url="https://cdn.icon-icons.com/icons2/1381/PNG/512/mega_93685.png"
            ;;
        *)
            echo "⚠️  Invalid message type specified — skipping Discord notification."
            return
            ;;
    esac
    local msg="{\"username\": \"$username\", \"avatar_url\": \"$avatar_url\", \"content\": \"$message\"}"
    curl -s -H "Content-Type: application/json" -X POST -d "$msg" "$webhook_url"
}


print_boxed_message() {
  local msg="$1"
  local content_width=65
  # Check if message fits
  if [ ${#msg} -gt $content_width ]; then
    echo "Message too long!"
    return 1
  fi
  # Calculate padding
  local msg_length=${#msg}
  local left_padding=$(( (content_width - msg_length) / 2 ))
  local right_padding=$(( content_width - msg_length - left_padding ))
  # Print box
  echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  printf "%*s%s%*s\n" "$left_padding" "" "$msg" "$right_padding" ""
  echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
}

elapsed_time() {
  local start_sec=$1
  local now_sec=$(date +%s.%3N)
  local diff=$(echo "$now_sec - $start_sec" | bc)
  printf "(+%.1f sec)" "$diff"

}

# Function: get_remaining_space
# Purpose: Extracts the used storage percentage from MEGA account
# Returns: A string like "57.3%" or empty if parsing fails
get_remaining_space() {
    # Run 'mega-df' to get storage usage info; suppress errors
    local output
    output=$(mega-df -h 2>/dev/null)

    # Extract percentage value from line containing "USED STORAGE"
    local percent total_size
    percent=$(echo "$output" | grep "USED STORAGE" | sed -n 's/.* \([0-9]*\.[0-9]*%\).*/\1/p')
    total_size=$(echo "$output" | grep "USED STORAGE" | sed -n 's/.*of \([0-9.]* [A-Z]*\).*/\1/p')
    # Return the percentage string
    echo "$percent $total_size"
}

#send_discord_notification "this is a test message" "$DISCORD_WEBHOOK_URL" "backup"
#send_discord_notification "this is a test error message" "$DISCORD_ERROR_WEBHOOK_URL" "error"
#send_discord_notification "this is a test archive message" "$DISCORD_ARCHIVE_WEBHOOK_URL" "archive"

