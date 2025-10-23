# Traefik Global - Reverse Proxy

Configuración centralizada de Traefik para todos los proyectos (desarrollo y producción).

## 🚀 Inicio Rápido

### Desarrollo

```bash
# 1. Clonar/copiar este directorio
cd traefik

# 2. Copiar y configurar variables de entorno
cp .env.example .env
# Editar .env con tus valores

# 3. Dar permisos a los scripts
chmod +x scripts/*.sh

# 4. Iniciar Traefik
./scripts/start-dev.sh

# 5. Acceder al dashboard
# http://traefik.localhost:8080
```

### Producción

```bash
# 1. Configurar .env con valores de producción
nano .env
# IMPORTANTE: 
# - Cambiar PROD_DOMAIN
# - Configurar LETSENCRYPT_EMAIL
# - Generar password hash: htpasswd -nb admin tu_password

# 2. Iniciar Traefik
./scripts/start-prod.sh

# 3. Acceder al dashboard
# https://traefik.tudominio.com (requiere autenticación)
```

## 📋 Requisitos

- Docker y Docker Compose instalados
- Puertos 80, 443 y 8080 disponibles
- Para producción: dominio apuntando a tu servidor

## 🏗️ Estructura del Proyecto

```
traefik/
├── config/
│   ├── traefik.yml          # Configuración base
│   ├── traefik.dev.yml      # Override para desarrollo
│   ├── traefik.prod.yml     # Override para producción
│   └── dynamic/             # Configuración que se recarga automáticamente
│       ├── middlewares.yml  # Middlewares reutilizables
│       ├── tls.yml          # Configuración TLS
│       ├── dev/             # Específico de desarrollo
│       └── prod/            # Específico de producción
├── certs/                   # Certificados SSL
├── logs/                    # Logs separados por ambiente
└── scripts/                 # Scripts de utilidad
```

## 🔧 Scripts Disponibles

| Script | Descripción |
|--------|-------------|
| `./scripts/start-dev.sh` | Inicia Traefik en desarrollo |
| `./scripts/start-prod.sh` | Inicia Traefik en producción |
| `./scripts/stop.sh` | Detiene Traefik |
| `./scripts/logs.sh` | Ver logs en tiempo real |
| `./scripts/generate-dev-certs.sh` | Genera certificados SSL para desarrollo |

## 🔗 Conectar Proyectos a Traefik

### Paso 1: Conectar a la red

En el `docker-compose.yml` de tu proyecto:

```yaml
services:
  tu-app:
    image: tu-imagen
    networks:
      - traefik-public
    labels:
      # Habilitar Traefik para este contenedor
      - "traefik.enable=true"
      
      # Router HTTP
      - "traefik.http.routers.tu-app.rule=Host(`tu-app.localhost`)"
      - "traefik.http.routers.tu-app.entrypoints=web"
      
      # Servicio (puerto interno del contenedor)
      - "traefik.http.services.tu-app.loadbalancer.server.port=3000"

networks:
  traefik-public:
    external: true
```

### Paso 2: Para HTTPS en producción

```yaml
labels:
  - "traefik.enable=true"
  
  # Router HTTPS
  - "traefik.http.routers.tu-app-secure.rule=Host(`tu-app.tudominio.com`)"
  - "traefik.http.routers.tu-app-secure.entrypoints=websecure"
  - "traefik.http.routers.tu-app-secure.tls=true"
  - "traefik.http.routers.tu-app-secure.tls.certresolver=letsencrypt"
  
  # Router HTTP (redirige a HTTPS)
  - "traefik.http.routers.tu-app.rule=Host(`tu-app.tudominio.com`)"
  - "traefik.http.routers.tu-app.entrypoints=web"
  - "traefik.http.routers.tu-app.middlewares=redirect-to-https"
  
  # Servicio
  - "traefik.http.services.tu-app.loadbalancer.server.port=3000"
  
  # Middlewares opcionales
  - "traefik.http.routers.tu-app-secure.middlewares=security-headers,compression"
```

### Paso 3: Usar middlewares

```yaml
labels:
  # Aplicar múltiples middlewares
  - "traefik.http.routers.tu-app-secure.middlewares=security-headers,compression,rate-limit"
  
  # O crear middleware personalizado
  - "traefik.http.middlewares.tu-app-cors.headers.accesscontrolalloworiginlist=https://tudominio.com"
  - "traefik.http.routers.tu-app-secure.middlewares=tu-app-cors"
```

## 📝 Middlewares Disponibles

Los siguientes middlewares están pre-configurados en `config/dynamic/middlewares.yml`:

### Seguridad
- `security-headers` - Headers de seguridad HTTP
- `ip-whitelist-local` - Restricción por IP local

### Performance
- `compression` - Compresión gzip/brotli
- `rate-limit` - Limitador de requests (100/s)
- `rate-limit-strict` - Limitador estricto (10/s)

### CORS
- `cors-headers` - CORS permisivo (dev)
- `prod-cors` - CORS restrictivo (prod)

### Otros
- `redirect-to-https` - Redirección HTTP → HTTPS
- `redirect-non-www` - Redirección www → non-www
- `retry` - Reintentos automáticos
- `buffering` - Para uploads grandes

## 🔐 Configuración SSL/TLS

### Desarrollo
- Certificados autofirmados generados automáticamente
- Tu navegador mostrará advertencia (es normal)
- Válido para `localhost` y `*.localhost`

### Producción
- Let's Encrypt automático
- Renovación automática cada 60 días
- Soporte para wildcard certificates (`*.tudominio.com`)

## 📊 Dashboard

### Desarrollo
- URL: `http://traefik.localhost:8080`
- Sin autenticación
- API en modo debug

### Producción
- URL: `https://traefik.tudominio.com`
- Requiere autenticación (usuario/password del `.env`)
- Solo accesible por HTTPS

## 🐛 Troubleshooting

### El dashboard no carga

```bash
# Verificar que Traefik está corriendo
docker ps | grep traefik

# Ver logs
./scripts/logs.sh

# Verificar red
docker network ls | grep traefik-public
```

### Mi proyecto no aparece en Traefik

```bash
# Verificar que el contenedor tiene las labels correctas
docker inspect tu-contenedor | grep traefik

# Verificar que está en la red correcta
docker inspect tu-contenedor | grep traefik-public

# Ver logs de Traefik
./scripts/logs.sh
```

### Error de permisos en acme.json

```bash
chmod 600 certs/prod/acme.json
```

### Let's Encrypt no genera certificados

1. Verificar que el dominio apunta a tu servidor
2. Verificar que los puertos 80 y 443 están abiertos
3. Verificar el email en `.env`
4. Ver logs: `./scripts/logs.sh -e`

## 📚 Ejemplos Completos

Ver la carpeta `networks/README.md` para ejemplos completos de:
- Aplicación simple
- API con CORS
- Microservicios
- Aplicaciones con autenticación

## 🔄 Actualizar Traefik

```bash
# Detener
./scripts/stop.sh

# Actualizar imagen
docker pull traefik:v3.5

# Iniciar nuevamente
./scripts/start-dev.sh  # o start-prod.sh
```

## 📖 Recursos

- [Documentación oficial de Traefik](https://doc.traefik.io/traefik/)
- [Middlewares disponibles](https://doc.traefik.io/traefik/middlewares/overview/)
- [Docker Provider](https://doc.traefik.io/traefik/providers/docker/)
- [Let's Encrypt](https://doc.traefik.io/traefik/https/acme/)

## ⚠️ Notas de Seguridad

### Desarrollo
- Dashboard sin autenticación (solo localhost)
- Certificados autofirmados
- Logs en modo DEBUG
- CORS permisivo

### Producción
- Dashboard con autenticación
- Certificados Let's Encrypt
- Logs optimizados (WARN/ERROR)
- CORS restrictivo
- Rate limiting activado
- Headers de seguridad estrictos

## 📞 Soporte

Si encuentras problemas:
1. Revisa los logs: `./scripts/logs.sh`
2. Verifica la configuración en `.env`
3. Consulta la documentación oficial de Traefik