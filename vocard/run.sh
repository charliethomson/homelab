#!/bin/sh

set -e
cd "$(dirname "$0")"

[ -f .env ] || { echo "Copy .env.example to .env and fill in values"; exit 1; }

# render config templates into live/ before starting
set -a; . ./.env; set +a

mkdir -p live/dashboard live/lavalink

envsubst < settings.json          > live/settings.json
envsubst < dashboard/settings.json > live/dashboard/settings.json
envsubst < lavalink/application.yml > live/lavalink/application.yml

docker compose \
    -p vocard \
    --env-file .env \
    -f ./docker-compose.yml "$@"
