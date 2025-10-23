# Conectar Proyectos a Traefik

Esta guía muestra ejemplos completos de cómo conectar diferentes tipos de proyectos a Traefik.

## 🌐 Red Docker

Todos los proyectos deben conectarse a la red `traefik-public`:

```yaml
networks:
  traefik-public:
    external: true
```

Esta red ya fue creada automáticamente al iniciar Traefik.

---

## 📦 Ejemplo 1: Aplicación Simple (Node.js/Python/etc)

### Desarrollo

**docker-compose.yml:**
```yaml
services:
  mi-app:
    build: .
    container_name: mi-app
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.mi-app.rule=Host(`mi-app.localhost`)"
      - "traefik.http.routers.mi-app.entrypoints=web"
      - "traefik.http.services.mi-app.loadbalancer.server.port=3000"

networks:
  traefik-public:
    external: true
```

**Acceso:** `http://mi-app.localhost`

### Producción

```yaml
services:
  mi-app:
    image: mi-app:latest
    container_name: mi-app
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      
      # HTTPS
      - "traefik.http.routers.mi-app-secure.rule=Host(`mi-app.tudominio.com`)"
      - "traefik.http.routers.mi-app-secure.entrypoints=websecure"
      - "traefik.http.routers.mi-app-secure.tls=true"
      - "traefik.http.routers.mi-app-secure.tls.certresolver=letsencrypt"
      
      # HTTP -> HTTPS redirect
      - "traefik.http.routers.mi-app.rule=Host(`mi-app.tudominio.com`)"
      - "traefik.http.routers.mi-app.entrypoints=web"
      - "traefik.http.routers.mi-app.middlewares=redirect-to-https"
      
      # Puerto interno
      - "traefik.http.services.mi-app.loadbalancer.server.port=3000"
      
      # Middlewares de seguridad
      - "traefik.http.routers.mi-app-secure.middlewares=security-headers,compression"

networks:
  traefik-public:
    external: true
```

**Acceso:** `https://mi-app.tudominio.com`

---

## 🎯 Ejemplo 2: API con CORS

```yaml
services:
  api:
    image: mi-api:latest
    container_name: api
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      
      # Router principal
      - "traefik.http.routers.api-secure.rule=Host(`api.tudominio.com`)"
      - "traefik.http.routers.api-secure.entrypoints=websecure"
      - "traefik.http.routers.api-secure.tls=true"
      - "traefik.http.routers.api-secure.tls.certresolver=letsencrypt"
      
      # Servicio
      - "traefik.http.services.api.loadbalancer.server.port=8000"
      
      # Middlewares: CORS + Rate limiting + Compression
      - "traefik.http.routers.api-secure.middlewares=api-cors,rate-limit,compression"
      
      # CORS personalizado
      - "traefik.http.middlewares.api-cors.headers.accesscontrolallowmethods=GET,POST,PUT,DELETE,OPTIONS"
      - "traefik.http.middlewares.api-cors.headers.accesscontrolalloworiginlist=https://app.tudominio.com,https://admin.tudominio.com"
      - "traefik.http.middlewares.api-cors.headers.accesscontrolallowheaders=Content-Type,Authorization"
      - "traefik.http.middlewares.api-cors.headers.accesscontrolallowcredentials=true"

networks:
  traefik-public:
    external: true
```

**Acceso:** `https://api.tudominio.com`

---

## 🏗️ Ejemplo 3: Microservicios

```yaml
services:
  # Servicio de usuarios
  users-service:
    image: users:latest
    networks:
      - traefik-public
      - backend
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.users.rule=Host(`api.tudominio.com`) && PathPrefix(`/users`)"
      - "traefik.http.routers.users.entrypoints=websecure"
      - "traefik.http.routers.users.tls=true"
      - "traefik.http.routers.users.tls.certresolver=letsencrypt"
      - "traefik.http.services.users.loadbalancer.server.port=8001"
      - "traefik.http.routers.users.middlewares=security-headers,rate-limit-strict"
  
  # Servicio de productos
  products-service:
    image: products:latest
    networks:
      - traefik-public
      - backend
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.products.rule=Host(`api.tudominio.com`) && PathPrefix(`/products`)"
      - "traefik.http.routers.products.entrypoints=websecure"
      - "traefik.http.routers.products.tls=true"
      - "traefik.http.routers.products.tls.certresolver=letsencrypt"
      - "traefik.http.services.products.loadbalancer.server.port=8002"
      - "traefik.http.routers.products.middlewares=security-headers,rate-limit"
  
  # Servicio de órdenes
  orders-service:
    image: orders:latest
    networks:
      - traefik-public
      - backend
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.orders.rule=Host(`api.tudominio.com`) && PathPrefix(`/orders`)"
      - "traefik.http.routers.orders.entrypoints=websecure"
      - "traefik.http.routers.orders.tls=true"
      - "traefik.http.routers.orders.tls.certresolver=letsencrypt"
      - "traefik.http.services.orders.loadbalancer.server.port=8003"
      - "traefik.http.routers.orders.middlewares=security-headers,rate-limit"

networks:
  traefik-public:
    external: true
  backend:
    driver: bridge
```

**Acceso:**
- `https://api.tudominio.com/users`
- `https://api.tudominio.com/products`
- `https://api.tudominio.com/orders`

---

## 🔐 Ejemplo 4: Aplicación con Autenticación Básica

```yaml
services:
  admin-panel:
    image: admin:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.admin-secure.rule=Host(`admin.tudominio.com`)"
      - "traefik.http.routers.admin-secure.entrypoints=websecure"
      - "traefik.http.routers.admin-secure.tls=true"
      - "traefik.http.routers.admin-secure.tls.certresolver=letsencrypt"
      - "traefik.http.services.admin.loadbalancer.server.port=80"
      
      # Autenticación básica
      - "traefik.http.routers.admin-secure.middlewares=admin-auth,security-headers"
      - "traefik.http.middlewares.admin-auth.basicauth.users=admin:$$apr1$$H6uskkkW$$IgXLP6ewTrSuBkTrqE8wj/"
      # Genera el hash con: htpasswd -nb admin tu_password

networks:
  traefik-public:
    external: true
```

**Nota:** Los `$$` son necesarios en docker-compose para escapar el `$`.

---

## 🌍 Ejemplo 5: Múltiples Dominios

```yaml
services:
  main-site:
    image: main-site:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      
      # Dominio principal
      - "traefik.http.routers.main.rule=Host(`tudominio.com`) || Host(`www.tudominio.com`)"
      - "traefik.http.routers.main.entrypoints=websecure"
      - "traefik.http.routers.main.tls=true"
      - "traefik.http.routers.main.tls.certresolver=letsencrypt"
      
      # Dominio alternativo
      - "traefik.http.routers.alt.rule=Host(`otro-dominio.com`)"
      - "traefik.http.routers.alt.entrypoints=websecure"
      - "traefik.http.routers.alt.tls=true"
      - "traefik.http.routers.alt.tls.certresolver=letsencrypt"
      
      # Servicio
      - "traefik.http.services.main.loadbalancer.server.port=80"
      
      # Middlewares
      - "traefik.http.routers.main.middlewares=redirect-non-www,security-headers"

networks:
  traefik-public:
    external: true
```

---

## 🔄 Ejemplo 6: Load Balancing (Múltiples Instancias)

```yaml
services:
  app1:
    image: mi-app:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=Host(`app.tudominio.com`)"
      - "traefik.http.routers.app.entrypoints=websecure"
      - "traefik.http.routers.app.tls=true"
      - "traefik.http.routers.app.tls.certresolver=letsencrypt"
      - "traefik.http.services.app.loadbalancer.server.port=3000"
  
  app2:
    image: mi-app:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=Host(`app.tudominio.com`)"
      - "traefik.http.routers.app.entrypoints=websecure"
      - "traefik.http.routers.app.tls=true"
      - "traefik.http.routers.app.tls.certresolver=letsencrypt"
      - "traefik.http.services.app.loadbalancer.server.port=3000"
  
  app3:
    image: mi-app:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=Host(`app.tudominio.com`)"
      - "traefik.http.routers.app.entrypoints=websecure"
      - "traefik.http.routers.app.tls=true"
      - "traefik.http.routers.app.tls.certresolver=letsencrypt"
      - "traefik.http.services.app.loadbalancer.server.port=3000"

networks:
  traefik-public:
    external: true
```

Traefik balanceará automáticamente las peticiones entre las 3 instancias.

---

## 🎨 Ejemplo 7: Frontend + Backend

```yaml
services:
  frontend:
    image: react-app:latest
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.frontend.rule=Host(`app.tudominio.com`)"
      - "traefik.http.routers.frontend.entrypoints=websecure"
      - "traefik.http.routers.frontend.tls=true"
      - "traefik.http.routers.frontend.tls.certresolver=letsencrypt"
      - "traefik.http.services.frontend.loadbalancer.server.port=80"
      - "traefik.http.routers.frontend.middlewares=security-headers,compression"
  
  backend:
    image: api:latest
    networks:
      - traefik-public
      - backend
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.backend.rule=Host(`app.tudominio.com`) && PathPrefix(`/api`)"
      - "traefik.http.routers.backend.entrypoints=websecure"
      - "traefik.http.routers.backend.tls=true"
      - "traefik.http.routers.backend.tls.certresolver=letsencrypt"
      - "traefik.http.services.backend.loadbalancer.server.port=8000"
      - "traefik.http.routers.backend.middlewares=security-headers,rate-limit"
      # Strip /api prefix antes de enviar al backend
      - "traefik.http.middlewares.strip-api.stripprefix.prefixes=/api"
      - "traefik.http.routers.backend.middlewares=strip-api"
  
  database:
    image: postgres:15
    networks:
      - backend
    # Database NO está en traefik-public (no es accesible externamente)

networks:
  traefik-public:
    external: true
  backend:
    driver: bridge
```

**Acceso:**
- Frontend: `https://app.tudominio.com`
- Backend: `https://app.tudominio.com/api`

---

## 📋 Reglas de Routing Avanzadas

### Por Host
```yaml
- "traefik.http.routers.app.rule=Host(`app.tudominio.com`)"
```

### Por Path
```yaml
- "traefik.http.routers.api.rule=PathPrefix(`/api`)"
```

### Combinadas (AND)
```yaml
- "traefik.http.routers.api.rule=Host(`app.tudominio.com`) && PathPrefix(`/api`)"
```

### Múltiples hosts (OR)
```yaml
- "traefik.http.routers.app.rule=Host(`app.tudominio.com`) || Host(`www.app.tudominio.com`)"
```

### Con Headers
```yaml
- "traefik.http.routers.api.rule=Host(`api.tudominio.com`) && Headers(`X-API-Version`, `v2`)"
```

### Con Query params
```yaml
- "traefik.http.routers.api.rule=Host(`api.tudominio.com`) && Query(`version`, `2`)"
```

---

## 🛠️ Tips y Mejores Prácticas

### 1. Nombrado consistente
Usa nombres consistentes para routers, services y middlewares:
```yaml
- "traefik.http.routers.mi-app.rule=..."
- "traefik.http.services.mi-app.loadbalancer.server.port=..."
```

### 2. Siempre usa HTTPS en producción
```yaml
- "traefik.http.routers.app-secure.tls=true"
- "traefik.http.routers.app-secure.tls.certresolver=letsencrypt"
```

### 3. Aplica middlewares de seguridad
```yaml
- "traefik.http.routers.app.middlewares=security-headers,compression,rate-limit"
```

### 4. Separa redes
- `traefik-public`: Para servicios expuestos externamente
- `backend`: Para comunicación interna (databases, caches, etc)

### 5. Health checks
Traefik detecta automáticamente contenedores saludables, pero puedes configurar health checks:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

---

## 🚨 Troubleshooting

### Mi aplicación no responde

1. Verifica que el contenedor está en la red correcta:
```bash
docker inspect tu-contenedor | grep traefik-public
```

2. Verifica los labels:
```bash
docker inspect tu-contenedor | grep traefik
```

3. Verifica el puerto interno:
```yaml
# Debe coincidir con el puerto que expone tu aplicación DENTRO del contenedor
- "traefik.http.services.app.loadbalancer.server.port=3000"
```

### Error 404

Verifica la regla de routing:
```bash
# Ver en el dashboard qué routers están activos
# http://traefik.localhost:8080
```

### Error 502 Bad Gateway

El contenedor no responde:
1. Verifica que la aplicación está corriendo: `docker logs tu-contenedor`
2. Verifica el puerto: `docker exec tu-contenedor netstat -tulpn`
3. Verifica health del contenedor: `docker ps`

---

## 📚 Recursos Adicionales

- [Traefik Docker Labels](https://doc.traefik.io/traefik/routing/providers/docker/)
- [Routing Rules](https://doc.traefik.io/traefik/routing/routers/)
- [Middlewares](https://doc.traefik.io/traefik/middlewares/overview/)