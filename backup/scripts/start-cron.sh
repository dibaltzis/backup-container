#!/bin/bash

echo "Running backup_container version ${APP_VERSION}"

./scripts/checks.sh
if [ $? -ne 0 ]; then
    echo "❌ Pre-flight checks failed. Exiting."
    exit 1
fi

CRON_FILE="/etc/cron.d/backup-cron"
: > "$CRON_FILE"  # Clear the cron file before writing new jobs

# Default ENABLE_ARCHIVE_FUNCTION to "false" if not set
ENABLE_ARCHIVE_FUNCTION="${ENABLE_ARCHIVE_FUNCTION:-false}"

# Write environment variables to be used by cron jobs
cat <<EOF > /etc/cron.env
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
export ENCRYPTION_PASSWORD="${ENCRYPTION_PASSWORD}"
export MEGA_REMOTE_FOLDER="${MEGA_REMOTE_FOLDER}"
export MEGA_BACKUP_ARCHIVE_FOLDER="${MEGA_BACKUP_ARCHIVE_FOLDER}"
export TZ="${TZ}"
export DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL}"
export DISCORD_ERROR_WEBHOOK_URL="${DISCORD_ERROR_WEBHOOK_URL}"
export DISCORD_ARCHIVE_WEBHOOK_URL="${DISCORD_ARCHIVE_WEBHOOK_URL}"
EOF

# Add backup job if defined
if [ -n "$BACKUP_CRON" ]; then
    echo "$BACKUP_CRON . /etc/cron.env; /backup/scripts/backup_procedures.sh >> /var/log/cron.log 2>&1" >> "$CRON_FILE"
    echo "✅ Backup cron schedule set to: $BACKUP_CRON"
else
    echo "⚠️  No BACKUP_CRON provided. Skipping backup job setup."
fi

if [ "$ENABLE_ARCHIVE_FUNCTION" = "true" ]; then
    # Add archive job if defined
    if [ -n "$ARCHIVE_CRON" ]; then
        echo "$ARCHIVE_CRON . /etc/cron.env; /backup/scripts/archive_backups.sh >> /var/log/cron.log 2>&1" >> "$CRON_FILE"
        echo "📦 Archive cron schedule set to: $ARCHIVE_CRON"
    else
        echo "⚠️  No ARCHIVE_CRON provided. Skipping archive job setup."
    fi
fi

# Finalize cron setup
chmod 0644 "$CRON_FILE"
crontab "$CRON_FILE"

# Start cron and keep logs in foreground
cron
tail -f /var/log/cron.log