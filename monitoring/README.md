# Monitoring Stack

Metrics, logs, and traces for the homelab. Prometheus scrapes node exporters across the LAN; Promtail ships Docker container logs; apps send OTLP telemetry to the OTel Collector, which fans out to Loki (logs) and Tempo (traces). Grafana is the single pane of glass for all three.

## Services

| Service | Port | Purpose |
|---|---|---|
| Grafana | 3000 | Dashboards — queries Prometheus, Loki, and Tempo |
| Prometheus | 9090 | Metrics scraper and TSDB (30-day retention) |
| Loki | 3100 | Log aggregation backend |
| Tempo | 3200 | Distributed tracing backend |
| Promtail | — | Scrapes Docker container logs → Loki |
| OTel Collector | 4317 (gRPC), 4318 (HTTP) | OTLP receiver — fans out logs → Loki, traces → Tempo |

## Data flow

```
node_exporter (:9100 on each host)  ──► Prometheus ──────────────────────┐
Home Assistant (:8123/api/prometheus) ──► Prometheus                      │
Docker containers                   ──► Promtail ──► Loki                 ├──► Grafana
Apps (OTLP)                         ──► OTel Collector ──► Loki (logs)    │
                                                      └──► Tempo (traces) ┘
```

Prometheus scrapes these hosts:

| Host | Address |
|---|---|
| dev.thmsn.local | 192.168.0.193:9100 |
| game.thmsn.local | 192.168.0.87:9100 |
| ttr.thmsn.local | 192.168.0.33:9100 |
| agent-1.thmsn.local | 192.168.0.12:9100 |
| agent-2.thmsn.local | 192.168.0.201:9100 |
| fs.thmsn.local | 192.168.0.62:9100 |
| ha.thmsn.local | 192.168.0.114:8123 (HA metrics API) |
| ttr app | ttr.lan.thmsn.dev/api/metrics |

OTel ports 4317/4318 are LAN-facing — remote services on the network can ship OTLP telemetry directly to this host.

## Directory structure

```
monitoring/
├── docker-compose.yml
├── run.sh                          # thin wrapper around docker compose
├── .env                            # secrets — gitignored
├── .env.example
├── grafana/
│   ├── grafana.ini
│   └── provisioning/datasources/
│       └── prometheus.yml          # auto-provisions Prometheus, Loki, Tempo datasources
├── loki/config/
│   └── loki-config.yml
├── otelcol/
│   └── config.yml
├── prometheus/config/
│   ├── prometheus.yml
│   └── ha_token                    # HA bearer token — gitignored
├── promtail/
│   └── config.yml
└── tempo/
    └── tempo.yml
```

Data is stored in named Docker volumes (`prometheus_data`, `grafana_data`, `loki_data`, `tempo_data`).

## Initial setup

### 1. Environment file

```bash
cp .env.example .env
```

Fill in `.env`:

```
GF_SECURITY_ADMIN_PASSWORD=<choose a password>
```

### 2. HA bearer token

Prometheus uses a long-lived token to authenticate against the Home Assistant metrics API. The token lives in a gitignored file:

```bash
echo -n '<token>' > prometheus/config/ha_token
```

To generate a new token in Home Assistant: **Profile → Long-Lived Access Tokens → Create token**.

### 3. Start the stack

```bash
./run.sh up -d
```

## Day-to-day usage

```bash
# Start
./run.sh up -d

# Stop
./run.sh stop

# Tail logs for a specific service
./run.sh logs -f prometheus

# Pull updated images and recreate
./run.sh pull && ./run.sh up -d
```

## Gateway

Grafana is proxied by the Caddy gateway (see `../gateway/Caddyfile`) at `https://dev.thmsn.local/management/monitoring/`.

## Troubleshooting

**Grafana shows "no data" for a datasource** — check the datasource health in **Connections → Data sources → [source] → Save & test**. Confirm the relevant backend container is running: `./run.sh ps`.

**Prometheus target down** — open `http://localhost:9090/targets` to see which scrape targets are failing. For node exporters, verify `node_exporter` is running on the target host and port 9100 is reachable from this host.

**HA metrics not scraping** — confirm `prometheus/config/ha_token` exists and contains a valid, unexpired token. Test manually: `curl -H "Authorization: Bearer $(cat prometheus/config/ha_token)" http://192.168.0.114:8123/api/prometheus`.

**OTel Collector not receiving spans/logs** — confirm the sending service is targeting this host on port 4317 (gRPC) or 4318 (HTTP) and that the firewall allows inbound connections on those ports.

**Promtail not shipping logs** — the container needs access to the Docker socket (`/var/run/docker.sock`). Verify it is mounted and that the Promtail process has read access.
