# Backup Container

Automated, encrypted backup and archiving to [MEGA.nz](https://mega.nz) with Discord notifications, managed via Docker Compose.

---

## Features

- **Automated Backups:** Scheduled zipping, encryption, and upload of folders to MEGA.nz.
- **Archiving:** Scheduled archival of file versions to a dedicated MEGA folder.
- **Encryption:** Uses [Picocrypt](https://github.com/HACKERALERT/Picocrypt) for strong encryption.
- **Notifications:** Sends status and error messages to Discord via webhooks.
- **Easy Setup:** All configuration via environment variables and Docker Compose.
- **Development Mode:** Includes a `dev` service for debugging and script development.
- **Multi-Architecture:** Supports both AMD64 and ARM64 builds and runs.

---

## Folder Structure

```
backup-container/
├── backup/
│   ├── backup_out/           # Output directory for logs and backup files
│   ├── backup_in/            # Input mount point for folders to back up
│   └── scripts/
│       ├── checks.sh         # Pre-flight checks for environment and MEGA
│       ├── backup_procedures.sh # Main backup logic
│       ├── archive_backups.sh   # Archive logic for old versions
│       └── start-cron.sh     # Entrypoint: sets up cron jobs
├── Dockerfile
├── Jenkinsfile
├── docker-compose.yml
├── docker-compose.build.yml
└── README.md
```

---

## Quick Start

1. **Clone the repository and enter the directory:**
   ```sh
   git clone https://github.com/dibaltzis/backup-container.git
   cd backup-container
   ```

2. **Create a `.env` file** in the root directory with the following variables:
   ```
   backup_cron=0 2 * * *         # Example: every day at 2am
   archive_cron=0 3 1 * *        # Example: 1st of every month at 3am
   mega_mail=your@email.com
   mega_password=yourpassword
   encryption_password=your_encryption_password
   mega_remote_folder=Backups
   archive_folder_name=Archives
   discord_webhook_url=https://discord.com/api/webhooks/...
   discord_error_webhook_url=https://discord.com/api/webhooks/...
   discord_archive_webhook_url=https://discord.com/api/webhooks/...
   ```

3. **Mount your data:**  
   By default, a source directory is mounted for backup. Adjust the `volumes` section in the compose files to specify which folders you want to back up or restore.

---

## Building Images

- **Build for AMD64 (default):**
  ```sh
  docker compose -f docker-compose.build.yml build --no-cache backup_amd64
  ```

- **Build for ARM64:**
  ```sh
  docker compose -f docker-compose.build.yml --profile arm64 build --no-cache backup_arm64
  ```

- **Build the Dev container (AMD64):**
  ```sh
  docker compose -f docker-compose.build.yml --profile dev build --no-cache dev
  ```

---

## Running Containers

- **Run backup on AMD64 (default):**
  ```sh
  docker compose up backup_amd64
  ```

- **Run backup on ARM64:**
  ```sh
  docker compose --profile arm64 up backup_arm64
  ```

- **Run the Dev container (AMD64):**
  ```sh
  docker compose --profile dev up dev
  ```

---

## How It Works

- **Entrypoint:** `start-cron.sh` runs checks, sets up cron jobs for backup and archive scripts, and tails the log.
- **Backup:** `backup_procedures.sh` zips, encrypts, and uploads files, then notifies Discord.
- **Archive:** `archive_backups.sh` moves old file versions to an archive folder on MEGA and cleans up.
- **Checks:** `checks.sh` validates mounts, credentials, and MEGA folder existence before running jobs.
- **Dev Service:** The `dev` service mounts scripts and backup folders for live debugging and development.

---

## Environment Variables

| Variable                     | Description                                 |
|------------------------------|---------------------------------------------|
| `BACKUP_CRON`                | Cron schedule for backups                   |
| `ARCHIVE_CRON`               | Cron schedule for archiving                 |
| `MEGA_EMAIL`                 | MEGA.nz account email                       |
| `MEGA_PASSWORD`              | MEGA.nz account password                    |
| `ENCRYPTION_PASSWORD`        | Password for Picocrypt encryption           |
| `MEGA_REMOTE_FOLDER`         | MEGA folder for backups                     |
| `MEGA_BACKUP_ARCHIVE_FOLDER` | MEGA folder for archives                    |
| `DISCORD_WEBHOOK_URL`        | Discord webhook for notifications           |
| `DISCORD_ERROR_WEBHOOK_URL`  | Discord webhook for errors                  |
| `DISCORD_ARCHIVE_WEBHOOK_URL`| Discord webhook for archive notifications   |
| `TZ`                         | Timezone (default: UTC)                     |

---


## Logs

- All logs are written to `backup/backup_out/backup_logs.txt` and `archive_logs.txt`.
- Cron output is tailed in the container’s foreground.

---

## Customization

- **Add more folders to back up:**  
  Mount them under `/backup/backup_in/` in your compose file.
- **Change backup/archive schedules:**  
  Edit `BACKUP_CRON` and `ARCHIVE_CRON` in your `.env`.
- **Switch architecture:**  
  Use the `--profile arm64` flag for ARM64, or `--profile dev` for development.

---

## CI/CD Pipeline

This project implements a fully automated CI/CD pipeline using Jenkins:

- **Trigger**: A Gitea webhook triggers the Jenkins pipeline on each commit
- **Build**: Multi-architecture Docker images are built using Docker Buildx (amd64 and arm64)
- **Registry**: Versioned images are pushed to a private local Docker registry
- **Deployment**: Watchtower monitors the registry and automatically deploys the latest image, completing the CI/CD cycle

---

## Troubleshooting

- Check logs in `backup/backup_out/`.
- Discord notifications will alert you to errors or issues.
- Ensure your MEGA credentials and folder names are correct.

---


