#!/bin/sh
set -eu

PROWLARR_URL="http://prowlarr:9696"
SONARR_URL="http://sonarr:8989"
RADARR_URL="http://radarr:7878"
LIDARR_URL="http://lidarr:8686"

MAX_WAIT=300

wait_for() {
    name=$1
    status_url=$2
    key=$3
    elapsed=0
    until curl -sf -H "X-Api-Key: $key" "$status_url" >/dev/null 2>&1; do
        [ "$elapsed" -ge "$MAX_WAIT" ] && { echo "$name: timed out" >&2; exit 1; }
        echo "$name: not ready, retrying in 3s (${elapsed}s elapsed)"
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "$name: ready"
}

prowlarr_add_app() {
    name=$1
    payload=$2
    existing=$(curl -sf \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        "$PROWLARR_URL/api/v1/applications" \
        | jq -r ".[] | select(.name == \"$name\") | .id // empty")
    if [ -n "$existing" ]; then
        echo "Prowlarr: $name already configured (id=$existing)"
        return
    fi
    curl -sf -X POST \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$PROWLARR_URL/api/v1/applications" >/dev/null
    echo "Prowlarr: added $name"
}

wait_for prowlarr "$PROWLARR_URL/api/v1/system/status" "$PROWLARR_API_KEY"
wait_for sonarr   "$SONARR_URL/api/v3/system/status"  "$SONARR_API_KEY"
wait_for radarr   "$RADARR_URL/api/v3/system/status"  "$RADARR_API_KEY"
wait_for lidarr   "$LIDARR_URL/api/v1/system/status"  "$LIDARR_API_KEY"

prowlarr_add_app Sonarr "$(jq -n \
    --arg baseUrl "http://sonarr:8989" \
    --arg apiKey  "$SONARR_API_KEY" \
    '{
        name: "Sonarr", syncLevel: "fullSync",
        implementationName: "Sonarr", implementation: "Sonarr",
        configContract: "SonarrSettings", tags: [],
        fields: [
            {name: "prowlarrUrl",             value: "http://prowlarr:9696"},
            {name: "baseUrl",                 value: $baseUrl},
            {name: "apiKey",                  value: $apiKey},
            {name: "syncCategories",          value: [5000,5010,5020,5030,5040,5045,5050,5060,5070,5080]},
            {name: "animeSyncCategories",     value: [5070]},
            {name: "syncAnimeStandardFormat", value: false}
        ]
    }')"

prowlarr_add_app Radarr "$(jq -n \
    --arg baseUrl "http://radarr:7878" \
    --arg apiKey  "$RADARR_API_KEY" \
    '{
        name: "Radarr", syncLevel: "fullSync",
        implementationName: "Radarr", implementation: "Radarr",
        configContract: "RadarrSettings", tags: [],
        fields: [
            {name: "prowlarrUrl",    value: "http://prowlarr:9696"},
            {name: "baseUrl",        value: $baseUrl},
            {name: "apiKey",         value: $apiKey},
            {name: "syncCategories", value: [2000,2010,2020,2030,2040,2045,2050,2060]}
        ]
    }')"

prowlarr_add_app Lidarr "$(jq -n \
    --arg baseUrl "http://lidarr:8686" \
    --arg apiKey  "$LIDARR_API_KEY" \
    '{
        name: "Lidarr", syncLevel: "fullSync",
        implementationName: "Lidarr", implementation: "Lidarr",
        configContract: "LidarrSettings", tags: [],
        fields: [
            {name: "prowlarrUrl",    value: "http://prowlarr:9696"},
            {name: "baseUrl",        value: $baseUrl},
            {name: "apiKey",         value: $apiKey},
            {name: "syncCategories", value: [3000,3010,3020,3030,3040,3050]}
        ]
    }')"

echo "Init complete"
