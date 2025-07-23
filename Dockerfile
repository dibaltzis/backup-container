# --- Builder Stage ---
FROM golang:1.22 AS builder

WORKDIR /app

# Install Picocrypt CLI
RUN go install github.com/HACKERALERT/Picocrypt/cli/v1/picocrypt@latest

# --- Final Runtime Stage ---
FROM debian:bookworm-slim AS runtime

# Install minimal runtime dependencies including MegaCMD dependency (procps)
RUN apt-get update && apt-get install -y \
    libfuse2 \
    gnupg \
    fuse \
    wget \
    ca-certificates \
    procps \
    zip \
    tzdata \
    curl \
    bc \
    cron \
    && rm -rf /var/lib/apt/lists/*

ARG MEGA_OS=Debian_12
ARG MEGA_ARCHITECTURE=amd64

# Set MEGA variables
ENV MEGA_OS=${MEGA_OS}
ENV MEGA_ARCHITECTURE=${MEGA_ARCHITECTURE}
ENV MEGA_FILENAME=megacmd-${MEGA_OS}_${MEGA_ARCHITECTURE}

# Conditionally add 32-bit support and install MegaCMD
RUN if [ "$MEGA_ARCHITECTURE" = "armhf" ]; then \
      dpkg --add-architecture armhf && \
      apt-get update && \
      apt-get install -y libc6:armhf libatomic1:armhf libstdc++6:armhf apt-transport-https && \
      rm -rf /var/lib/apt/lists/*; \
    fi


# Download and install MegaCMD
RUN wget https://mega.nz/linux/repo/${MEGA_OS}/${MEGA_ARCHITECTURE}/${MEGA_FILENAME}.deb \
    && dpkg -i ${MEGA_FILENAME}.deb \
    && apt-get install -fy \
    && rm ${MEGA_FILENAME}.deb

#COPY --from=builder /go/bin/picocrypt ./picocrypt
COPY --from=builder /go/bin/picocrypt /usr/local/bin/picocrypt

WORKDIR backup     
# Copy Picocrypt binary into /app
#COPY --from=builder /go/bin/picocrypt ./picocrypt

# Create required directories inside /app
RUN mkdir -p scripts backup_in backup_out

# Copy scripts into /app/scripts
COPY backup/scripts/checks.sh ./scripts/checks.sh
COPY backup/scripts/utils.sh ./scripts/utils.sh
COPY backup/scripts/backup_procedures.sh ./scripts/backup_procedures.sh
COPY backup/scripts/start-cron.sh ./scripts/start-cron.sh
COPY backup/scripts/archive_backups.sh ./scripts/archive_backups.sh

# Make all scripts executable
RUN chmod +x ./scripts/*.sh

# Setup cron log
RUN touch /var/log/cron.log

# Environment variables
ENV CRON_SCHEDULE=""
ENV MEGA_EMAIL=""
ENV MEGA_PASSWORD=""
ENV ENCRYPTION_PASSWORD=""
ENV MEGA_REMOTE_FOLDER=""
ENV MEGA_BACKUP_ARCHIVE_FOLDER=""
ENV TZ=UTC  
ENV DISCORD_WEBHOOK_URL=""
ENV DISCORD_ERROR_WEBHOOK_URL=""
ENV DISCORD_ARCHIVE_WEBHOOK_URL=""

# Entry point from /app
ENTRYPOINT ["./scripts/start-cron.sh"]