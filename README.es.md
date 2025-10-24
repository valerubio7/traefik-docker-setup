# Traefik - Proxy Inverso y Balanceador de Carga

Configuración limpia y educativa de Traefik v3 para entornos de desarrollo y producción.

## Inicio Rápido

### Desarrollo

```bash
# Clonar este repositorio
cd traefik

# Crear y configurar el ambiente
cp .env.example .env

# Dar permisos de ejecución a los scripts
chmod +x scripts/*.sh

# Iniciar Traefik en desarrollo
./scripts/start-dev.sh

# Acceder al dashboard
# http://localhost:8080/dashboard/
```

### Producción

```bash
# Configurar el ambiente de producción
nano .env
# Configurar: PROD_DOMAIN, LETSENCRYPT_EMAIL, TRAEFIK_DASHBOARD_PASSWORD

# Generar contraseña de autenticación básica segura
# htpasswd -nb admin tu_contraseña_segura

# Iniciar Traefik en producción
./scripts/start-prod.sh

# Acceder al dashboard
# https://traefik.tudominio.com (requiere autenticación)
```

## Requisitos

- Docker y Docker Compose
- Puertos 80 y 443 disponibles
- Para producción: dominio apuntando a tu servidor

## Estructura del Proyecto

```
traefik/
├── config/
│   ├── traefik.yml              # Configuración base (opciones comunes)
│   ├── traefik.dev.yml          # Sobrescrituras de desarrollo
│   ├── traefik.prod.yml         # Sobrescrituras de producción
│   └── dynamic/                 # Configuración recargada automáticamente
│       ├── middlewares.yml      # Middlewares compartidos
│       ├── routers.yml          # Referencia (usar etiquetas Docker en su lugar)
│       ├── tls.yml              # Opciones TLS
│       ├── dev/                 # Específicos de desarrollo
│       │   ├── certificates.yml # Config de certificados auto-firmados
│       │   └── middlewares.yml  # Middlewares de desarrollo (CORS permisivo)
│       └── prod/                # Específicos de producción
│           ├── certificates.yml # Opciones TLS de Let's Encrypt
│           └── middlewares.yml  # Middlewares de producción (seguridad estricta)
├── certs/                       # Certificados SSL
├── logs/                        # Logs separados por ambiente
├── scripts/                     # Scripts de utilidad
└── docker-compose*.yml          # Definiciones de servicios
```

## Filosofía de Configuración

**Mínimo por defecto**: Solo configuraciones esenciales en la configuración base.

**Separación clara**: Las sobrescrituras de desarrollo y producción son explícitas y autodocumentadas.

**Etiquetas Docker preferidas**: Los servicios definen sus rutas mediante etiquetas, no archivos estáticos.

**Comentarios educativos**: Cada sección explica su propósito.

## Conceptos Clave

### Puntos de Entrada

- **web** (80): Tráfico HTTP
- **websecure** (443): Tráfico HTTPS

En producción, el puerto 80 se redirige automáticamente a HTTPS.

### Proveedores

- **Docker**: Descubre automáticamente contenedores con etiquetas `traefik.enable=true`
- **Archivo**: Carga configuración dinámica desde `/etc/traefik/dynamic` (se recarga automáticamente)

### Desarrollo vs Producción

| Aspecto | Desarrollo | Producción |
|---------|-----------|-----------|
| Dashboard | http://localhost:8080 (inseguro) | https://traefik.dominio (auth requerida) |
| Certificados | Auto-firmados (generados automáticamente) | Let's Encrypt (renovados automáticamente) |
| Logging | DEBUG (verboso) | WARN (solo errores) |
| CORS | Permitir todos los orígenes | Restringir a orígenes configurados |
| Redirección HTTP | Ninguna (acceso directo) | HTTP→HTTPS |
| Rate limiting | Relajado | Habilitado en dashboard |

## Conectar Servicios a Traefik

### Servicio Básico (Desarrollo)

```yaml
services:
  miapp:
    image: mi-imagen:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.miapp.rule=Host(`miapp.localhost`)"
      - "traefik.http.routers.miapp.entrypoints=web"
      - "traefik.http.services.miapp.loadbalancer.server.port=3000"

networks:
  traefik-public:
    external: true
```

### Servicio Seguro con HTTPS (Producción)

```yaml
services:
  miapp:
    image: mi-imagen:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      
      # Ruta HTTPS
      - "traefik.http.routers.miapp-secure.rule=Host(`miapp.tudominio.com`)"
      - "traefik.http.routers.miapp-secure.entrypoints=websecure"
      - "traefik.http.routers.miapp-secure.tls=true"
      - "traefik.http.routers.miapp-secure.tls.certresolver=letsencrypt"
      - "traefik.http.routers.miapp-secure.middlewares=security-headers-prod"
      
      # Redirección HTTP a HTTPS
      - "traefik.http.routers.miapp.rule=Host(`miapp.tudominio.com`)"
      - "traefik.http.routers.miapp.entrypoints=web"
      - "traefik.http.routers.miapp.middlewares=redirect-to-https"
      
      # Backend del servicio
      - "traefik.http.services.miapp.loadbalancer.server.port=3000"

networks:
  traefik-public:
    external: true
```

### Con Middlewares

```yaml
labels:
  # Aplicar múltiples middlewares
  - "traefik.http.routers.miapp-secure.middlewares=security-headers-prod,compression,rate-limit"
  
  # O definir middleware personalizado inline (desarrollo)
  - "traefik.http.middlewares.miapp-cors.headers.accesscontrolalloworiginlist=http://localhost:3000"
  - "traefik.http.routers.miapp.middlewares=miapp-cors"
```

## Middlewares Disponibles

### Global (todos los ambientes)

- **security-headers** - HSTS, X-Frame-Options, CSP, etc.
- **rate-limit** - 30 req/s promedio, 60 ráfaga
- **rate-limit-strict** - 10 req/s promedio, 20 ráfaga
- **compression** - Compresión gzip/brotli
- **retry** - Reintentar solicitudes fallidas (3 intentos)
- **redirect-to-https** - HTTP → HTTPS
- **redirect-non-www** - www → sin-www
- **ip-whitelist-local** - Permitir solo IPs locales

### Desarrollo (config/dynamic/dev/middlewares.yml)

- **cors** - Permitir todos los orígenes (permisivo para dev local)
- **debug-headers** - Marcar respuestas como del ambiente de desarrollo
- **relaxed-security** - Sin aplicación de HTTPS

### Producción (config/dynamic/prod/middlewares.yml)

- **security-headers-prod** - Encabezados de seguridad estrictos + CSP
- **cors-prod** - CORS restrictivo (configurar orígenes por servicio)

## Certificados SSL/TLS

### Desarrollo

- Certificados auto-firmados para `localhost` y `*.localhost`
- Generados automáticamente por `scripts/generate-dev-certs.sh`
- El navegador muestra advertencia (esperado, hacer clic en "continuar de todas formas")

### Producción

- Certificados Let's Encrypt (completamente automatizados)
- Almacenados en `certs/prod/acme.json` (chmod 600)
- Se renuevan automáticamente cada 60 días
- Soporta certificados comodín (`*.tudominio.com`)

## Scripts

```bash
./scripts/start-dev.sh              # Iniciar Traefik en modo desarrollo
./scripts/start-prod.sh             # Iniciar Traefik en modo producción (con confirmación)
./scripts/stop.sh                   # Detener Traefik (detecta ambiente automáticamente)
./scripts/logs.sh                   # Ver logs en tiempo real
./scripts/generate-dev-certs.sh     # Generar certificados auto-firmados
./scripts/common.sh                 # Funciones de utilidad compartidas (source en otros scripts)
```

## Tareas Comunes

### Ver Logs

```bash
./scripts/logs.sh

# O directamente
docker compose logs -f traefik
```

### Verificar Estado del Contenedor

```bash
docker ps | grep traefik
docker inspect traefik --format '{{.State.Health.Status}}'
```

### Verificar Red

```bash
docker network ls | grep traefik
docker network inspect traefik-public
```

### Reiniciar Traefik

```bash
./scripts/stop.sh
./scripts/start-dev.sh   # o start-prod.sh
```

### Arreglar Permisos de Certificados (producción)

```bash
chmod 600 certs/prod/acme.json
```

## Solución de Problemas

### Dashboard no es accesible

```bash
# Verificar si el contenedor está corriendo
docker ps | grep traefik

# Ver logs recientes
docker compose logs traefik --tail=50

# Verificar que la red existe
docker network inspect traefik-public
```

### El servicio no aparece en Traefik

1. Verificar que el contenedor tenga etiquetas correctas: `docker inspect micontenedor | grep traefik`
2. Verificar que el contenedor esté en la red `traefik-public`: `docker network inspect traefik-public`
3. Verificar salud del servicio: `docker ps micontenedor`
4. Ver logs de Traefik: `./scripts/logs.sh`

### Certificado de Let's Encrypt no se genera (producción)

1. Verificar que el dominio apunte a tu servidor
2. Asegurar que los puertos 80 y 443 estén abiertos: `netstat -tlnp | grep ':80\|:443'`
3. Verificar email en `.env`
4. Ver logs para errores ACME: `./scripts/logs.sh | grep acme`

### Conflictos de puertos

```bash
# Encontrar qué está usando puerto 80/443
netstat -tlnp | grep ':80\|:443'
ss -tlnp | grep ':80\|:443'

# Matar el proceso o usar puertos diferentes en .env
```

## Mejores Prácticas de Seguridad

### Desarrollo

- Dashboard accesible solo en localhost
- Certificados auto-firmados (advertencias del navegador esperadas)
- CORS permisivo (todos los orígenes permitidos)
- Logging de depuración habilitado

### Producción

- Dashboard requiere autenticación
- Certificados Let's Encrypt (válidos para todos los navegadores)
- CORS restrictivo (solo orígenes configurados)
- Solo errores/advertencias en logs
- Rate limiting en dashboard
- Encabezados de seguridad estrictos
- Todos los servicios redirigen HTTP → HTTPS

## Variables de Entorno

Crear `.env` desde `.env.example` y configurar:

**Comunes**
- `TZ` - Zona horaria (default: UTC)
- `HTTP_PORT` - Puerto HTTP (default: 80)
- `HTTPS_PORT` - Puerto HTTPS (default: 443)
- `DEV_DOMAIN` - Dominio de desarrollo (default: localhost)
- `LOG_LEVEL` - Nivel de log para dev (default: DEBUG)

**Solo producción**
- `PROD_DOMAIN` - Tu dominio de producción (requerido)
- `LETSENCRYPT_EMAIL` - Email para notificaciones de certificados (requerido)
- `TRAEFIK_DASHBOARD_USER` - Nombre de usuario del dashboard (default: admin)
- `TRAEFIK_DASHBOARD_PASSWORD` - Hash de contraseña de autenticación básica (requerido)

Generar hash de contraseña:

```bash
htpasswd -nb admin tu_contraseña
# Output: admin:$apr1$...
```

## Ajuste de Rendimiento

### Para tráfico alto

1. Aumentar límites de rate en `config/dynamic/middlewares.yml`
2. Ajustar límites del motor Docker
3. Usar middleware `buffering` para solicitudes/respuestas grandes
4. Considerar redes dedicadas para diferentes grupos de servicios

### Para ambientes con recursos limitados

1. Reducir tamaño del buffer de logs
2. Desactivar compresión para respuestas pequeñas
3. Usar opciones TLS más simples (evitar perfil moderno)

## Recursos

- [Documentación Oficial de Traefik](https://doc.traefik.io/traefik/)
- [Middlewares de Traefik](https://doc.traefik.io/traefik/middlewares/overview/)
- [Proveedor Docker](https://doc.traefik.io/traefik/providers/docker/)
- [Integración Let's Encrypt](https://doc.traefik.io/traefik/https/acme/)
- [Configuración TLS/HTTPS](https://doc.traefik.io/traefik/https/overview/)

## Consejos para Aprender

1. **Comienza con desarrollo**: Usa `./scripts/start-dev.sh` para familiarizarte con lo básico
2. **Lee los comentarios**: Los archivos YAML incluyen explicaciones
3. **Usa etiquetas Docker**: Más fácil de entender que archivos de configuración estática
4. **Monitorea logs**: `./scripts/logs.sh` muestra todo
5. **Experimenta con middlewares**: Agregar/remover para ver efectos inmediatamente
6. **Consulta docs oficiales**: Para características avanzadas no cubiertas aquí

## Licencia y Atribución

Esta es una implementación de referencia limpia y educativa de la configuración de Traefik v3.
