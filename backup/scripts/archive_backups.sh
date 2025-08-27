#!/bin/bash

[ -f /etc/cron.env ] && source /etc/cron.env
source /backup/scripts/utils.sh

LOG_FILE="/backup/backup_out/archive_logs.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

# Check if Discord webhook URLs are set; if not, disable notifications
if [[ -z "$DISCORD_ARCHIVE_WEBHOOK_URL" || -z "$DISCORD_ERROR_WEBHOOK_URL" ]]; then
    echo "⚠️  Discord webhook URLs not set — disabling Discord notifications."
    send_notification_to_discord() { :; }
    send_error_notification_to_discord() { :; }
fi

# Function: create_folder_for_the_monthly_backup_archive
# Purpose: Ensures that a MEGA folder structure exists for archiving backups.
#          - Checks if the root archive folder ($MEGA_BACKUP_ARCHIVE_FOLDER) exists; creates it if missing.
#          - Enters that folder and checks for a subfolder named with today's date (dd-mm-yyyy).
#          - If today's subfolder doesn't exist, it creates it.
create_folder_for_the_monthly_backup_archive() {
    local folder_name="$MEGA_BACKUP_ARCHIVE_FOLDER"
    local folder_exists=false
    local today
    today=$(date '+%d-%m-%Y')

    # Get folder list at MEGA root; exit on failure
    local output
    output=$(mega-cd / && mega-ls 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$output" ]; then
        return 1
    fi

    # Check if the archive folder already exists
    while IFS= read -r line; do
        if [[ "$line" == "$folder_name" ]]; then
            folder_exists=true
            break
        fi
    done <<< "$output"

    # Create archive folder if it doesn't exist
    if [ "$folder_exists" = false ]; then
        mega-mkdir "/$folder_name" >/dev/null 2>&1 || return 1
    fi

    # Navigate into the archive folder
    mega-cd "/$folder_name" >/dev/null 2>&1 || return 1

    # Get list of subfolders (previous backups)
    local subfolders
    subfolders=$(mega-ls 2>/dev/null)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # If no subfolders exist, create today's folder
    if [ -z "$subfolders" ]; then
        mega-mkdir "$today" >/dev/null 2>&1 || return 1
    else
        # Otherwise, check if today's folder exists
        local found_today=false
        while IFS= read -r line; do
            if [[ "$line" == "$today" ]]; then
                found_today=true
                break
            fi
        done <<< "$subfolders"

        # Create today's folder if it doesn't exist
        if [ "$found_today" = false ]; then
            mega-mkdir "$today" >/dev/null 2>&1 || return 1
        fi
    fi

    return 0
}

# Function: get_the_file_names_for_the_given_date
# Purpose: Retrieves a list of MEGA file versions that match a specific date
# Parameters:
#   $1 - specific_date  (e.g., "10")
#   $2 - specific_month (e.g., "04")
#   $3 - specific_year  (e.g., "2025")
# Returns: A list of filenames (one per line) that match the given date,
#          or an error message if none match or something fails
get_the_file_names_for_the_given_date() {
    local specific_date="$1"
    local specific_month="$2"
    local specific_year="$3"
    # Array mapping numeric months to their full month names
    local month_names=("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec")
    # Convert the numeric month (e.g., 05) to the full month name (e.g., May)
    local month_name="${month_names[$((specific_month - 1))]}"
    
    # Check if the month name was correctly retrieved
    if [ -z "$month_name" ]; then
        echo "Invalid month number: $specific_month"
        return 1
    fi
    
    mega-cd
    # Navigate to $MEGA_REMOTE_FOLDER and retrieve version list
    local output
    output=$(mega-cd "$MEGA_REMOTE_FOLDER" && mega-ls --versions)
    # Check if the output is empty (no versions found or retrieval failed)
    if [[ -z "$output" ]]; then
        echo "Failed to retrieve versions or no versions found." >&2
        return 1
    fi

    # Parse output into an array
    local version_list=()
    IFS=$'\n' mapfile -t version_list <<< "$output"

    local matched_versions=()
    
    # Process each version entry
    for version in "${version_list[@]}"; do
        # Match date within parentheses
        if [[ $version =~ \((.*)\) ]]; then
            local date_string="${BASH_REMATCH[1]}"
            # Parse date into day, month, year
            if [[ $date_string =~ [a-zA-Z]{3},\ ([0-9]{1,2})\ ([a-zA-Z]{3})\ ([0-9]{4}) ]]; then
                local day="${BASH_REMATCH[1]}"
                local month="${BASH_REMATCH[2]}"
                local year="${BASH_REMATCH[3]}"
                
                # Convert month abbreviation to numeric format
                case $month in
                    Jan) month_num="01" ;; Feb) month_num="02" ;;
                    Mar) month_num="03" ;; Apr) month_num="04" ;;
                    May) month_num="05" ;; Jun) month_num="06" ;;
                    Jul) month_num="07" ;; Aug) month_num="08" ;;
                    Sep) month_num="09" ;; Oct) month_num="10" ;;
                    Nov) month_num="11" ;; Dec) month_num="12" ;;
                esac

                # Match against specific date criteria
                if [[ -n $day && $day == $specific_date && $month_num == $specific_month && $year == $specific_year ]]; then
                    local part_before_bracket="${version%%[*}"
                    part_before_bracket="${part_before_bracket#"${part_before_bracket%%[![:space:]]*}"}"  # trim leading spaces
                    part_before_bracket="${part_before_bracket%"${part_before_bracket##*[![:space:]]}"}"  # trim trailing spaces
                    matched_versions+=("$part_before_bracket")
                fi
            fi
        fi
    done

    if [[ ${#matched_versions[@]} -gt 0 ]]; then
         printf '%s\n' "${matched_versions[@]}"
    else
        echo "No matched versions for $specific_date/$specific_month/$specific_year"
    fi
}

# Function: convert_to_bytes
# Purpose: Converts a size string with unit (e.g., "20.00 GB") into bytes as a numeric value
# Returns: Size in bytes (as a plain number)
convert_to_bytes() {
    local size_str="$1"
    local value unit size

    value=$(echo "$size_str" | awk '{print $1}')
    unit=$(echo "$size_str" | awk '{print $2}')

    case "$unit" in
        B)   size="$value" ;;
        KB)  size=$(echo "$value * 1024" | bc) ;;
        MB)  size=$(echo "$value * 1024 * 1024" | bc) ;;
        GB)  size=$(echo "$value * 1024 * 1024 * 1024" | bc) ;;
        TB)  size=$(echo "$value * 1024 * 1024 * 1024 * 1024" | bc) ;;
        *)   echo "Unknown unit: $unit" >&2; return 1 ;;
    esac

    # Return only the numeric value in bytes
    echo "$size"
}

# Function: enough_space_to_archive
# Purpose: Calculate the total size in bytes of given files on MEGA cloud,
#          check if there is enough free space in the cloud for the archive.
# Input:
#   $1 - Total cloud storage size as a string with unit (e.g., "20.00 GB")
#   $2 - Used space percentage as a string with % (e.g., "2.51%")
#   $3..$n - Array of file names relative to the MEGA remote folder
# Output:
#   Returns 0 if enough space is available,
#   Returns 1 if not enough space,
#   Returns 2 if any file size could not be determined.
#   Prints no output; communicates status through return codes.
enough_space_to_archive() {
    local cloud_size="$1"          # Total cloud size (e.g. "20.00 GB")
    local used_percent="$2"        # Used percent (e.g. "2.51%")
    shift 2                       # Remove first two args
    local files=("$@")            # Remaining args are file names
    
    # Convert total cloud size string to bytes
    local total_cloud_bytes=$(convert_to_bytes "$cloud_size")
    
    local total_size=0
    local file_size full_path
    local space_needed_percent

    # Loop through each file and sum sizes
    for file in "${files[@]}"; do
        full_path="/$MEGA_REMOTE_FOLDER/$file"  # Construct full MEGA remote path
        output=$(mega-ls -la "$full_path" 2>/dev/null)
        # Extract file size (assuming output format, size is 3rd field)
        file_size=$(echo "$output" | grep -v '^FLAGS' | awk 'NR==1 {print $3}')
        
        # Validate file size is numeric
        if [[ -n "$file_size" && "$file_size" =~ ^[0-9]+$ ]]; then
            total_size=$((total_size + file_size))  # Add file size to total
        else
            return 2  # Error: Could not get size of a file
        fi
    done

    # Calculate percentage of total cloud storage required by the files
    space_needed_percent=$(echo "scale=2; ($total_size / $total_cloud_bytes) * 100" | bc)

    # Remove % sign from used_percent string and calculate remaining free %
    used_percent_value=$(echo "$used_percent" | sed 's/%//')
    remaining_percent=$(echo "scale=2; 100 - $used_percent_value" | bc)


    # Check if we have enough free space
    if (( $(echo "$space_needed_percent > $remaining_percent" | bc -l) )); then
        return 1  # Not enough space
    else
        return 0  # Enough space
    fi
}

# Script Purpose:
# Archives files from the file version system at $MEGA_REMOTE_FOLDER
# for a specific date by:
#  - Retrieving the file versions
#  - Copying them to the archive folder at $MEGA_ARCHIVE_PATH
#  - Deleting the original versions after successful archive

# Entry point: Main script execution starts here
#----------------------------------------------------------------------------------
#               Login to mega
echo ""
msg="Archiving files started at $(date '+%Y-%m-%d %H:%M:%S')"
print_boxed_message "$msg"
mega-login $MEGA_EMAIL $MEGA_PASSWORD >/dev/null 2>&1
if [ $? -ne 0 ]; then
    send_discord_notification "Failed to log in to MEGA. Please check your credentials." "$DISCORD_ERROR_WEBHOOK_URL" "error"
    msg="[ ✗ ] Failed to log in to MEGA at $(date '+%Y-%m-%d %H:%M:%S')"
    print_boxed_message "$msg"
    exit 1
fi

# Ensure MEGA session is cleaned up on script exit or interruption
trap 'echo "Script interrupted. Logging out from MEGA..."; mega-logout >/dev/null 2>&1' INT TERM
trap 'mega-logout >/dev/null 2>&1' EXIT

#----------------------------------------------------------------------------------
#checking and creating the archive folder
if ! create_folder_for_the_monthly_backup_archive; then
    send_discord_notification "Error: Failed to create archive folder structure on MEGA." "$DISCORD_ERROR_WEBHOOK_URL" "error"
    mega-logout >/dev/null 2>&1
    msg="[ ✗ ] Failed to create archive folder at $(date '+%Y-%m-%d %H:%M:%S')"
    print_boxed_message "$msg"
    exit 1
fi

#----------------------------------------------------------------------------------
# Setting the date that it archives from
ARCHIVE_DAY="01"
ARCHIVE_MONTH=$(date -d "$(date +%Y-%m-01) -1 month" +%m)
ARCHIVE_YEAR=$(date -d "$(date +%Y-%m-01) -1 month" +%Y)

# just for testing purposes
#ARCHIVE_DAY="17"
#ARCHIVE_MONTH="05"
echo "Archiving files from $ARCHIVE_DAY/$ARCHIVE_MONTH/$ARCHIVE_YEAR"

#----------------------------------------------------------------------------------
# Getting the list of files to archive for the specific date
mapfile -t archive_files < <(get_the_file_names_for_the_given_date "$ARCHIVE_DAY" "$ARCHIVE_MONTH" "$ARCHIVE_YEAR")
if [[ "${archive_files[0]}" == No\ matched\ versions* ]]; then
    send_discord_notification "Aborting. No matched versions for $ARCHIVE_DAY/$ARCHIVE_MONTH/$ARCHIVE_YEAR" "$DISCORD_ERROR_WEBHOOK_URL" "error"
    mega-logout >/dev/null 2>&1
    msg="[ ✗ ] Failed. No matched versions. $(date '+%Y-%m-%d %H:%M:%S')"
    print_boxed_message "$msg"
    exit 1
fi

MEGA_ARCHIVE_PATH="/$MEGA_BACKUP_ARCHIVE_FOLDER/$(date '+%d-%m-%Y')"
#printing file names to archive
for file in "${archive_files[@]}"; do
    echo "Archiving [$file] to [$MEGA_ARCHIVE_PATH/] folder"
done

#----------------------------------------------------------------------------------
# check if there is enough space to copy the archives
read used_percent total_cloud_size <<< "$(get_remaining_space)"
enough_space_to_archive "$total_cloud_size" "$used_percent" "${archive_files[@]}"
comm_status=$?
if [[ $comm_status -eq 2 ]]; then
    send_discord_notification "Aborting. Some files could not be sized." "$DISCORD_ERROR_WEBHOOK_URL" "error"
    mega-logout >/dev/null 2>&1
    msg="[ ✗ ] Failed. Files could not be sized. $(date '+%Y-%m-%d %H:%M:%S')"
    print_boxed_message "$msg"
    exit 1
elif [[ $comm_status -ne 0 ]]; then
    send_discord_notification "Aborting: Not enough space in MEGA cloud." "$DISCORD_ERROR_WEBHOOK_URL" "error"
    mega-logout >/dev/null 2>&1
    msg="[ ✗ ] Failed. Not enough space cloud. $(date '+%Y-%m-%d %H:%M:%S')"
    print_boxed_message "$msg"
    exit 1
fi

#----------------------------------------------------------------------------------
# copying the archive files to the $MEGA_ARCHIVE_PATH
for file in "${archive_files[@]}"; do
    #echo "Copying file: $file"
    origin_file_path="/$MEGA_REMOTE_FOLDER/$file"
    if ! mega-cp "$origin_file_path" "$MEGA_ARCHIVE_PATH"; then
        send_discord_notification "Error: Failed to copy [$origin_file_path] to [$MEGA_ARCHIVE_PATH]." "$DISCORD_ERROR_WEBHOOK_URL" "error"
        mega-logout >/dev/null 2>&1
        msg="[ ✗ ] Failed to copy files to archive path. $(date '+%Y-%m-%d %H:%M:%S')"
        print_boxed_message "$msg"
        exit 1
    fi
done

#----------------------------------------------------------------------------------
# Deletes the rest versions of the archived files (both in source and archive locations)
for file in "${archive_files[@]}"; do
    clean_file="${file%%#*}"
    #echo "Deleting file versions: $clean_file"

    # Deletes file versions inside the source folder ($MEGA_REMOTE_FOLDER)
    origin_file_path="/$MEGA_REMOTE_FOLDER/$clean_file"
    if ! mega-deleteversions -f "$origin_file_path"; then
        send_discord_notification "Error: Failed to delete versions of [$origin_file_path]." "$DISCORD_ERROR_WEBHOOK_URL" "error"
        mega-logout >/dev/null 2>&1
        msg="[ ✗ ] Failed to delete versions of file. $(date '+%Y-%m-%d %H:%M:%S')"
        print_boxed_message "$msg"
        exit 1
    fi

    # Deletes file versions inside the archive folder ($MEGA_ARCHIVE_PATH)
    archived_file_path="/$MEGA_ARCHIVE_PATH/$clean_file"
    if ! mega-deleteversions -f "$archived_file_path"; then
        send_discord_notification "Error: Failed to delete versions of [$archived_file_path]." "$DISCORD_ERROR_WEBHOOK_URL" "error"
        mega-logout >/dev/null 2>&1
        msg="[ ✗ ] Failed to delete ver of archived. $(date '+%Y-%m-%d %H:%M:%S')"
        print_boxed_message "$msg"
        exit 1
    fi
done

summary="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
summary+="✅ Archiving proccess completed\n"
summary+="🕓 $(date '+%Y-%m-%d %H:%M:%S') \n"
summary+="👤 $MEGA_EMAIL\n"
summary+="🗂️ Archive folder: $MEGA_BACKUP_ARCHIVE_FOLDER\n"
summary+="📂 Remote folder: $MEGA_REMOTE_FOLDER\n"
summary+="📅 Date archived: $ARCHIVE_DAY/$ARCHIVE_MONTH/$ARCHIVE_YEAR\n"
summary+="📦 Files archived: ${#archive_files[@]}\n"
summary+="📈 Used space: $used_percent\n"
summary+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
send_discord_notification "$summary" "$DISCORD_ARCHIVE_WEBHOOK_URL" "archive"

mega-logout >/dev/null 2>&1
complete_message 
msg="[ ✓ ] Archive completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
print_boxed_message "$msg"
