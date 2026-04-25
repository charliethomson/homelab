#!/bin/sh
set -e

GLUETUN_URL="http://localhost:8000"
QB_URL="http://localhost:8080"
QB_USER="${QB_USER:-admin}"
QB_PASS="${QB_PASS:-adminadmin}"

log() { echo "[port-updater] $*"; }

qb_login() {
  curl -s -c /tmp/qb_cookies.txt \
    --data-urlencode "username=$QB_USER" \
    --data-urlencode "password=$QB_PASS" \
    "$QB_URL/api/v2/auth/login" > /dev/null
}

qb_set_port() {
  curl -s -b /tmp/qb_cookies.txt \
    --data-urlencode "json={\"listen_port\":$1}" \
    "$QB_URL/api/v2/app/setPreferences" > /dev/null
}

current_port=0

while true; do
  port=$(curl -sf "$GLUETUN_URL/v1/openvpn/portforwarded" | grep -o '"port":[0-9]*' | grep -o '[0-9]*')

  if [ -n "$port" ] && [ "$port" != "0" ] && [ "$port" != "$current_port" ]; then
    log "Port changed: $current_port -> $port"
    qb_login
    qb_set_port "$port"
    current_port="$port"
    log "Updated qBittorrent listening port to $port"
  fi

  sleep 30
done
