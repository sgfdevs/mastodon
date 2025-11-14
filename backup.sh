#!/bin/bash
set -euo pipefail

# Ensure working directory is project root
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $__dir
# Load all environment variables
export $(cat .env.backup | xargs)

echo "Backing up mastodon"

docker compose exec db /bin/bash -c "pg_dump -U postgres postgres -f /tmp/backup.sql"

docker compose cp db:/tmp/backup.sql ./data/backup.sql

restic -r $RESTIC_REPOSITORY_PREFIX/mastodon backup ./data

restic -r $RESTIC_REPOSITORY_PREFIX/mastodon forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
