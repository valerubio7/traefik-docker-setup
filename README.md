# Traefik - Reverse Proxy & Load Balancer

Clean, educational configuration of Traefik v3 for development and production environments.

## Quick Start

### Development

```bash
# Clone this repository
cd traefik

# Create and configure environment
cp .env.example .env

# Give execute permissions to scripts
chmod +x scripts/*.sh

# Start Traefik in development
./scripts/start-dev.sh

# Access dashboard
# http://traefik.localhost:8080
```

### Production

```bash
# Configure production environment
nano .env
# Set: PROD_DOMAIN, LETSENCRYPT_EMAIL, TRAEFIK_DASHBOARD_PASSWORD

# Generate secure basic auth password
# htpasswd -nb admin your_secure_password

# Start Traefik in production
./scripts/start-prod.sh

# Access dashboard
# https://traefik.yourdomain.com (requires authentication)
```

## Requirements

- Docker & Docker Compose
- Ports 80, 443 available
- For production: domain pointing to your server

## Project Structure

```
traefik/
├── config/
│   ├── traefik.yml              # Base configuration (common settings)
│   ├── traefik.dev.yml          # Development overrides
│   ├── traefik.prod.yml         # Production overrides
│   └── dynamic/                 # Auto-reloaded configuration
│       ├── middlewares.yml      # Shared middlewares
│       ├── routers.yml          # Reference (use Docker labels instead)
│       ├── tls.yml              # TLS options
│       ├── dev/                 # Development-specific
│       │   ├── certificates.yml # Self-signed certs config
│       │   └── middlewares.yml  # Dev middlewares (CORS permissive)
│       └── prod/                # Production-specific
│           ├── certificates.yml # Let's Encrypt TLS options
│           └── middlewares.yml  # Prod middlewares (strict security)
├── certs/                       # SSL certificates
├── logs/                        # Separate logs per environment
├── scripts/                     # Utility scripts
└── docker-compose*.yml          # Service definitions
```

## Configuration Philosophy

**Minimal by default**: Only essential settings in the base config.

**Clear separation**: Dev and production overrides are explicit and self-documenting.

**Docker labels preferred**: Services define their routes via labels, not static files.

**Educational comments**: Each section explains its purpose.

## Key Concepts

### Entry Points

- **web** (80): HTTP traffic
- **websecure** (443): HTTPS traffic

In production, port 80 automatically redirects to HTTPS.

### Providers

- **Docker**: Auto-discovers containers with `traefik.enable=true` labels
- **File**: Loads dynamic config from `/etc/traefik/dynamic` (auto-reloads on changes)

### Development vs Production

| Aspect | Development | Production |
|--------|-------------|-----------|
| Dashboard | http://traefik.localhost:8080 (insecure) | https://traefik.domain (auth required) |
| Certificates | Self-signed (auto-generated) | Let's Encrypt (auto-renewed) |
| Logging | DEBUG (verbose) | WARN (errors only) |
| CORS | Allow all origins | Restrict to configured origins |
| HTTP redirect | None (direct access) | HTTP→HTTPS redirect |
| Rate limiting | Relaxed | Enabled for dashboard |

## Connecting Services to Traefik

### Basic Service (Development)

```yaml
services:
  myapp:
    image: my-image:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.localhost`)"
      - "traefik.http.routers.myapp.entrypoints=web"
      - "traefik.http.services.myapp.loadbalancer.server.port=3000"

networks:
  traefik-public:
    external: true
```

### Secure Service with HTTPS (Production)

```yaml
services:
  myapp:
    image: my-image:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      
      # HTTPS route
      - "traefik.http.routers.myapp-secure.rule=Host(`myapp.yourdomain.com`)"
      - "traefik.http.routers.myapp-secure.entrypoints=websecure"
      - "traefik.http.routers.myapp-secure.tls=true"
      - "traefik.http.routers.myapp-secure.tls.certresolver=letsencrypt"
      - "traefik.http.routers.myapp-secure.middlewares=security-headers-prod"
      
      # HTTP redirect to HTTPS
      - "traefik.http.routers.myapp.rule=Host(`myapp.yourdomain.com`)"
      - "traefik.http.routers.myapp.entrypoints=web"
      - "traefik.http.routers.myapp.middlewares=redirect-to-https"
      
      # Service backend
      - "traefik.http.services.myapp.loadbalancer.server.port=3000"

networks:
  traefik-public:
    external: true
```

### With Middlewares

```yaml
labels:
  # Apply multiple middlewares
  - "traefik.http.routers.myapp-secure.middlewares=security-headers-prod,compression,rate-limit"
  
  # Or define custom middleware inline (development)
  - "traefik.http.middlewares.myapp-cors.headers.accesscontrolalloworiginlist=http://localhost:3000"
  - "traefik.http.routers.myapp.middlewares=myapp-cors"
```

## Available Middlewares

### Global (all environments)

- **security-headers** - HSTS, X-Frame-Options, CSP, etc.
- **rate-limit** - 30 req/s average, 60 burst
- **rate-limit-strict** - 10 req/s average, 20 burst
- **compression** - gzip/brotli compression
- **retry** - Retry failed requests (3 attempts)
- **redirect-to-https** - HTTP → HTTPS
- **redirect-non-www** - www → non-www redirect
- **ip-whitelist-local** - Allow only local IPs

### Development (config/dynamic/dev/middlewares.yml)

- **cors** - Allow all origins (permissive for local dev)
- **debug-headers** - Mark responses as from dev environment
- **relaxed-security** - No HTTPS enforcement

### Production (config/dynamic/prod/middlewares.yml)

- **security-headers-prod** - Strict security headers + CSP
- **cors-prod** - Restrictive CORS (configure origins per service)

## SSL/TLS Certificates

### Development

- Self-signed certificates for `localhost` and `*.localhost`
- Auto-generated by `scripts/generate-dev-certs.sh`
- Browser shows warning (expected, click "proceed anyway")

### Production

- Let's Encrypt certificates (fully automated)
- Stored in `certs/prod/acme.json` (chmod 600)
- Auto-renewed every 60 days
- Supports wildcard certificates (`*.yourdomain.com`)

## Scripts

```bash
./scripts/start-dev.sh              # Start Traefik in development mode
./scripts/start-prod.sh             # Start Traefik in production mode (with confirmation)
./scripts/stop.sh                   # Stop Traefik (auto-detects environment)
./scripts/logs.sh                   # View real-time logs
./scripts/generate-dev-certs.sh     # Generate self-signed certificates
./scripts/common.sh                 # Shared utility functions (source in other scripts)
```

## Common Tasks

### View Logs

```bash
./scripts/logs.sh

# Or directly
docker compose logs -f traefik
```

### Verify Container Status

```bash
docker ps | grep traefik
docker inspect traefik --format '{{.State.Health.Status}}'
```

### Check Network

```bash
docker network ls | grep traefik
docker network inspect traefik-public
```

### Restart Traefik

```bash
./scripts/stop.sh
./scripts/start-dev.sh   # or start-prod.sh
```

### Fix Certificate Permissions (production)

```bash
chmod 600 certs/prod/acme.json
```

## Troubleshooting

### Dashboard not accessible

```bash
# Check if container is running
docker ps | grep traefik

# View recent logs
docker compose logs traefik --tail=50

# Verify network exists
docker network inspect traefik-public
```

### Service not appearing in Traefik

1. Verify container has correct labels: `docker inspect mycontainer | grep traefik`
2. Verify container is on `traefik-public` network: `docker network inspect traefik-public`
3. Check service health: `docker ps mycontainer`
4. View Traefik logs: `./scripts/logs.sh`

### Let's Encrypt certificate not generating (production)

1. Verify domain points to your server
2. Ensure ports 80 and 443 are open: `netstat -tlnp | grep ':80\|:443'`
3. Check email in `.env`
4. View logs for ACME errors: `./scripts/logs.sh | grep acme`

### Port conflicts

```bash
# Find what's using port 80/443
netstat -tlnp | grep ':80\|:443'
ss -tlnp | grep ':80\|:443'

# Kill the process or use different ports in .env
```

## Security Best Practices

### Development

- Dashboard accessible only on localhost
- Self-signed certificates (browser warnings expected)
- CORS permissive (all origins allowed)
- Debug logging enabled

### Production

- Dashboard requires authentication
- Let's Encrypt certificates (valid for all browsers)
- CORS restrictive (only configured origins)
- Only errors/warnings in logs
- Rate limiting on dashboard
- Strict security headers
- All services redirect HTTP → HTTPS

## Environment Variables

Create `.env` from `.env.example` and configure:

**Common**
- `TZ` - Timezone (default: UTC)
- `HTTP_PORT` - HTTP port (default: 80)
- `HTTPS_PORT` - HTTPS port (default: 443)
- `DEV_DOMAIN` - Development domain (default: localhost)
- `LOG_LEVEL` - Log level for dev (default: DEBUG)

**Production only**
- `PROD_DOMAIN` - Your production domain (required)
- `LETSENCRYPT_EMAIL` - Email for certificate notifications (required)
- `TRAEFIK_DASHBOARD_USER` - Dashboard username (default: admin)
- `TRAEFIK_DASHBOARD_PASSWORD` - Basic auth password hash (required)

Generate password hash:

```bash
htpasswd -nb admin your_password
# Output: admin:$apr1$...
```

## Performance Tuning

### For high traffic

1. Increase rate limits in `config/dynamic/middlewares.yml`
2. Adjust Docker engine limits
3. Use `buffering` middleware for large requests/responses
4. Consider dedicated networks for different service groups

### For low resource environments

1. Reduce log buffering size
2. Disable compression for small responses
3. Use simpler TLS options (avoid modern profile)

## Resources

- [Official Traefik Documentation](https://doc.traefik.io/traefik/)
- [Traefik Middlewares](https://doc.traefik.io/traefik/middlewares/overview/)
- [Docker Provider](https://doc.traefik.io/traefik/providers/docker/)
- [Let's Encrypt Integration](https://doc.traefik.io/traefik/https/acme/)
- [TLS/HTTPS Configuration](https://doc.traefik.io/traefik/https/overview/)

## Tips for Learning

1. **Start with development**: Use `./scripts/start-dev.sh` to get familiar with the basics
2. **Read the comments**: YAML files include explanations
3. **Use Docker labels**: Easier to understand than static config files
4. **Monitor logs**: `./scripts/logs.sh` shows everything
5. **Experiment with middlewares**: Add/remove to see effects immediately
6. **Check official docs**: For advanced features not covered here

## License & Attribution

This is a clean, educational reference implementation of Traefik v3 configuration.
