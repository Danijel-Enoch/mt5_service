# MT5 Service - MetaTrader 5 Trading Service

A Docker-based REST API service that provides programmatic access to MetaTrader 5 trading operations. Runs MT5 on Linux using Wine and exposes all functionality through a Flask REST API behind a multi-account gateway.

## Table of Contents

- [Overview](#overview)
- [Choose how you expose services](#choose-how-you-expose-services)
- [Platform support](#platform-support)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Deployment without Traefik](#deployment-without-traefik) (default)
- [Deployment with Traefik](#deployment-with-traefik) (optional)
- [Bootstrap workers](#bootstrap-workers)
- [Configuration reference](#configuration-reference)
- [Usage](#usage)
- [API Integration](#api-integration)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Overview

`mt5_service` runs MetaTrader 5 in Docker (Wine + KasmVNC) with one **worker container per MT5 login**. A lightweight **gateway** routes HTTP requests to the correct worker by account ID (MT5 login number).

Deploy on a **Linux VPS** (recommended). See [Platform support](#platform-support) before using macOS.

## Choose how you expose services

Most setups use **host ports** and an external reverse proxy (e.g. nginx), or direct IP access. **Traefik is optional** — skip it unless you want this repo to run Traefik and obtain Let’s Encrypt certificates for you.

| | **Without Traefik** (typical) | **With Traefik** (optional) |
| --- | --- | --- |
| Start stack | `make up` | `make up-traefik` (after `docker network create traefik-public`) |
| Compose files | `docker-compose.yml` only | `docker-compose.yml` + `docker-compose.traefik.yml` |
| API access | `http://<host>:5002` (or nginx → `localhost:5002`) | `https://${API_DOMAIN}` |
| VNC access | `http://<host>:3011`, `:3012` (or nginx → those ports) | `https://w1.${VNC_BASE_DOMAIN}`, `w2.${VNC_BASE_DOMAIN}` |
| `.env` | `CUSTOM_USER`, `PASSWORD`, `MT5_API_PORT` | Also `API_DOMAIN`, `VNC_BASE_DOMAIN`, `TRAEFIK_*`, `ACME_EMAIL` |
| DNS | Only if **you** terminate TLS on nginx/your proxy | Required for Traefik hostnames |

**Do not run `make up-traefik` if you are not using Traefik** — use `make up` only.

**Shortcuts:** [`Makefile`](Makefile) — `make help`, `make up`, `make down`. Always use the matching `down` target for how you started (`make down` vs `make down-traefik`).

## Platform support

| Platform | Support |
| --- | --- |
| **Linux** | **Supported** — Linux VPS or host with Docker. |
| **Windows** | **May work** — Docker Desktop with Linux containers (WSL2). |
| **macOS** | **Not supported for MT5** — Wine does not run reliably in these containers on Docker Desktop for Mac. Use a Linux VPS for production and VNC bootstrap. |

## Architecture

```
Client
  → Gateway (:5002 on host)
      → Worker 1 (MT5 login A)  — VNC :3011
      → Worker 2 (MT5 login B)  — VNC :3012
```

With your own nginx (or similar), terminate TLS on the proxy and forward to these local ports. With Traefik (optional), hostnames replace raw ports — see [Deployment with Traefik](#deployment-with-traefik).

| Service | Host port (no Traefik) | Optional Traefik hostname |
| --- | --- | --- |
| API gateway | **5002** | `api.mt5.bawembye.com` |
| Worker 1 VNC | **3011** | `w1.vnc.mt5.bawembye.com` |
| Worker 2 VNC | **3012** | `w2.vnc.mt5.bawembye.com` |

Internal container ports stay `5001` (Flask) and `3000` (KasmVNC); only the **host mappings** above matter for access without Traefik.

## Prerequisites

- Docker 20.10+ and Compose v2+
- Linux VPS (2GB+ RAM; 4GB+ recommended for two workers)
- MT5 demo or live credentials
- **Without Traefik:** open firewall ports you expose (at least `5002`, `3011`, `3012` if accessed from outside)
- **With Traefik:** DNS records for `API_DOMAIN`, `w1`/`w2` under `VNC_BASE_DOMAIN`, and optional `TRAEFIK_DOMAIN`

---

## Deployment without Traefik

This is the **default** path. No Traefik container, no `traefik-public` network, no `API_DOMAIN` / `VNC_BASE_DOMAIN` required in `.env`.

### 1. Configure `.env`

```bash
cp .env.example .env
```

Minimum (edit passwords):

```env
CUSTOM_USER=admin
PASSWORD=yourpassword
MT5_API_PORT=5001
```

`API_DOMAIN`, `VNC_BASE_DOMAIN`, and `TRAEFIK_*` can be omitted or left commented — they are only used when you add the Traefik compose overlay.

### 2. Start the stack

```bash
make up
```

### 3. Verify

```bash
curl http://localhost:5002/health
curl http://localhost:5002/accounts
```

On a VPS, replace `localhost` with the server IP or with the hostname your **nginx** (or other proxy) forwards to `127.0.0.1:5002`.

### 4. Firewall (VPS)

Allow only what you need, for example:

```bash
sudo ufw allow 5002/tcp   # API gateway
sudo ufw allow 3011/tcp   # Worker 1 VNC
sudo ufw allow 3012/tcp   # Worker 2 VNC
```

### 5. Optional: nginx (or Caddy) in front

Point your public hostnames at the VPS, then proxy to Docker’s published ports:

| Public URL (example) | Proxy to |
| --- | --- |
| `https://api.mt5.bawembye.com` | `http://127.0.0.1:5002` |
| `https://w1.vnc.mt5.bawembye.com` | `http://127.0.0.1:3011` |
| `https://w2.vnc.mt5.bawembye.com` | `http://127.0.0.1:3012` |

Enable WebSocket upgrade headers for VNC locations. SSL certificates live on nginx, not in this repo.

Clients then use `https://api.mt5.bawembye.com/accounts/<login>/...` even though Traefik is not running.

### 6. Bootstrap MT5

Follow [Bootstrap workers](#bootstrap-workers) using `:3011` and `:3012` (or your nginx VNC URLs).

### Managing services (no Traefik)

| Action | Command |
| --- | --- |
| Start | `make up` |
| Stop | `make down` |
| Logs | `make logs` · `make logs-gateway` · `make logs-worker1` · `make logs-worker2` |
| Rebuild | `make build` |

---

## Deployment with Traefik

**Skip this entire section** if you use nginx or direct ports ([Deployment without Traefik](#deployment-without-traefik)).

Traefik adds HTTPS (Let’s Encrypt HTTP-01), routes by hostname, and a optional dashboard. It listens on host **9080** (HTTP) and **9443** (HTTPS) by default so it can sit behind nginx on 80/443.

### 1. DNS

Point these to your VPS (same IP):

| Hostname |
| --- |
| `api.mt5.bawembye.com` (`API_DOMAIN`) |
| `w1.vnc.mt5.bawembye.com` |
| `w2.vnc.mt5.bawembye.com` |
| `traefik.mt5.bawembye.com` (dashboard, optional) |

Or use a wildcard `*.vnc.mt5.bawembye.com` for worker VNC hosts.

### 2. Configure `.env`

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

### 3. Create network and start

```bash
docker network create traefik-public
make up-traefik
```

### 4. Verify

```bash
curl https://api.mt5.bawembye.com/health
curl https://api.mt5.bawembye.com/accounts
```

Open `https://w1.vnc.mt5.bawembye.com` and `https://w2.vnc.mt5.bawembye.com` for MT5 login.

If nginx fronts Traefik, proxy port 80/443 to `9080`/`9443` and preserve `Host` headers.

### Managing services (Traefik)

| Action | Command |
| --- | --- |
| Start | `make up-traefik` |
| Stop | `make down-traefik` |
| Logs | `make logs-traefik` |

---

## Bootstrap workers

Same for both deployment paths; only VNC URLs differ.

1. Open VNC for worker 1 and worker 2:
   - **No Traefik:** `http://<host>:3011` and `:3012`
   - **Traefik:** `https://w1.vnc.mt5.bawembye.com`, `https://w2.vnc.mt5.bawembye.com`
2. Log into MT5 in each container (save password).
3. List accounts:

   ```bash
   curl http://localhost:5002/accounts
   # or https://api.mt5.bawembye.com/accounts when using a public API URL
   ```

4. Call the API (replace `<login>` with MT5 login number):

   ```bash
   curl http://localhost:5002/accounts/<login>/get_positions
   curl -X POST http://localhost:5002/accounts/<login>/order \
     -H "Content-Type: application/json" \
     -d '{"symbol":"EURUSD","type":"BUY","volume":0.01}'
   ```

Swagger per account (via gateway): `/accounts/<login>/apidocs/`

### Scaling workers

Each MT5 login needs its own worker service, `config/workers/worker-N` volume, host VNC port, gateway entry in `MT5_WORKER_HOSTS`, and (if using Traefik) `wN.${VNC_BASE_DOMAIN}` DNS + labels. The repo ships **two** workers by default.

---

## Configuration reference

| Variable | Required without Traefik? | Purpose |
| --- | --- | --- |
| `CUSTOM_USER` / `PASSWORD` | Yes | KasmVNC login inside worker containers |
| `MT5_API_PORT` | Yes (default `5001`) | Internal Flask port in workers |
| `API_DOMAIN` | No | Traefik API router hostname only |
| `VNC_BASE_DOMAIN` | No | Traefik VNC hosts `w1.`, `w2.`; also fills `vnc_host` in `GET /accounts` when set on gateway |
| `TRAEFIK_*` / `ACME_EMAIL` | No | Traefik dashboard and Let’s Encrypt |

Gateway settings in `docker-compose.yml`: `MT5_WORKER_HOSTS`, `MT5_WORKER_VNC_PORTS` — update when adding workers.

Volumes: `config/workers/worker-1`, `config/workers/worker-2` (Wine + MT5 data per account).

## Usage

### Gateway routes

| Route | Description |
| --- | --- |
| `GET /health` | Gateway + worker status |
| `GET /accounts` | Discovered MT5 logins (`vnc_port`, `vnc_host` when configured) |
| `GET /accounts/<login>/health` | Worker health |
| `GET/POST /accounts/<login>/<endpoint>` | Proxied worker API (`order`, `get_positions`, …) |

### Mac (experimental)

`make up-mac` · `make worker-reset-mac` — see [Platform support](#platform-support).

## API Integration

Set `MT5_API_URL` to whatever reaches the gateway:

```env
# No Traefik — VPS IP or nginx URL
MT5_API_URL=http://your-vps-ip:5002
# or
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

**API not reachable (no Traefik):**

```bash
curl http://127.0.0.1:5002/health
sudo ufw status
docker ps --filter name=mt5-gateway
```

**API not reachable (Traefik):** `make logs-traefik`; check DNS and HTTP-01 on port 80.

**Account not routable:** MT5 must be logged in on that worker; `GET /accounts` should show `connected` and `routable`. Never use the same login on two workers.

**Mac / Wine:** `make up-mac`; do not install Wine via VNC. `make worker-reset-mac` resets worker prefixes only.

## License

MIT License.
