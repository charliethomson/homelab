#!/bin/sh

set -e
cd "$(dirname "$0")"

[ -f .env ] || { echo "Copy .env.example to .env and fill in values"; exit 1; }

set -a; . ./.env; set +a

mkdir -p live
envsubst < keys.json > live/keys.json

docker compose \
    -p cobalt \
    --env-file .env \
    -f ./docker-compose.yml "$@"
