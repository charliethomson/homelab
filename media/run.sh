#!/bin/sh

cd "$(dirname "$0")"
[ -f .env ] || { echo "Copy .env.example to .env and fill in values"; exit 1; }

docker compose \
    -p media \
    --env-file .env \
    -f ./docker-compose.yml "$@"
