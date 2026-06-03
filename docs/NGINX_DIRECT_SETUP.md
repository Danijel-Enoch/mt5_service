# Nginx Direct Setup (Without Traefik)

This guide explains how to configure nginx to directly proxy to the MT5 services with SSL certificates using certbot.

## Overview

With this setup, nginx directly handles:
- Domain routing (api.mt5.bawembye.com, vnc.mt5.bawembye.com)
- SSL/TLS certificates (via certbot/Let's Encrypt)
- HTTP to HTTPS redirects
- Reverse proxying to Flask API v1 (port 5002), Flask API v2 (port 5010), and VNC (ports 3001, 3011, 3012)

## Prerequisites

- Docker containers running with ports 5002 (API v1), 5010 (API v2), 3001 (v1 VNC), 3011 and 3012 (v2 worker VNC) exposed on the host
- DNS records pointing to your VPS IP
- Certbot installed: `sudo apt install certbot python3-certbot-nginx`

## Check for Port Conflicts

Before starting, check if ports 5002 and 3001 are already in use:

```bash
# Check if ports are in use
sudo lsof -i :5002
sudo lsof -i :3001

# Or using ss
ss -tlnp | grep -E ":5002|:3001"

# Or using netstat (if installed)
netstat -tlnp | grep -E ":5002|:3001"
```

**Note:** We use ports 5002 (API) and 3001 (VNC) on the host to avoid conflicts with common services. The containers still use 5001 and 3000 internally.

## Step 1: Install Certbot

```bash
sudo apt update
sudo apt install certbot python3-certbot-nginx
```

## Step 2: Create Nginx Configuration

Create `/etc/nginx/conf.d/mt5-services.conf`:

```nginx
# API Service v1 (api.mt5.bawembye.com) — legacy single-account routes
server {
    listen 80;
    server_name api.mt5.bawembye.com;
    
    location /v2/ {
        proxy_pass http://localhost:5010;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location / {
        proxy_pass http://localhost:5002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeout settings
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# VNC Service (vnc.mt5.bawembye.com)
server {
    listen 80;
    server_name vnc.mt5.bawembye.com;
    
    location / {
        proxy_pass http://localhost:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support for VNC
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeout settings
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

## Step 3: Test and Reload Nginx

```bash
# Test nginx configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

## Step 4: Obtain SSL Certificates

Use certbot to automatically obtain and configure SSL certificates:

```bash
# Get certificates for all domains
sudo certbot --nginx -d api.mt5.bawembye.com -d vnc.mt5.bawembye.com

# Follow the prompts:
# - Enter your email address
# - Agree to terms of service
# - Choose whether to redirect HTTP to HTTPS (recommended: Yes)
```

Certbot will automatically:
- Obtain Let's Encrypt certificates
- Update your nginx configuration with SSL settings
- Set up automatic renewal

## Step 5: Verify SSL Certificates

```bash
# Check certificate status
sudo certbot certificates

# Test SSL
curl https://api.mt5.bawembye.com/health
curl -I https://vnc.mt5.bawembye.com
```

## Step 6: Auto-Renewal

Certbot sets up automatic renewal. Test it:

```bash
# Test renewal process (dry run)
sudo certbot renew --dry-run
```

## Final Nginx Configuration

After certbot runs, your nginx config will look like this (certbot modifies it automatically):

```nginx
# API Service
server {
    listen 80;
    server_name api.mt5.bawembye.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.mt5.bawembye.com;
    
    ssl_certificate /etc/letsencrypt/live/api.mt5.bawembye.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.mt5.bawembye.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    
    location / {
        proxy_pass http://localhost:5002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# VNC Service
server {
    listen 80;
    server_name vnc.mt5.bawembye.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name vnc.mt5.bawembye.com;
    
    ssl_certificate /etc/letsencrypt/live/vnc.mt5.bawembye.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/vnc.mt5.bawembye.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    
    location / {
        proxy_pass http://localhost:3001;  # Change if using custom MT5_VNC_PORT
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

## Troubleshooting

### Check if services are accessible

```bash
# Test API
curl http://localhost:5002/health

# Test VNC (should return HTML)
curl http://localhost:3001
```

### Check nginx logs

```bash
# Error logs
sudo tail -f /var/log/nginx/error.log

# Access logs
sudo tail -f /var/log/nginx/access.log
```

### Verify DNS

```bash
# Check DNS resolution
nslookup api.mt5.bawembye.com
nslookup vnc.mt5.bawembye.com
```

## Removing Old Traefik Configuration

If you previously had Traefik setup, remove the old nginx config:

```bash
# Remove old Traefik proxy config
sudo rm /etc/nginx/conf.d/mt5-traefik.conf

# Remove self-signed certificates (if not needed)
sudo rm -rf /etc/nginx/ssl/

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

## Benefits of This Setup

- **Simpler**: One less service (no Traefik)
- **Direct**: nginx → services (no double proxy)
- **Standard**: Common nginx + certbot pattern
- **Easier to debug**: Fewer moving parts
- **Better performance**: One less hop

## Cleanup: Removing MT5 Nginx Configuration

If you need to remove the MT5 nginx configuration (e.g., when stopping use of the VPS or cleaning up):

### Step 1: Revoke SSL Certificates (Optional but Recommended)

```bash
# Revoke certificates to free up Let's Encrypt rate limits
sudo certbot revoke --cert-path /etc/letsencrypt/live/api.mt5.bawembye.com/cert.pem
sudo certbot revoke --cert-path /etc/letsencrypt/live/vnc.mt5.bawembye.com/cert.pem

# Or revoke all certificates for a domain
sudo certbot revoke --cert-name api.mt5.bawembye.com
sudo certbot revoke --cert-name vnc.mt5.bawembye.com
```

### Step 2: Remove Nginx Configuration

```bash
# Remove the MT5 nginx config file
sudo rm /etc/nginx/conf.d/mt5-services.conf

# Test nginx configuration
sudo nginx -t

# Reload nginx to apply changes
sudo systemctl reload nginx
```

### Step 3: Remove SSL Certificates (Optional)

```bash
# Remove Let's Encrypt certificates and configuration
sudo rm -rf /etc/letsencrypt/live/api.mt5.bawembye.com
sudo rm -rf /etc/letsencrypt/live/vnc.mt5.bawembye.com
sudo rm -rf /etc/letsencrypt/archive/api.mt5.bawembye.com
sudo rm -rf /etc/letsencrypt/archive/vnc.mt5.bawembye.com
sudo rm -rf /etc/letsencrypt/renewal/api.mt5.bawembye.com.conf
sudo rm -rf /etc/letsencrypt/renewal/vnc.mt5.bawembye.com.conf
```

### Step 4: Stop and Remove Docker Containers

```bash
# Stop and remove containers
cd ~/apps/tdev/mt5_service  # or wherever your project is
docker compose down

# Remove volumes (if you want to delete all data)
docker compose down -v

# Remove the built image (optional)
docker rmi mt5_service-mt5
```

### Step 5: Remove Docker Network (if not used by other services)

```bash
# Check if network exists and is used
docker network ls | grep mt5_service

# Remove network (only if not used elsewhere)
docker network rm mt5_service_default
```

### Step 6: Clean Up Project Files (Optional)

```bash
# Remove project directory (if you want to completely remove)
# WARNING: This will delete all project files and data
rm -rf ~/apps/tdev/mt5_service
```

### Complete Cleanup Checklist

- [ ] Revoke SSL certificates (optional)
- [ ] Remove nginx configuration file
- [ ] Test and reload nginx
- [ ] Remove SSL certificate files (optional)
- [ ] Stop Docker containers
- [ ] Remove Docker volumes (if needed)
- [ ] Remove Docker network (if not used elsewhere)
- [ ] Remove project directory (if completely cleaning up)

### Verification

After cleanup, verify everything is removed:

```bash
# Check nginx configs
ls -la /etc/nginx/conf.d/ | grep mt5

# Check certificates
sudo certbot certificates | grep mt5

# Check Docker containers
docker ps -a | grep mt5

# Check Docker networks
docker network ls | grep mt5
```

All commands should return no results if cleanup is complete.
