# Traefik: Guía Completa para Principiantes

## 📚 Tabla de Contenidos

1. [¿Qué es Traefik?](#qué-es-traefik)
2. [¿Por qué usar Traefik?](#por-qué-usar-traefik)
3. [Conceptos Fundamentales](#conceptos-fundamentales)
4. [Arquitectura de Traefik](#arquitectura-de-traefik)
5. [Configuración Paso a Paso](#configuración-paso-a-paso)
6. [Ejemplos Prácticos](#ejemplos-prácticos)
7. [Troubleshooting Común](#troubleshooting-común)
8. [Mejores Prácticas](#mejores-prácticas)

---

## ¿Qué es Traefik?

**Traefik** es un **reverse proxy** y **load balancer** moderno diseñado específicamente para trabajar con contenedores Docker, Kubernetes y otras tecnologías cloud-native.

### Analogía Simple

Imagina que tienes un edificio (tu servidor) con muchas oficinas (tus aplicaciones):

- **Sin Traefik**: Los visitantes tienen que saber exactamente qué puerta y piso visitar. Si tienes una app en el puerto 3000, otra en el 4000, otra en el 8080... los usuarios tendrían que recordar todos esos números.

- **Con Traefik**: Es como tener un recepcionista inteligente en la entrada. Los visitantes solo dicen "quiero ir a blog.midominio.com" y Traefik los lleva automáticamente a la aplicación correcta, sin importar en qué puerto esté corriendo internamente.

### ¿Qué es un Reverse Proxy?

Un **reverse proxy** es un intermediario que:

1. **Recibe peticiones** de los usuarios (navegadores, apps)
2. **Decide** qué aplicación debe responder
3. **Envía la petición** a la aplicación correcta
4. **Devuelve la respuesta** al usuario

```
Usuario → Traefik → Aplicación correcta
         (decide basándose en el dominio/path)
```

---

## ¿Por qué usar Traefik?

### Problemas que resuelve

#### 1. **Gestión de Dominios**

**Sin Traefik:**
```
blog.midominio.com:3000
api.midominio.com:8000
admin.midominio.com:9000
```
Los usuarios tienen que recordar puertos.

**Con Traefik:**
```
blog.midominio.com
api.midominio.com
admin.midominio.com
```
URLs limpias y profesionales.

#### 2. **Certificados SSL/HTTPS**

**Sin Traefik:**
- Tienes que configurar SSL en cada aplicación
- Renovar certificados manualmente cada 3 meses
- Es complicado y propenso a errores

**Con Traefik:**
- SSL/HTTPS automático con Let's Encrypt
- Renovación automática de certificados
- Configuración de una sola vez

#### 3. **Configuración Dinámica**

**Sin Traefik:**
- Editar archivos de configuración
- Reiniciar el servidor
- Riesgo de downtime

**Con Traefik:**
- Detecta nuevas aplicaciones automáticamente
- Se reconfigura solo cuando subes/bajas contenedores
- Zero-downtime

#### 4. **Múltiples Aplicaciones en un Servidor**

**Sin Traefik:**
```
Solo 1 app puede usar el puerto 80
Solo 1 app puede usar el puerto 443
```

**Con Traefik:**
```
10, 20, 100 aplicaciones pueden convivir
Todas accesibles por HTTP/HTTPS
Traefik enruta cada petición a la app correcta
```

---

## Conceptos Fundamentales

### 1. EntryPoints (Puntos de Entrada)

Son los **puertos** donde Traefik escucha peticiones.

```yaml
entryPoints:
  web:
    address: ":80"      # Puerto 80 = HTTP
  websecure:
    address: ":443"     # Puerto 443 = HTTPS
```

**Analogía**: Las puertas principales de un edificio. Una puerta para HTTP (80), otra para HTTPS (443).

### 2. Routers (Enrutadores)

Definen **REGLAS** para decidir qué peticiones van a qué aplicación.

```yaml
# Ejemplo: Si alguien pide "blog.midominio.com", enviar a la app "blog"
routers:
  blog:
    rule: "Host(`blog.midominio.com`)"
    service: blog-service
```

**Analogía**: El recepcionista que lee el nombre que buscas y te dice a qué oficina ir.

**Tipos de reglas comunes:**

```yaml
# Por dominio/host
rule: "Host(`blog.midominio.com`)"

# Por path/ruta
rule: "PathPrefix(`/api`)"

# Combinadas
rule: "Host(`api.midominio.com`) && PathPrefix(`/v1`)"

# Múltiples dominios
rule: "Host(`blog.com`) || Host(`www.blog.com`)"
```

### 3. Services (Servicios)

Definen **DÓNDE** está tu aplicación (IP, puerto).

```yaml
services:
  blog-service:
    loadBalancer:
      servers:
        - url: "http://192.168.1.10:3000"
```

**Analogía**: La dirección exacta de la oficina (piso, puerta).

### 4. Middlewares (Intermediarios)

**Modifican** las peticiones/respuestas antes de llegar a la aplicación.

```yaml
middlewares:
  # Redirigir HTTP a HTTPS
  redirect-to-https:
    redirectScheme:
      scheme: https
  
  # Autenticación
  basic-auth:
    basicAuth:
      users:
        - "admin:$password$hash"
  
  # Rate limiting (limitar peticiones)
  rate-limit:
    rateLimit:
      average: 100
      burst: 200
```

**Analogía**: Guardias de seguridad o asistentes que verifican IDs, limitan visitantes, etc., antes de dejarte pasar.

**Middlewares comunes:**

- **Autenticación**: Pedir usuario/contraseña
- **Rate Limiting**: Prevenir spam/ataques
- **Compresión**: Comprimir respuestas (gzip)
- **Headers de seguridad**: Prevenir ataques XSS, clickjacking
- **CORS**: Permitir peticiones desde otros dominios
- **Redirects**: HTTP→HTTPS, www→non-www

---

## Arquitectura de Traefik

### Flujo de una Petición

```
1. Usuario escribe: https://blog.midominio.com
                          ↓
2. Petición llega a Traefik (puerto 443)
                          ↓
3. Traefik busca un ROUTER que coincida
   → rule: "Host(`blog.midominio.com`)" ✓
                          ↓
4. Traefik aplica MIDDLEWARES (si hay)
   → Ejemplo: security-headers, compression
                          ↓
5. Traefik envía petición al SERVICE
   → http://blog-container:3000
                          ↓
6. La aplicación responde
                          ↓
7. Traefik devuelve respuesta al usuario
```

### Diagrama Visual

```
Internet
   ↓
[Puerto 80/443]
   ↓
┌────────────────────────────────────┐
│           TRAEFIK                  │
│                                    │
│  ┌──────────────────────────────┐  │
│  │  EntryPoint: web (80)        │  │
│  │  EntryPoint: websecure (443) │  │
│  └──────────────────────────────┘  │
│            ↓                       │
│  ┌──────────────────────────────┐  │
│  │  Routers (reglas)            │  │
│  │  - blog.com → blog-service   │  │
│  │  - api.com → api-service     │  │
│  └──────────────────────────────┘  │
│            ↓                       │
│  ┌──────────────────────────────┐  │
│  │  Middlewares                 │  │
│  │  - Auth, CORS, Compression   │  │
│  └──────────────────────────────┘  │
│            ↓                       │
│  ┌──────────────────────────────┐  │
│  │  Services (aplicaciones)     │  │
│  └──────────────────────────────┘  │
└────────────────────────────────────┘
         ↓           ↓
    [Blog App]   [API App]
```

---

## Configuración Paso a Paso

### Método 1: Configuración con Archivos YAML

#### Archivo: `traefik.yml` (configuración estática)

```yaml
# Configuración que NO cambia mientras Traefik corre
# (requiere reinicio para aplicar cambios)

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  # Leer configuración de archivos
  file:
    directory: "/etc/traefik/dynamic"
    watch: true  # Recargar automáticamente si cambian

api:
  dashboard: true  # Habilitar dashboard web
```

#### Archivo: `dynamic/routers.yml` (configuración dinámica)

```yaml
# Configuración que SÍ se recarga automáticamente

http:
  routers:
    blog:
      rule: "Host(`blog.localhost`)"
      service: blog-service
      entryPoints:
        - web
  
  services:
    blog-service:
      loadBalancer:
        servers:
          - url: "http://192.168.1.10:3000"
```

### Método 2: Configuración con Docker Labels (Recomendado)

Este es el método **más fácil y automático** cuando usas Docker.

#### docker-compose.yml de tu aplicación

```yaml
services:
  blog:
    image: ghost:latest
    networks:
      - traefik-public  # Conectar a la red de Traefik
    labels:
      # Habilitar Traefik para este contenedor
      - "traefik.enable=true"
      
      # Definir el router
      - "traefik.http.routers.blog.rule=Host(`blog.localhost`)"
      - "traefik.http.routers.blog.entrypoints=web"
      
      # Definir el service (puerto interno del contenedor)
      - "traefik.http.services.blog.loadbalancer.server.port=2368"

networks:
  traefik-public:
    external: true
```

**¿Qué hace cada label?**

```yaml
# 1. Activar Traefik para este contenedor
- "traefik.enable=true"

# 2. Nombre del router: "blog"
#    Regla: responder a peticiones con Host = blog.localhost
- "traefik.http.routers.blog.rule=Host(`blog.localhost`)"

# 3. El router escucha en el entrypoint "web" (puerto 80)
- "traefik.http.routers.blog.entrypoints=web"

# 4. El servicio envía peticiones al puerto 2368 DEL CONTENEDOR
#    (no es el puerto expuesto externamente)
- "traefik.http.services.blog.loadbalancer.server.port=2368"
```

---

## Ejemplos Prácticos

### Ejemplo 1: Blog Simple (Desarrollo)

**Objetivo**: Acceder a tu blog en `http://blog.localhost`

#### 1. docker-compose.yml de Traefik

```yaml
services:
  traefik:
    image: traefik:v3.5
    ports:
      - "80:80"
      - "8080:8080"  # Dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command:
      - "--api.dashboard=true"
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
    networks:
      - traefik-public

networks:
  traefik-public:
    external: true
```

#### 2. docker-compose.yml de tu Blog

```yaml
services:
  blog:
    image: ghost:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.blog.rule=Host(`blog.localhost`)"
      - "traefik.http.routers.blog.entrypoints=web"
      - "traefik.http.services.blog.loadbalancer.server.port=2368"

networks:
  traefik-public:
    external: true
```

#### 3. Iniciar

```bash
# Crear red
docker network create traefik-public

# Iniciar Traefik
cd traefik-folder
docker compose up -d

# Iniciar Blog
cd blog-folder
docker compose up -d
```

#### 4. Acceder

- Blog: `http://blog.localhost`
- Dashboard de Traefik: `http://localhost:8080`

---

### Ejemplo 2: Aplicación con HTTPS (Producción)

**Objetivo**: Acceder a tu app en `https://app.tudominio.com` con SSL automático

#### docker-compose.yml de Traefik

```yaml
services:
  traefik:
    image: traefik:v3.5
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./certs:/etc/traefik/certs  # Guardar certificados
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      
      # Let's Encrypt
      - "--certificatesresolvers.letsencrypt.acme.email=tu@email.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/etc/traefik/certs/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
    networks:
      - traefik-public

networks:
  traefik-public:
    external: true
```

#### docker-compose.yml de tu App

```yaml
services:
  app:
    image: tu-app:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      
      # Router HTTPS
      - "traefik.http.routers.app-secure.rule=Host(`app.tudominio.com`)"
      - "traefik.http.routers.app-secure.entrypoints=websecure"
      - "traefik.http.routers.app-secure.tls=true"
      - "traefik.http.routers.app-secure.tls.certresolver=letsencrypt"
      
      # Router HTTP (redirige a HTTPS)
      - "traefik.http.routers.app.rule=Host(`app.tudominio.com`)"
      - "traefik.http.routers.app.entrypoints=web"
      - "traefik.http.routers.app.middlewares=redirect-to-https"
      
      # Middleware redirect
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
      
      # Service
      - "traefik.http.services.app.loadbalancer.server.port=3000"

networks:
  traefik-public:
    external: true
```

**Resultado:**
- HTTP (`http://app.tudominio.com`) → Redirige automáticamente a HTTPS
- HTTPS (`https://app.tudominio.com`) → ✓ Certificado SSL válido y automático

---

### Ejemplo 3: API con Múltiples Rutas

**Objetivo**: Enrutar diferentes paths a diferentes servicios

```
https://api.tudominio.com/users    → Servicio de usuarios
https://api.tudominio.com/products → Servicio de productos
https://api.tudominio.com/orders   → Servicio de órdenes
```

#### docker-compose.yml

```yaml
services:
  # Servicio de usuarios
  users-api:
    image: users-api:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.users.rule=Host(`api.tudominio.com`) && PathPrefix(`/users`)"
      - "traefik.http.routers.users.entrypoints=websecure"
      - "traefik.http.routers.users.tls.certresolver=letsencrypt"
      - "traefik.http.services.users.loadbalancer.server.port=8001"
  
  # Servicio de productos
  products-api:
    image: products-api:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.products.rule=Host(`api.tudominio.com`) && PathPrefix(`/products`)"
      - "traefik.http.routers.products.entrypoints=websecure"
      - "traefik.http.routers.products.tls.certresolver=letsencrypt"
      - "traefik.http.services.products.loadbalancer.server.port=8002"
  
  # Servicio de órdenes
  orders-api:
    image: orders-api:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.orders.rule=Host(`api.tudominio.com`) && PathPrefix(`/orders`)"
      - "traefik.http.routers.orders.entrypoints=websecure"
      - "traefik.http.routers.orders.tls.certresolver=letsencrypt"
      - "traefik.http.services.orders.loadbalancer.server.port=8003"

networks:
  traefik-public:
    external: true
```

---

### Ejemplo 4: Aplicación con Autenticación

**Objetivo**: Proteger el panel de administración con usuario/contraseña

```yaml
services:
  admin:
    image: admin-panel:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.admin.rule=Host(`admin.tudominio.com`)"
      - "traefik.http.routers.admin.entrypoints=websecure"
      - "traefik.http.routers.admin.tls.certresolver=letsencrypt"
      
      # Aplicar middleware de autenticación
      - "traefik.http.routers.admin.middlewares=admin-auth"
      
      # Definir el middleware con usuario/contraseña
      # Usuario: admin, Password: secret
      # Hash generado con: htpasswd -nb admin secret
      - "traefik.http.middlewares.admin-auth.basicauth.users=admin:$$apr1$$H6uskkkW$$IgXLP6ewTrSuBkTrqE8wj/"
      
      - "traefik.http.services.admin.loadbalancer.server.port=80"

networks:
  traefik-public:
    external: true
```

**Generar el hash de contraseña:**

```bash
# Instalar htpasswd (si no lo tienes)
apt-get install apache2-utils  # Ubuntu/Debian
brew install httpd             # macOS

# Generar hash
htpasswd -nb admin tu_password_secreto

# Resultado (ejemplo):
# admin:$apr1$H6uskkkW$IgXLP6ewTrSuBkTrqE8wj/
```

**Importante**: En docker-compose.yml, los `$` deben escaparse como `$$`.

---

## Troubleshooting Común

### Problema 1: "502 Bad Gateway"

**Significa**: Traefik no puede conectarse a tu aplicación.

**Causas comunes:**

1. **Puerto incorrecto**
   ```yaml
   # ❌ Incorrecto
   - "traefik.http.services.app.loadbalancer.server.port=80"
   # Si tu app corre en puerto 3000
   
   # ✓ Correcto
   - "traefik.http.services.app.loadbalancer.server.port=3000"
   ```

2. **Contenedor no en la red correcta**
   ```bash
   # Verificar
   docker inspect mi-contenedor | grep traefik-public
   
   # Si no aparece, añadir la red:
   networks:
     - traefik-public
   ```

3. **Aplicación no está corriendo**
   ```bash
   docker ps  # Verificar que el contenedor está UP
   docker logs mi-contenedor  # Ver logs de errores
   ```

### Problema 2: "404 Page Not Found"

**Significa**: Traefik no encontró un router que coincida con la URL.

**Causas comunes:**

1. **Dominio/Host incorrecto**
   ```yaml
   # ❌ Pusiste esto
   - "traefik.http.routers.app.rule=Host(`app.localhost`)"
   
   # Pero intentas acceder a:
   # http://blog.localhost  ← No coincide
   ```

2. **Falta `traefik.enable=true`**
   ```yaml
   labels:
     - "traefik.enable=true"  # ← Necesario
     - "traefik.http.routers..."
   ```

3. **Router sin entrypoint**
   ```yaml
   - "traefik.http.routers.app.entrypoints=web"  # ← Necesario
   ```

**Solución**: Ver dashboard de Traefik (`http://localhost:8080`) para ver qué routers están activos.

### Problema 3: Let's Encrypt no genera certificados

**Causas comunes:**

1. **Dominio no apunta a tu servidor**
   ```bash
   # Verificar DNS
   nslookup tudominio.com
   dig tudominio.com
   ```

2. **Puertos 80/443 no accesibles**
   ```bash
   # Verificar firewall
   sudo ufw status
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

3. **Email no configurado**
   ```yaml
   - "--certificatesresolvers.letsencrypt.acme.email=tu@email.com"
   ```

4. **Permisos de acme.json**
   ```bash
   chmod 600 certs/acme.json
   ```

### Problema 4: Cambios no se aplican

**Configuración estática (traefik.yml)**:
```bash
# Requiere reinicio
docker compose restart traefik
```

**Configuración dinámica (labels, archivos en /dynamic)**:
```bash
# Se aplica automáticamente (espera 1-2 segundos)
# Si no, reinicia:
docker compose restart traefik
```

### Problema 5: No puedo acceder al dashboard

**Desarrollo:**
```yaml
# Asegúrate de tener:
command:
  - "--api.dashboard=true"
  - "--api.insecure=true"  # Solo desarrollo

ports:
  - "8080:8080"

# Accede a: http://localhost:8080
```

**Producción:**
```yaml
# Dashboard protegido con labels:
labels:
  - "traefik.http.routers.dashboard.rule=Host(`traefik.tudominio.com`)"
  - "traefik.http.routers.dashboard.service=api@internal"
  - "traefik.http.routers.dashboard.middlewares=auth"
  - "traefik.http.middlewares.auth.basicauth.users=admin:$$hash$$"
```

---

## Mejores Prácticas

### 1. Separar Configuración por Ambiente

```
traefik/
├── config/
│   ├── traefik.yml           # Base común
│   ├── traefik.dev.yml       # Desarrollo
│   └── traefik.prod.yml      # Producción
```

**Desarrollo:**
- Logs en modo DEBUG
- Dashboard sin autenticación
- Certificados autofirmados
- Sin rate limiting

**Producción:**
- Logs en modo WARN/ERROR
- Dashboard protegido
- Let's Encrypt automático
- Rate limiting activado

### 2. Usar Variables de Entorno

**.env**
```bash
DOMAIN=tudominio.com
LETSENCRYPT_EMAIL=tu@email.com
DASHBOARD_USER=admin
DASHBOARD_PASSWORD=$apr1$hash...
```

**docker-compose.yml**
```yaml
labels:
  - "traefik.http.routers.app.rule=Host(`app.${DOMAIN}`)"
```

### 3. Aplicar Middlewares de Seguridad

```yaml
labels:
  # Siempre en producción:
  - "traefik.http.routers.app.middlewares=security-headers,compression,rate-limit"
```

**Middlewares recomendados:**
- `security-headers`: Headers anti-XSS, clickjacking
- `compression`: Reducir tamaño de respuestas
- `rate-limit`: Prevenir spam/DDoS
- `redirect-to-https`: Forzar HTTPS

### 4. Organizar con Redes Docker

```yaml
services:
  frontend:
    networks:
      - traefik-public  # Expuesto externamente
  
  api:
    networks:
      - traefik-public  # Expuesto externamente
      - backend         # Comunicación interna
  
  database:
    networks:
      - backend  # Solo interno, NO expuesto
```

### 5. Logs y Monitoreo

```yaml
# Archivo de logs
log:
  filePath: "/var/log/traefik/traefik.log"
  level: "INFO"

accessLog:
  filePath: "/var/log/traefik/access.log"
```

```bash
# Ver logs en tiempo real
docker logs -f traefik

# Filtrar errores
docker logs traefik 2>&1 | grep -i error
```

### 6. Backup de Certificados

```bash
# Let's Encrypt guarda certificados en:
./certs/acme.json

# Hacer backup periódico:
cp certs/acme.json certs/acme.json.backup
```

### 7. Health Checks

```yaml
services:
  app:
    image: tu-app:latest
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

Traefik detectará automáticamente si el contenedor está "unhealthy" y dejará de enviarle tráfico.

---

## Recursos Adicionales

### Documentación Oficial
- [Traefik Docs](https://doc.traefik.io/traefik/)
- [Docker Provider](https://doc.traefik.io/traefik/providers/docker/)
- [Let's Encrypt](https://doc.traefik.io/traefik/https/acme/)
- [Middlewares](https://doc.traefik.io/traefik/middlewares/overview/)

### Comandos Útiles

```bash
# Ver contenedores en la red de Traefik
docker network inspect traefik-public

# Ver labels de un contenedor
docker inspect mi-contenedor | grep traefik

# Logs de Traefik
docker logs -f traefik

# Reiniciar Traefik
docker compose restart traefik

# Ver certificados de Let's Encrypt
cat certs/acme.json | jq

# Validar sintaxis de docker-compose
docker compose config

# Ver qué puertos están en uso
netstat -tuln | grep -E '80|443|8080'
```

### Glosario

- **Reverse Proxy**: Intermediario que recibe peticiones y las envía a la aplicación correcta
- **Load Balancer**: Distribuye peticiones entre múltiples instancias de una app
- **EntryPoint**: Puerto donde Traefik escucha (ej: 80, 443)
- **Router**: Define reglas para enrutar peticiones (por host, path, etc)
- **Service**: Define dónde está tu aplicación (IP, puerto)
- **Middleware**: Modifica peticiones/respuestas (auth, CORS, rate limit, etc)
- **Provider**: Fuente de configuración (Docker, archivos, Kubernetes, etc)
- **Let's Encrypt**: Servicio que proporciona certificados SSL/TLS gratis
- **ACME**: Protocolo para obtener certificados automáticamente
- **SNI**: Permite múltiples certificados SSL en un mismo puerto

---

## Conclusión

Traefik simplifica enormemente la gestión de múltiples aplicaciones en Docker:

✅ **URLs limpias** sin puertos  
✅ **HTTPS automático** con Let's Encrypt  
✅ **Configuración dinámica** detecta nuevas apps automáticamente  
✅ **Load balancing** distribuye carga entre instancias  
✅ **Middlewares** añaden seguridad, CORS, rate limiting, etc  
✅ **Dashboard** visualiza toda tu infraestructura  

**Lo mejor**: Una vez configurado Traefik, solo tienes que añadir labels a tus `docker-compose.yml` y todo funciona automáticamente. No más editar archivos de Nginx, no más renovar certificados manualmente, no más conflictos de puertos.

¡Es la herramienta perfecta para desplegar múltiples proyectos en un solo servidor! 🚀