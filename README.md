# MT5 Service - MetaTrader 5 Trading Service

A Docker-based REST API service that provides programmatic access to MetaTrader 5 trading operations. Runs MT5 on Linux using Wine and exposes all functionality through a Flask REST API behind a multi-account gateway.

## Table of Contents

- [Overview](#overview)
- [Platform support](#platform-support)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [API Integration](#api-integration)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Overview

`mt5_service` runs MetaTrader 5 in Docker (Wine + KasmVNC) with one **worker container per MT5 login**. A lightweight **gateway** routes HTTP requests to the correct worker by account ID (MT5 login number).

Deploy on a **Linux VPS** (recommended). See [Platform support](#platform-support) before using macOS.

## Platform support

| Platform | Support |
| --- | --- |
| **Linux** | **Supported** — Linux VPS or host with Docker. |
| **Windows** | **May work** — Docker Desktop with Linux containers (WSL2). |
| **macOS** | **Not supported for MT5** — Wine does not run reliably in these containers on Docker Desktop for Mac. Use a Linux VPS for production and VNC bootstrap. |

## Architecture

```
Client
  → Gateway (api.mt5.example.com or localhost:5002)
      → Worker 1 (MT5 login A)  — VNC: w1.vnc.mt5.example.com
      → Worker 2 (MT5 login B)  — VNC: w2.vnc.mt5.example.com
```

| Service | Local | Production (Traefik) |
| --- | --- | --- |
| API gateway | `http://localhost:5002` | `https://api.mt5.bawembye.com` |
| Worker 1 VNC | `http://localhost:3011` | `https://w1.vnc.mt5.bawembye.com` |
| Worker 2 VNC | `http://localhost:3012` | `https://w2.vnc.mt5.bawembye.com` |

**Shortcuts:** [`Makefile`](Makefile) — `make help`, `make up`, `make down`. Use matching `down` for the stack you started.

### Bootstrap workers

1. Open VNC for each worker (local ports above, or `w1` / `w2` hostnames with Traefik).
2. Log into MT5 in each container (save password).
3. List accounts:

   ```bash
   curl http://localhost:5002/accounts
   ```

4. Call the API with the MT5 login in the path:

   ```bash
   curl http://localhost:5002/accounts/25115284/get_positions
   curl -X POST http://localhost:5002/accounts/25115284/order \
     -H "Content-Type: application/json" \
     -d '{"symbol":"EURUSD","type":"BUY","volume":0.01}'
   ```

Per-worker Swagger (proxied): `https://api.mt5.bawembye.com/accounts/<login>/apidocs/`

### Scaling workers

Each MT5 login needs its own worker service, config volume (`config/workers/worker-N`), host VNC port, Traefik host `wN.${VNC_BASE_DOMAIN}`, and an entry in `MT5_WORKER_HOSTS` on the gateway. The repo ships **two** workers by default.

## Prerequisites

- Docker 20.10+ and Compose v2+
- Linux VPS (2GB+ RAM; 4GB+ recommended for two workers)
- DNS (optional): `API_DOMAIN`, `w1` / `w2` under `VNC_BASE_DOMAIN`, Traefik dashboard host
- MT5 demo or live credentials

## Quick Start

```bash
cd mt5_service
cp .env.example .env
make up
curl http://localhost:5002/health
curl http://localhost:5002/accounts
```

## Installation

### Environment

```bash
cp .env.example .env
```

Example `.env` for production hostnames:

```env
CUSTOM_USER=admin
PASSWORD=yourpassword
MT5_API_PORT=5001

API_DOMAIN=api.mt5.bawembye.com
VNC_BASE_DOMAIN=vnc.mt5.bawembye.com

TRAEFIK_DOMAIN=traefik.mt5.bawembye.com
TRAEFIK_USERNAME=admin
ACME_EMAIL=you@example.com
# TRAEFIK_HASHED_PASSWORD=...
```

### Traefik

```bash
docker network create traefik-public
make up-traefik
```

DNS:

- `api.mt5.bawembye.com` → VPS
- `w1.vnc.mt5.bawembye.com`, `w2.vnc.mt5.bawembye.com` → VPS (or wildcard `*.vnc.mt5.bawembye.com`)
- `traefik.mt5.bawembye.com` → VPS (dashboard)

### VPS checklist

1. Install Docker and Compose on the VPS.
2. Clone repo, configure `.env`, keep `config/workers/*` backed up.
3. `make up` or `make up-traefik`.
4. Log in via VNC per worker; verify `curl https://api.mt5.bawembye.com/accounts`.

## Configuration

| Variable | Description |
| --- | --- |
| `API_DOMAIN` | Public API hostname (Traefik). |
| `VNC_BASE_DOMAIN` | Base for worker VNC: `w1.${VNC_BASE_DOMAIN}`, `w2.${VNC_BASE_DOMAIN}`. |
| `CUSTOM_USER` / `PASSWORD` | KasmVNC basic auth inside worker containers. |
| `MT5_API_PORT` | Internal Flask port in workers (default `5001`). |
| `TRAEFIK_*` / `ACME_EMAIL` | Traefik dashboard and Let's Encrypt. |

Gateway (in `docker-compose.yml`): `MT5_WORKER_HOSTS`, `MT5_WORKER_VNC_PORTS` — keep in sync when adding workers.

Volumes: `config/workers/worker-1`, `config/workers/worker-2` (Wine prefix + MT5 data per account).

## Usage

### Gateway routes

| Route | Description |
| --- | --- |
| `GET /health` | Gateway + worker status |
| `GET /accounts` | Discovered MT5 logins and `vnc_host` |
| `GET /accounts/<login>/health` | Worker health |
| `GET/POST /accounts/<login>/<endpoint>` | Proxied worker API (`order`, `get_positions`, …) |

Worker endpoints match the paths documented in Swagger on each worker (no extra prefix on the worker itself).

### Managing services

| Target | Commands |
| --- | --- |
| Stack | `make up` · `make down` · `make logs` · `make build` |
| Gateway / workers | `make logs-gateway` · `make logs-worker1` · `make logs-worker2` |
| Mac (experimental) | `make up-mac` · `make worker-reset-mac` |
| Traefik | `make up-traefik` · `make down-traefik` · `make logs-traefik` |

## API Integration

```env
MT5_API_URL=https://api.mt5.bawembye.com
```

```python
import os
import requests

class MT5Client:
    def __init__(self, account_id: str, api_url: str | None = None):
        self.account_id = account_id
        self.api_url = (api_url or os.getenv("MT5_API_URL", "http://localhost:5002")).rstrip("/")

    def place_order(self, symbol: str, side: str, volume: float, **kwargs):
        response = requests.post(
            f"{self.api_url}/accounts/{self.account_id}/order",
            json={
                "symbol": symbol,
                "type": "BUY" if side.lower() == "buy" else "SELL",
                "volume": volume,
                **kwargs,
            },
        )
        response.raise_for_status()
        return response.json()

    def get_positions(self, magic: int | None = None):
        params = {"magic": magic} if magic is not None else {}
        response = requests.get(
            f"{self.api_url}/accounts/{self.account_id}/get_positions",
            params=params,
        )
        response.raise_for_status()
        return response.json()
```

## Troubleshooting

**Containers / logs:**

```bash
make logs-worker1
docker exec mt5-worker-1 tail -f /var/log/mt5_setup.log
```

**Mac / Wine issues:** use `make up-mac`; do not install Wine manually via VNC. `make worker-reset-mac` resets worker prefixes only.

**Account not routable:** ensure MT5 is logged in on that worker; check `GET /accounts` for `connected` and `routable`. Do not log the same login into two workers.

**Traefik certificates:** `make logs-traefik`; confirm DNS for `api`, `w1.vnc`, `w2.vnc` hosts.

## License

MIT License.
