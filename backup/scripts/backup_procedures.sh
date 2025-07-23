#!/bin/bash

source /backup/scripts/utils.sh

LOG_FILE="/backup/backup_out/backup_logs.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

timestamp() {
    date +"[%H:%M:%S]"
}
failed_encryptions=0
failed_uploads=0

[ -f /etc/cron.env ] && source /etc/cron.env

# Disable Discord notifications if either webhook URL is missing
if [[ -z "$DISCORD_WEBHOOK_URL" || -z "$DISCORD_ERROR_WEBHOOK_URL" ]]; then
    echo "⚠️  Discord webhook URLs not set — disabling Discord notifications."
    send_discord_notification() { :; }
fi

echo ""
start_total_sec=$(date +%s.%3N)
msg="Backup run started at $(date '+%Y-%m-%d %H:%M:%S')"
print_boxed_message "$msg"
echo "Mega account: $MEGA_EMAIL"
echo "$(timestamp) Zipping folders from /backup/backup_in..."
for dir in /backup/backup_in/*; do
    if [ -d "$dir" ] && [ "$(ls -A "$dir")" ]; then
        start_sec=$(date +%s.%3N)
        folder_name=$(basename "$dir")
        zip_file="/backup/backup_out/${folder_name}.zip"
        cd "$dir" || continue
        zip -r "$zip_file" . >/dev/null 2>&1
        cd - >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo "  • $folder_name ... ✓ $(elapsed_time "$start_sec")"
        else
            echo "  • $folder_name ... ✗ (Failed)"
        fi
    fi
done

echo "$(timestamp) Encrypting zip files..."
for zip_file in /backup/backup_out/*.zip; do
    start_sec=$(date +%s.%3N)
    [ -e "$zip_file" ] || continue  # skip if no zip files

    encrypted_file="${zip_file}.pcv"

    if [ -f "$encrypted_file" ]; then
        rm "$encrypted_file"
    fi

    /usr/local/bin/picocrypt -p "$ENCRYPTION_PASSWORD" "$zip_file"  >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "  • $(basename "$encrypted_file") ... ✓ $(elapsed_time "$start_sec")"
        rm "$zip_file"
    else
        echo  "  • $(basename "$zip_file") ... ✗ (Failed)"
        ((failed_encryptions++))
    fi
done

echo "$(timestamp) Uploading encrypted files to Mega.nz..."
mega-login "$MEGA_EMAIL" "$MEGA_PASSWORD" >/dev/null 2>&1
read percent_used_start total_cloud_size_start <<< "$(get_remaining_space)"
for encrypted_file in /backup/backup_out/*.pcv; do
    start_sec=$(date +%s.%3N)
    [ -e "$encrypted_file" ] || continue
    base_name="$(basename "$encrypted_file")"

    mega-put "$encrypted_file" "/$MEGA_REMOTE_FOLDER/" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "  • $MEGA_REMOTE_FOLDER/$base_name ... ✓ $(elapsed_time "$start_sec")"
        rm "$encrypted_file"
    else
        echo "  • $MEGA_REMOTE_FOLDER/$base_name ... ✗ (Failed)"
        ((failed_uploads++))
    fi
done

read percent_used_end total_cloud_size_end <<< "$(get_remaining_space)"
percent_used_end_num=$(echo "${percent_used_end%\%}" | tr -d '[:space:]')
percent_used_start_num=$(echo "${percent_used_start%\%}" | tr -d '[:space:]')
# Calculate difference
used_percent=$(echo "$percent_used_end_num - $percent_used_start_num" | bc -l)
used_percent=$(printf "%.2f" "$used_percent")

mega-logout >/dev/null 2>&1

#backed_up_folders=$(for d in /backup/backup_in/*; do [ -d "$d" ] && basename "$d"; done | paste -sd ", " -)
backed_up_folders=$(find /backup/backup_in -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | paste -sd ", " -)
if [ -z "$backed_up_folders" ]; then
    backed_up_folders="None"
fi

summary="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
summary+="✅ Backup completed!\n"
summary+="🕓 $(date '+%Y-%m-%d %H:%M') $(elapsed_time "$start_total_sec")\n"
summary+="👤 $MEGA_EMAIL\n"
summary+="📦 Folders: $backed_up_folders\n"
summary+="💾 Used storage: $percent_used_end (+${used_percent}%)\n"
summary+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

send_discord_notification "$summary" "$DISCORD_WEBHOOK_URL" "backup"


error_report="🚨 *Backup Issues Detected:*\n"
error_triggered=false
if [ "$failed_encryptions" -gt 0 ]; then
    error_report+="• ❌ Failed Encryptions: $failed_encryptions\n"
    error_triggered=true
fi
if [ "$failed_uploads" -gt 0 ]; then
    error_report+="• ❌ Failed Uploads: $failed_uploads\n"
    error_triggered=true
fi
if [[ "$percent_used" =~ ^[0-9]+(\.[0-9]+)?%$ ]]; then
    used_number=$(echo "$percent_used" | tr -d '%')
    if (( $(echo "$used_number > 90" | bc -l) )); then
        error_report+="• ⚠️ Mega.nz Storage Used: ${percent_used}\n"
        error_triggered=true
    fi
fi
if $error_triggered; then
    error_report+="🕓 Time: $(date '+%Y-%m-%d %H:%M:%S')"
    send_discord_notification "$error_report" "$DISCORD_ERROR_WEBHOOK_URL" "error"
fi

echo "Used storage: $percent_used_end (+${used_percent}%) out of $total_cloud_size_end"
msg="Backup run completed at $(date '+%Y-%m-%d %H:%M:%S') $(elapsed_time "$start_total_sec")"
print_boxed_message "$msg"