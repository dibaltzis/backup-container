#!/bin/bash

# ==============================================================
# Backup Container Preflight Checks Script
#
# This script performs a series of checks before running a backup:
#   - Verifies mega-cmd and picocrypt are installed
#   - Checks for mounted and non-empty backup input folders
#   - Validates MEGA credentials and login
#   - Ensures encryption password and remote folder variables are set
#   - Checks for (and creates if needed) the MEGA remote folder
#   - Logs all output to /backup/backup_out/backup_logs.txt
#
# Exit codes:
#   1 - mega-cmd (mega-version) is not installed or not in PATH
#   2 - picocrypt is not installed or not in PATH
#   3 - No backup folders were mounted or all are empty
#   4 - Login to Mega.nz failed
#   5 - MEGA_EMAIL or MEGA_PASSWORD not set
#   6 - ENCRYPTION_PASSWORD not set
#   7 - MEGA_REMOTE_FOLDER not set
#   8 - Failed to create remote folder
# ==============================================================

source /backup/scripts/utils.sh

LOG_FILE="/backup/backup_out/backup_logs.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

timestamp() {
    date +"[%H:%M:%S]"
}

run_checks() {

    
    msg="Backup Container Preflight Checks $(date '+%Y-%m-%d %H:%M:%S')"
    print_boxed_message "$msg"

    #--------------------[ mega-cmd check ]----------------------
    echo "Checking if mega-cmd is installed..."
    if ! command -v mega-version &> /dev/null; then
        echo "[ ✗ ] mega-version could not be found"
        return 1
    else
        echo "[ ✓ ] mega-version is installed"
    fi


    #-------------------[ picocrypt check ]----------------------
    echo "Checking if picocrypt is installed..."
    if ! command -v /usr/local/bin/picocrypt &> /dev/null; then
        echo "[ ✗ ] picocrypt could not be found"
        return 1
    else
        echo "[ ✓ ] picocrypt is installed"
    fi


    #------------[ backup input folders access check ]------------
    echo "Checking backup input folders access..."
    mounted_count=0
    for dir in /backup/backup_in/*; do
        if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
            echo "[ ✓ ] Mounted and contains files: $(basename "$dir")"
            ((mounted_count++))
        fi
    done

    if [ "$mounted_count" -eq 0 ]; then
        echo "[ ✗ ] No backup folders mounted or all are empty"
        return 1
    else
        echo "[ ✓ ] Folder access check passed"
    fi

    #----------------[ MEGA credentials check ]-------------------
    echo "Checking MEGA credentials..."
    if [ -n "$MEGA_EMAIL" ] && [ -n "$MEGA_PASSWORD" ]; then
        echo "login $MEGA_EMAIL $MEGA_PASSWORD" | mega-cmd >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "[ ✓ ] Successfully logged in to Mega.nz"
        else
            echo "[ ✗ ] Failed to log in to Mega.nz"
            return 2
        fi
    else
        echo "[ ✗ ] MEGA credentials not set"
        return 3
    fi

    #------------[ encryption password presence check ]-----------
    echo "Verifying that encryption password is set..."
    if [ -n "$ENCRYPTION_PASSWORD" ]; then
        echo "[ ✓ ] Encryption password is set"
    else
        echo "[ ✗ ] Encryption password missing"
        return 4
    fi

    #-----------[ MEGA remote folder variable check ]-------------
    echo "Verifying that MEGA remote folder name is set..."
    if [ -n "$MEGA_REMOTE_FOLDER" ]; then
        echo "[ ✓ ] MEGA folder: $MEGA_REMOTE_FOLDER"
    else
        echo "[ ✗ ] MEGA_REMOTE_FOLDER not set"
        return 5
    fi

    #--------[ MEGA remote folder existence/creation check ]------
    echo "Checking if remote folder '$MEGA_REMOTE_FOLDER' exists on Mega.nz..."
    if mega-ls | grep -q "^$MEGA_REMOTE_FOLDER$"; then
        echo "[ ✓ ] Remote folder '$MEGA_REMOTE_FOLDER' already exists"
    else
        echo "[ ✗ ] Remote folder not found. Creating '$MEGA_REMOTE_FOLDER'..."
        mega-mkdir "$MEGA_REMOTE_FOLDER"
        if [ $? -eq 0 ]; then
            echo "[ ✓ ] Successfully created remote folder '$MEGA_REMOTE_FOLDER'"
        else
            echo "[ ✗ ] Failed to create remote folder '$MEGA_REMOTE_FOLDER'"
            return 6
        fi
    fi
    #------------------------[ logout ]---------------------------
    mega-logout >/dev/null 2>&1
    return 0
}

# Run checks
run_checks
exit_code=$?
if [ $exit_code -ne 0 ]; then
    case $exit_code in
        1) echo "🛠️ mega-cmd (mega-version) is not installed or not in PATH." ;;
        2) echo "🛠️ picocrypt is not installed or not in PATH." ;;
        3) echo "🔎 No backup folders were mounted or all are empty." ;;
        4) echo "🔐 Login to Mega.nz failed — check MEGA_EMAIL and MEGA_PASSWORD." ;;
        5) echo "🔐 MEGA_EMAIL or MEGA_PASSWORD not set." ;;
        6) echo "🛡️ ENCRYPTION_PASSWORD not set." ;;
        7) echo "📁 MEGA_REMOTE_FOLDER not set." ;;
        8) echo "📁 Failed to create remote folder — check path/permissions." ;;
        *) echo "❗ Unknown error occurred." ;;
    esac
    msg="Checks failed with exit code [ $exit_code ] $(date '+%Y-%m-%d %H:%M:%S')"
    print_boxed_message "$msg"
    exit $exit_code
else
    msg="All checks passed successfully. $(date '+%Y-%m-%d %H:%M:%S')"
    print_boxed_message "$msg"
fi
