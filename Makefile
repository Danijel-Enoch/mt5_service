COMPOSE := docker compose

FILES := -f docker-compose.yml
FILES_TRAEFIK := $(FILES) -f docker-compose.traefik.yml
FILES_MAC := $(FILES) -f docker-compose.mac.yml

.PHONY: help
help:
	@echo "MT5 service — Docker Compose shortcuts"
	@echo ""
	@echo "  Default:     make up / down / logs          (no Traefik — use nginx or host ports)"
	@echo "  Mac:         make up-mac / down-mac / logs-mac / build-mac"
	@echo "  Optional:    make up-traefik / down-traefik  (only if using Traefik)"
	@echo ""
	@echo "  make ps-mt5            containers for this compose project"
	@echo "  make restart-workers   restart workers after VNC MT5 login (API attach)"
	@echo "  make verify            curl gateway /health and /accounts"
	@echo "  make worker-reset-mac  reset worker Wine prefixes (Mac troubleshooting)"

.PHONY: up down logs build restart-gateway restart-workers verify
up:
	$(COMPOSE) $(FILES) up -d --build

down:
	$(COMPOSE) $(FILES) down

logs:
	$(COMPOSE) $(FILES) logs -f

build:
	$(COMPOSE) $(FILES) up -d --build

restart-gateway:
	$(COMPOSE) $(FILES) restart mt5-gateway

restart-workers:
	$(COMPOSE) $(FILES) restart mt5-worker-1 mt5-worker-2

verify:
	@curl -sS http://localhost:5002/health; echo
	@curl -sS http://localhost:5002/accounts; echo

.PHONY: logs-gateway logs-worker1 logs-worker2
logs-gateway:
	$(COMPOSE) $(FILES) logs -f mt5-gateway

logs-worker1:
	$(COMPOSE) $(FILES) logs -f mt5-worker-1

logs-worker2:
	$(COMPOSE) $(FILES) logs -f mt5-worker-2

.PHONY: up-mac down-mac logs-mac build-mac worker-reset-mac
up-mac:
	$(COMPOSE) $(FILES_MAC) up -d --build

down-mac:
	$(COMPOSE) $(FILES_MAC) down

logs-mac:
	$(COMPOSE) $(FILES_MAC) logs -f

build-mac:
	$(COMPOSE) $(FILES_MAC) up -d --build

worker-reset-mac: down-mac
	rm -rf config/workers/worker-1/.wine config/workers/worker-2/.wine
	$(COMPOSE) $(FILES_MAC) up -d --build

.PHONY: up-traefik down-traefik logs-traefik
up-traefik:
	$(COMPOSE) $(FILES_TRAEFIK) up -d --build

down-traefik:
	$(COMPOSE) $(FILES_TRAEFIK) down

logs-traefik:
	$(COMPOSE) $(FILES_TRAEFIK) logs -f

PROJECT := $(notdir $(CURDIR))

.PHONY: ps-mt5
ps-mt5:
	docker ps -a --filter "label=com.docker.compose.project=$(PROJECT)" \
		--format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
