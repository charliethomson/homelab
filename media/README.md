# Media Stack

A self-hosted media management stack built around the \*arr suite, running on Docker Compose. All torrent traffic is tunnelled through ProtonVPN via Gluetun — qBittorrent never touches the open internet directly.

## Services

| Service | Port | Purpose |
|---|---|---|
| qBittorrent | 8080 | Torrent client (runs inside Gluetun's network namespace) |
| Gluetun | — | ProtonVPN WireGuard tunnel |
| FlareSolverr | 8191 | Cloudflare bypass for protected indexers |
| Prowlarr | 9696 | Indexer manager — syncs indexers to all \*arr apps |
| Sonarr | 8989 | TV show automation |
| Radarr | 7878 | Movie automation |
| Lidarr | 8686 | Music automation |
| Bazarr | 6767 | Subtitle automation (reads Sonarr + Radarr libraries) |
| Unpackerr | — | Extracts completed downloads for the \*arr apps |
| Recyclarr | — | Syncs TRaSH Guides quality profiles to Sonarr and Radarr (runs nightly) |

## Network layout

qBittorrent uses `network_mode: "service:gluetun"`, meaning it shares Gluetun's network namespace entirely — all of its traffic, including torrenting, goes through the VPN. Gluetun publishes port 8080 (web UI) and 6881 (BitTorrent) to the host. Every other service is on the default Docker bridge network and reaches qBittorrent by targeting the `gluetun` container on port 8080.

## Directory structure

```
media/
├── docker-compose.yml
├── run.sh            # thin wrapper around docker compose
├── .env              # secrets — gitignored
├── .env.example
├── init/
│   └── init.sh       # one-shot bootstrap: wires Prowlarr → Sonarr/Radarr/Lidarr
├── recyclarr/
│   └── recyclarr.yml
└── config/           # per-service config dirs — gitignored
    ├── qbittorrent/
    ├── prowlarr/
    ├── sonarr/
    ├── radarr/
    ├── lidarr/
    └── bazarr/
```

NFS mounts expected on the host:

| Host path | Used by |
|---|---|
| `/mnt/truenas/Files/10 - Downloads` | qBittorrent, Sonarr, Radarr, Lidarr |
| `/mnt/truenas/Files/04 - Anime/02 - Shows` | Sonarr, Bazarr |
| `/mnt/truenas/Files/04 - Anime/04 - Movies` | Radarr, Bazarr |
| `/mnt/truenas/Files/08 - Music` | Lidarr |

All services run as UID/GID 3000 (`PUID=3000`, `PGID=3000`). That user must own (or have write access to) the NFS mount paths.

## Initial setup

### 1. Environment file

```bash
cp .env.example .env
```

Fill in `.env`:

```
WIREGUARD_PRIVATE_KEY=<your ProtonVPN WireGuard private key>

SONARR_API_KEY=<random UUID>
RADARR_API_KEY=<random UUID>
LIDARR_API_KEY=<random UUID>
PROWLARR_API_KEY=<random UUID>
```

To get a WireGuard key from ProtonVPN: log in to proton.me → VPN → Downloads → WireGuard configuration → generate a config for a US server and copy the `PrivateKey` value.

Generate API keys with `openssl rand -hex 16`. These values are written into each app's config on every startup, so inter-service connections never break across container recreations.

### 2. Start the stack

```bash
./run.sh up -d
```

Check Gluetun is connected before touching anything else:

```bash
./run.sh logs -f gluetun
```

Look for `Wireguard is up` and a public IP that is not your home IP.

### 3. First-run auth setup (one-time per fresh volume)

Prowlarr, Sonarr, Radarr, and Lidarr all enforce Forms login. On the very first startup with a fresh config directory each app will prompt you to create an admin username and password. Do this before configuring anything else — it only happens once and persists in the config volume indefinitely.

Bazarr manages its own auth separately via its web UI.

### 4. Configure Prowlarr

The `init` container runs automatically on `docker compose up` and wires Prowlarr → Sonarr, Radarr, and Lidarr using the API keys from `.env`. Check its output with:

```bash
./run.sh logs init
```

You still need to add indexers manually (there is no API for seeding tracker credentials):

1. **Indexers → Add indexer** — add your preferred public or private trackers.
2. For any Cloudflare-protected indexer, add FlareSolverr first:
   - **Settings → Indexers → FlareSolverr proxies → Add**
   - URL: `http://flaresolverr:8191`
   - Tag the proxy, then assign that tag to the relevant indexer.

### 5. Configure qBittorrent

Open `http://localhost:8080` (or `qbit.dev.lan.thmsn.dev`).

Default credentials on first launch are `admin` / `adminadmin` — change them immediately in **Tools → Options → Web UI**.

Recommended settings:
- **Downloads → Default save path**: `/downloads`
- **BitTorrent → Seeding limits**: set ratio/time limits to taste, then pause on hit.

### 6. Add qBittorrent as a download client in each \*arr app

In Sonarr, Radarr, and Lidarr:

**Settings → Download Clients → Add → qBittorrent**

| Field | Value |
|---|---|
| Host | `gluetun` |
| Port | `8080` |
| Username | *(your qBittorrent username)* |
| Password | *(your qBittorrent password)* |

Use `gluetun` as the host (not `qbittorrent`) because qBittorrent shares Gluetun's network namespace — `gluetun` is the container that is actually reachable by name on the Docker network.

### 7. Configure Sonarr

Open `http://localhost:8989` (or `sonarr.dev.lan.thmsn.dev`).

1. **Settings → Media Management → Root Folders → Add** → `/tv`
2. Set your preferred naming format under **Settings → Media Management → Episode Naming**.
3. Prowlarr will have already synced indexers if step 3 was completed.
4. Add the qBittorrent download client (step 5).

### 8. Configure Radarr

Open `http://localhost:7878` (or `radarr.dev.lan.thmsn.dev`).

1. **Settings → Media Management → Root Folders → Add** → `/movies`
2. Prowlarr sync and qBittorrent download client same as Sonarr.

### 9. Configure Lidarr

Open `http://localhost:8686` (or `lidarr.dev.lan.thmsn.dev`).

1. **Settings → Media Management → Root Folders → Add** → `/music`
2. Prowlarr sync and qBittorrent download client same as above.

### 10. Configure Bazarr

Open `http://localhost:6767` (or `bazarr.dev.lan.thmsn.dev`).

1. **Settings → Sonarr**:
   - Enable, host `sonarr`, port `8989`, API key = `SONARR_API_KEY` from `.env`.
   - Base URL: leave blank.
2. **Settings → Radarr**:
   - Enable, host `radarr`, port `7878`, API key = `RADARR_API_KEY` from `.env`.
3. **Settings → Providers** — add subtitle providers (OpenSubtitles, Subscene, etc.).
4. **Settings → Languages** — set your wanted language profile and assign it as the default for series and movies.

Bazarr will scan both `/tv` and `/movies` for missing subtitles and download them automatically.

## Day-to-day usage

```bash
# Start
./run.sh up -d

# Stop
./run.sh down

# Tail logs for a specific service
./run.sh logs -f sonarr

# Pull updated images and recreate
./run.sh pull && ./run.sh up -d

# Open a shell in a container
./run.sh exec sonarr bash
```

## Gateway domains

All services are exposed via the Caddy gateway with TLS (see `../gateway/Caddyfile`).

| Service | LAN | VPN |
|---|---|---|
| qBittorrent | `qbit.dev.lan.thmsn.dev` | `qbit.dev.vpn.thmsn.dev` |
| Prowlarr | `prowlarr.dev.lan.thmsn.dev` | `prowlarr.dev.vpn.thmsn.dev` |
| Sonarr | `sonarr.dev.lan.thmsn.dev` | `sonarr.dev.vpn.thmsn.dev` |
| Radarr | `radarr.dev.lan.thmsn.dev` | `radarr.dev.vpn.thmsn.dev` |
| Lidarr | `lidarr.dev.lan.thmsn.dev` | `lidarr.dev.vpn.thmsn.dev` |
| Bazarr | `bazarr.dev.lan.thmsn.dev` | `bazarr.dev.vpn.thmsn.dev` |

## Troubleshooting

**Gluetun won't connect** — verify the WireGuard private key in `.env` is correct and that the ProtonVPN account has an active VPN subscription.

**qBittorrent unreachable** — because it shares Gluetun's network, if Gluetun is down qBittorrent's port is also unreachable. Check Gluetun logs first.

**\*arr can't reach qBittorrent** — use `gluetun` as the hostname, not `qbittorrent` or `localhost`. Test connectivity from inside a container: `./run.sh exec sonarr curl -s http://gluetun:8080`.

**Permission errors on NFS mounts** — the files/directories on TrueNAS must be owned by UID 3000 / GID 3000, or the NFS export must map root (or UID 3000) appropriately. Check with `ls -ln /mnt/truenas/Files/`.

**FlareSolverr not working** — confirm the container is running (`./run.sh ps`) and that the Prowlarr proxy URL is `http://flaresolverr:8191` (container name, not localhost).
