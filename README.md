# MT5 Service - MetaTrader 5 Trading Service

A Docker-based REST API service that provides programmatic access to MetaTrader 5 trading operations. Runs MT5 on Linux using Wine and exposes all functionality through a Flask REST API.

## Table of Contents

- [MT5 Service - MetaTrader 5 Trading Service](#mt5-service---metatrader-5-trading-service)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Features](#features)
  - [Architecture](#architecture)
  - [Prerequisites](#prerequisites)
  - [Quick Start](#quick-start)
  - [Installation](#installation)
    - [Local Development](#local-development)
    - [VPS Deployment](#vps-deployment)
  - [Configuration](#configuration)
    - [Environment Variables](#environment-variables)
    - [Docker Compose Services](#docker-compose-services)
    - [Volumes](#volumes)
  - [Usage](#usage)
    - [API Endpoints](#api-endpoints)
    - [Accessing Services](#accessing-services)
    - [Managing Services](#managing-services)
  - [API Documentation](#api-documentation)
  - [Deployment](#deployment)
    - [Local Development](#local-development-1)
    - [VPS Deployment (Production)](#vps-deployment-production)
  - [API Integration](#api-integration)
  - [Logging](#logging)
  - [Troubleshooting](#troubleshooting)
    - [Common Issues](#common-issues)
  - [License](#license)

## Overview

`mt5_service` provides a Docker-based REST API for MetaTrader 5 trading operations. It runs MetaTrader 5 using Wine on a Debian-based Docker environment, exposing all MT5 functionality through a Flask REST API. The service can be deployed to a VPS (recommended) or run locally for development.

This service enables programmatic access to MT5 for executing trades, retrieving market data, managing positions, and accessing trading history through standard HTTP endpoints.

**Key Components:**

- **Flask REST API** - Exposes MT5 operations via HTTP endpoints
- **Wine + MT5** - Runs MetaTrader 5 on Linux
- **Docker Containerization** - Isolated, reproducible environment
- **VNC Access** - Optional remote desktop for debugging
- **Traefik Integration** - Optional reverse proxy with SSL

## Features

- **REST API:** Complete MT5 functionality exposed via HTTP endpoints
- **Trading Operations:** Execute orders, manage positions, modify SL/TP
- **Market Data:** Real-time tick data, historical OHLCV data, symbol information
- **Position Management:** Get positions, close positions, filter by magic number
- **History & Analysis:** Deal history, order history, performance tracking
- **Dockerized Environment:** Simplified deployment and management
- **Wine Compatibility:** Runs MetaTrader 5 on Linux without native Windows installation
- **Headless Operation:** Works on headless Linux VPS (no GUI required)
- **Traefik Integration:** Optional reverse proxy with automatic SSL certificates
- **VNC Access:** Optional remote desktop access for debugging
- **Swagger Documentation:** Interactive API documentation at `/apidocs/`
- **Structured Logging:** JSON logging for monitoring and debugging

## Architecture

```
Client Application
    ↓ HTTP/REST API
mt5_service (Docker Container)
    ↓ Wine
MT5 Terminal
    ↓ Broker Connection
Live Trading Account
```

**Service Endpoints:**

- **Flask API (v1):** Port 5002 on host → legacy single-account container
- **Flask API (v2):** Port 5010 on host → multi-account gateway
- **VNC (v1):** Port 3001 on host
- **VNC (v2 workers):** Ports 3011 and 3012 on host
- **Traefik:** Ports 80/443 (optional, for HTTPS with domain)

## Multi-Account (v2)

v2 runs **alongside v1** without changing the existing `mt5` service. Account IDs are your **MT5 login numbers**, discovered at runtime after you log in via VNC on each worker.

| Stack | API | VNC |
|---|---|---|
| v1 legacy | `http://localhost:5002` | `http://localhost:3001` |
| v2 gateway | `http://localhost:5010` | — |
| v2 worker 1 | (internal) | `http://localhost:3011` |
| v2 worker 2 | (internal) | `http://localhost:3012` |

**Shortcuts:** [`Makefile`](Makefile) wraps the compose file sets — run `make` or `make help` for targets. Use the same target family for `up` and `down` (e.g. `make up` + `make down`, not bare `docker compose down`).

**Start v1 only (unchanged):**

```bash
make up-v1
```

**Start v1 + v2 together (Linux VPS / production):**

```bash
make up
```

**Apple Silicon Mac (add amd64 emulation overlay):**

```bash
make up-mac
```

**v2 only (after retiring v1):**

```bash
make up-v2
```

**Bootstrap v2 workers:**

1. Open VNC on `:3011` and `:3012`, log into each MT5 account (save password).
2. Discover account IDs (MT5 login numbers):

   ```bash
   curl http://localhost:5010/v2/accounts
   ```

3. Call the v2 API using those login IDs:

   ```bash
   curl http://localhost:5010/v2/accounts/25115284/get_positions
   curl -X POST http://localhost:5010/v2/accounts/25115284/order \
     -H "Content-Type: application/json" \
     -d '{"symbol":"EURUSD","type":"BUY","volume":0.01}'
   ```

**Phase out v1:** stop the `mt5` service when all clients use v2, then optionally map the gateway to port `5002` in [`docker-compose.v2.yml`](docker-compose.v2.yml).

With Traefik, merge [`docker-compose.v2.traefik.yml`](docker-compose.v2.traefik.yml) so `/v2` routes to the gateway while v1 routes stay on the legacy container.

## Prerequisites

- **Docker:** Docker 20.10+ installed. [Install Docker](https://docs.docker.com/get-docker/)
- **Docker Compose:** Docker Compose v2+ for orchestrating services. [Install Docker Compose](https://docs.docker.com/compose/install/)
- **VPS or Local Machine:**
  - **VPS (Recommended):** Linux VPS with 2GB+ RAM (4GB+ for production)
  - **Local Development:** Linux/macOS with Docker Desktop
- **Domain Name (Optional):** Required only if using Traefik with HTTPS
- **MT5 Account:** Demo or live trading account credentials

**Note:** This service is designed to run on a headless Linux VPS. No GUI is required on the host system.

## Quick Start

For local development:

```bash
# Navigate to project directory
cd mt5_service

# Create .env file
cat > .env << EOF
MT5_API_PORT=5001
EOF

# Build and start
docker-compose up -d --build

# Check health
curl http://localhost:5001/health
```

For simplified local setup without Traefik, see [Local Development Setup](docs/LOCAL_SETUP.md).

For VPS deployment, see [VPS Deployment Guide](docs/VPS_DEPLOYMENT.md).

## Installation

### Local Development

For a simplified local setup without Traefik, see [Local Development Setup](docs/LOCAL_SETUP.md).

1. **Navigate to project directory**

   ```bash
   cd mt5_service
   ```
2. **Configure Environment Variables**

   Create a `.env` file:

   ```bash
   cp .env.example .env  # If example exists
   # OR create manually
   nano .env
   ```

   Minimum configuration:

   ```env
   # MT5 API Port
   MT5_API_PORT=5001
   ```

   Full configuration (with Traefik):

   ```env
   # MT5 API Port
   MT5_API_PORT=5001

   # VNC Configuration (optional)
   VNC_DOMAIN=vnc.yourdomain.com
   CUSTOM_USER=admin
   PASSWORD=yourpassword

   # Traefik Configuration (optional, for HTTPS)
   TRAEFIK_DOMAIN=traefik.yourdomain.com
   TRAEFIK_USERNAME=admin
   TRAEFIK_HASHED_PASSWORD=your_hashed_password
   ACME_EMAIL=youremail@example.com
   API_DOMAIN=api.yourdomain.com
   ```
3. **Create Traefik Network (if using Traefik)**

   ```bash
   docker network create traefik-public
   ```
4. **Build and Start Services**

   ```bash
   docker-compose up -d --build
   ```
5. **Verify Installation**

   ```bash
   # Check containers
   docker ps

   # Check logs
   docker-compose logs -f mt5

   # Test API
   curl http://localhost:5001/health
   ```

### VPS Deployment

For production deployment to a VPS, see the comprehensive [VPS Deployment Guide](docs/VPS_DEPLOYMENT.md) which covers:

- VPS provider recommendations
- Docker installation
- Firewall configuration
- Security setup
- Domain configuration
- API integration examples

## Configuration

### Environment Variables

- `CUSTOM_USER`: Username for accessing the MT5 service.
- `PASSWORD`: Password for the custom user.
- `VNC_DOMAIN`: Domain for accessing the VNC service.
- `TRAEFIK_DOMAIN`: Domain for Traefik dashboard.
- `TRAEFIK_USERNAME`: Username for Traefik basic authentication.
- `ACME_EMAIL`: Email address for Let's Encrypt notifications.

### Docker Compose Services

- **Traefik:** Acts as a reverse proxy with HTTPS support.
- **MT5:** Runs MetaTrader 5 using Wine.

### Volumes

- `/var/run/docker.sock`: Allows Traefik to monitor Docker services.
- `./config`: Stores Wine configurations and MT5 data.
- `traefik-public-certificates`: Persists SSL certificates generated by Let's Encrypt.

## Usage

### API Endpoints

The Flask API runs on port 5001 by default. Key endpoints:

**Health & Status:**

- `GET /health` - Health check endpoint
- `GET /last_error` - Get last MT5 error
- `GET /last_error_str` - Get last error as string

**Trading Operations:**

- `POST /order` - Execute market order
- `POST /close_position` - Close specific position
- `POST /close_all_positions` - Close all positions
- `POST /modify_sl_tp` - Modify stop loss/take profit

**Position Management:**

- `GET /get_positions` - Get all open positions
- `GET /positions_total` - Get total position count

**Market Data:**

- `GET /fetch_data_pos` - Fetch historical data from position
- `GET /fetch_data_range` - Fetch data within date range
- `GET /symbol_info_tick/<symbol>` - Get latest tick data
- `GET /symbol_info/<symbol>` - Get symbol information

**History:**

- `GET /get_deal_from_ticket` - Get deal by ticket
- `GET /get_order_from_ticket` - Get order by ticket
- `GET /history_deals_get` - Get deals history
- `GET /history_orders_get` - Get orders history

**API Documentation:**

- `GET /apidocs/` - Swagger interactive documentation

### Accessing Services

1. **Flask API (Primary Interface)**

   ```bash
   # Health check
   curl http://localhost:5001/health

   # Get positions
   curl http://localhost:5001/get_positions

   # Swagger docs
   open http://localhost:5001/apidocs/
   ```
2. **VNC Remote Desktop (Optional)**

   Access at `http://your-vps-ip:3000` or `https://vnc.yourdomain.com` (if using Traefik)

   - Useful for debugging MT5 terminal
   - Not required for API operations
3. **Traefik Dashboard (If using Traefik)**

   Access at `https://traefik.yourdomain.com` with credentials from `.env`

### Managing Services

Use [`Makefile`](Makefile) targets so `down` matches the stack you started (`make help` lists all).

**v1 stack:** `make up-v1` · `make down-v1` · `make logs-v1` · `make restart-v1` · `make build-v1`

**v1 + v2:** `make up` · `make down` · `make logs` · `make build` · `make logs-gateway` · `make logs-worker1`

**Mac v1 + v2:** `make up-mac` · `make down-mac` · `make logs-mac` · `make build-mac`

**Traefik:** `make up-traefik` / `make up-traefik-full` (and matching `down-*`, `logs-traefik*`)

## API Documentation

Interactive Swagger documentation is available at:

- **Local:** `http://localhost:5001/apidocs/`
- **Production:** `https://api.yourdomain.com/apidocs/` (if using Traefik)

The Swagger UI provides:

- Complete API endpoint documentation
- Request/response schemas
- Try-it-out functionality
- Example requests

## Deployment

### Local Development

Run with `docker-compose up -d` for local testing.

### VPS Deployment (Production)

See comprehensive guide: [VPS Deployment Guide](docs/VPS_DEPLOYMENT.md)

**Quick VPS Setup:**

1. Transfer `mt5_service` folder to VPS
2. Install Docker and Docker Compose
3. Configure firewall (open port 5001)
4. Run `docker-compose up -d`
5. Access API at `http://your-vps-ip:5001`

## API Integration

The `mt5_service` exposes a REST API that can be called from any HTTP client.

**Example Configuration:**

```env
# Environment variable for API URL
MT5_API_URL=http://your-vps-ip:5001
# OR with domain
MT5_API_URL=https://api.yourdomain.com
```

**Example Python Client:**

```python
import requests

class MT5Client:
    def __init__(self, api_url: str = None):
        self.api_url = api_url or os.getenv('MT5_API_URL', 'http://localhost:5001')
  
    def place_order(self, symbol: str, side: str, volume: float, **kwargs):
        response = requests.post(
            f"{self.api_url}/order",
            json={
                "symbol": symbol,
                "type": "BUY" if side == "buy" else "SELL",
                "volume": volume,
                **kwargs
            }
        )
        return response.json()
  
    def get_positions(self, magic: int = None):
        params = {"magic": magic} if magic else {}
        response = requests.get(f"{self.api_url}/get_positions", params=params)
        return response.json()
```

See [VPS Deployment Guide - Integration Section](docs/VPS_DEPLOYMENT.md#api-integration) for more examples.

## Logging

The setup uses JSON-file logging with the following configuration:

- **Log Driver:** `json-file`
- **Max Size:** `1m`
- **Max File:** `1`

Logs are managed per service and can be viewed using Docker commands or integrated with external logging solutions like Promtail.

## Troubleshooting

### Common Issues

**Container won't start:**

```bash
# Check logs
docker-compose logs mt5

# Check if port is in use
sudo lsof -i :5001
```

**MT5 not initializing:**

```bash
# Check MT5 installation inside container
docker exec -it mt5 wine64 /config/.wine/drive_c/Program\ Files/MetaTrader\ 5/terminal64.exe --version

# Check setup logs
docker exec -it mt5 cat /var/log/mt5_setup.log
```

**Workers show "Bad EXE format", Rosetta trap, or black VNC screen:**

1. Use [`docker-compose.mac.yml`](docker-compose.mac.yml) on Apple Silicon.
2. Do **not** install Wine via VNC prompts — the image already includes WineHQ; manual installs often create a broken 32-bit prefix.
3. Reset **worker volumes only** on Mac (never prod `./config/.wine` if v1 works):

```bash
make worker-reset-mac
```

4. Watch install: `docker exec mt5-worker-1 tail -f /var/log/mt5_setup.log` — prefix path must show `/config/.wine`, not blank.

**Mac limitation:** MT5 auto-install can still fail under Docker Desktop Rosetta (`rosetta error: invalid gdt selector`). For reliable worker bootstrap, use a **Linux VPS** or copy a working `./config` tree from production into `config/workers/worker-1/`.

**API not accessible from outside:**

```bash
# Check firewall
sudo ufw status
sudo ufw allow 5001/tcp

# Test from VPS itself
curl http://localhost:5001/health
```

**Traefik SSL certificate issues:**

```bash
# Check Traefik logs
docker-compose logs traefik | grep -i certificate

# Verify DNS
nslookup api.yourdomain.com
```

For more detailed troubleshooting, see [VPS Deployment Guide - Troubleshooting](docs/VPS_DEPLOYMENT.md#troubleshooting).

## License

This project is licensed under the [MIT License](LICENSE.md).
