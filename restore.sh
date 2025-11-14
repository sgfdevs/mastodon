#!/bin/bash
set -euo pipefail

# Ensure working directory is project root
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $__dir
# Load all environment variables
export $(cat .env.backup | xargs)

docker compose down

sudo chown -R $(id -u):$(id -g) ./data/system

restic -r $RESTIC_REPOSITORY_PREFIX/mastodon restore latest --target ./

sudo chown -R 991:991 ./data/system

docker compose up -d db

docker compose cp ./data/backup.sql db:/tmp/backup.sql

docker compose exec db /bin/bash -c "dropdb -U postgres --if-exists postgres && createdb -U postgres postgres"

docker compose exec db /bin/bash -c "psql -U postgres postgres < /tmp/backup.sql"

docker compose exec db rm /tmp/backup.sql

docker compose up -d
