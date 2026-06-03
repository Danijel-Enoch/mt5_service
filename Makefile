COMPOSE := docker compose

FILES_V1 := -f docker-compose.yml
FILES_FULL := -f docker-compose.yml -f docker-compose.v2.yml
FILES_MAC := $(FILES_FULL) -f docker-compose.mac.yml
FILES_V2 := -f docker-compose.v2.yml
FILES_TRAEFIK := -f docker-compose.yml -f docker-compose.traefik.yml
FILES_TRAEFIK_FULL := $(FILES_TRAEFIK) -f docker-compose.v2.yml -f docker-compose.v2.traefik.yml

.PHONY: help
help:
	@echo "MT5 service — Docker Compose shortcuts"
	@echo ""
	@echo "  v1 only:     make up-v1 / down-v1 / logs-v1"
	@echo "  v1 + v2:     make up / down / logs          (Linux VPS / production)"
	@echo "  Mac (v1+v2): make up-mac / down-mac / logs-mac"
	@echo "  v2 only:     make up-v2 / down-v2 / logs-v2"
	@echo "  Traefik:     make up-traefik / up-traefik-full (+ matching down-*)"
	@echo ""
	@echo "  make ps-mt5            containers for this compose project"
	@echo "  make worker-reset-mac  reset worker Wine prefixes (Mac troubleshooting)"

# --- v1 only ---

.PHONY: up-v1 down-v1 logs-v1 build-v1 restart-v1
up-v1:
	$(COMPOSE) $(FILES_V1) up -d

down-v1:
	$(COMPOSE) $(FILES_V1) down

logs-v1:
	$(COMPOSE) $(FILES_V1) logs -f

build-v1:
	$(COMPOSE) $(FILES_V1) up -d --build

restart-v1:
	$(COMPOSE) $(FILES_V1) restart mt5

# --- v1 + v2 (Linux / production) ---

.PHONY: up down logs build restart
up:
	$(COMPOSE) $(FILES_FULL) up -d --build

down:
	$(COMPOSE) $(FILES_FULL) down

logs:
	$(COMPOSE) $(FILES_FULL) logs -f

build:
	$(COMPOSE) $(FILES_FULL) up -d --build

.PHONY: logs-gateway logs-worker1 logs-worker2
logs-gateway:
	$(COMPOSE) $(FILES_FULL) logs -f mt5-gateway

logs-worker1:
	$(COMPOSE) $(FILES_FULL) logs -f mt5-worker-1

logs-worker2:
	$(COMPOSE) $(FILES_FULL) logs -f mt5-worker-2

# --- v1 + v2 on Apple Silicon ---

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

# --- v2 only ---

.PHONY: up-v2 down-v2 logs-v2 build-v2
up-v2:
	$(COMPOSE) $(FILES_V2) up -d

down-v2:
	$(COMPOSE) $(FILES_V2) down

logs-v2:
	$(COMPOSE) $(FILES_V2) logs -f

build-v2:
	$(COMPOSE) $(FILES_V2) up -d --build

# --- Traefik ---

.PHONY: up-traefik down-traefik logs-traefik up-traefik-full down-traefik-full logs-traefik-full
up-traefik:
	$(COMPOSE) $(FILES_TRAEFIK) up -d --build

down-traefik:
	$(COMPOSE) $(FILES_TRAEFIK) down

logs-traefik:
	$(COMPOSE) $(FILES_TRAEFIK) logs -f traefik

up-traefik-full:
	$(COMPOSE) $(FILES_TRAEFIK_FULL) up -d --build

down-traefik-full:
	$(COMPOSE) $(FILES_TRAEFIK_FULL) down

logs-traefik-full:
	$(COMPOSE) $(FILES_TRAEFIK_FULL) logs -f

# --- misc ---

PROJECT := $(notdir $(CURDIR))

.PHONY: ps-mt5
ps-mt5:
	docker ps -a --filter "label=com.docker.compose.project=$(PROJECT)" \
		--format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
