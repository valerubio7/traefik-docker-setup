#!/bin/bash

# ============================================
# INICIAR TRAEFIK EN PRODUCCIÓN
# ============================================
# Script robusto con validaciones exhaustivas
# y manejo completo de errores
# ============================================

set -e

# ==========================================
# TRAP HANDLERS
# ==========================================
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "❌ Error al iniciar Traefik en producción (código: $exit_code)"
        echo "   Diagnosticar:"
        echo "   - Ver logs: docker compose logs traefik"
        echo "   - Verificar red: ./scripts/validate-network.sh"
        echo "   - Validar permisos: ls -la certs/prod/"
    fi
    exit $exit_code
}

trap cleanup EXIT

# ==========================================
# FUNCIÓN: Retry logic para docker commands
# ==========================================
docker_retry() {
    local max_retries=3
    local retry_count=0
    local command="$@"
    
    while [ $retry_count -lt $max_retries ]; do
        if eval "$command"; then
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "   ⚠️  Reintentando... ($retry_count/$max_retries)"
            sleep 2
        fi
    done
    
    echo "   ❌ Falló después de $max_retries intentos"
    return 1
}

# ==========================================
# FUNCIÓN: Validar Docker
# ==========================================
validate_docker() {
    if ! command -v docker &> /dev/null; then
        echo "❌ Error: Docker no está instalado"
        exit 1
    fi
    
    if ! docker_retry "docker ps &>/dev/null 2>&1"; then
        echo "❌ Error: No se puede conectar al daemon de Docker"
        exit 1
    fi
}

echo "🚀 Iniciando Traefik en modo PRODUCCIÓN..."
echo ""

# Validar Docker disponible
validate_docker

# ==========================================
# VALIDAR .env EXISTE
# ==========================================
if [ ! -f .env ]; then
    echo "❌ Error: archivo .env no encontrado"
    echo ""
    echo "   Solución: Copia .env.example a .env"
    echo "   $ cp .env.example .env"
    echo ""
    exit 1
fi

# Cargar variables de .env
source .env

echo "📋 Validando configuración de producción..."
echo ""

# ==========================================
# VALIDAR VARIABLES DE ENTORNO CRÍTICAS
# ==========================================
VALIDATION_ERRORS=0

# Validar PROD_DOMAIN
if [ -z "$PROD_DOMAIN" ] || [ "$PROD_DOMAIN" = "example.com" ] || [ "$PROD_DOMAIN" = "tu-dominio.com" ]; then
    echo "❌ Error: PROD_DOMAIN no está configurado correctamente"
    echo "   Valor actual: ${PROD_DOMAIN:-<vacío>}"
    echo "   Debe ser un dominio real (ej: midominio.com)"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Validar LETSENCRYPT_EMAIL
if [ -z "$LETSENCRYPT_EMAIL" ] || [ "$LETSENCRYPT_EMAIL" = "tu-email@example.com" ]; then
    echo "❌ Error: LETSENCRYPT_EMAIL no está configurado correctamente"
    echo "   Valor actual: ${LETSENCRYPT_EMAIL:-<vacío>}"
    echo "   Debe ser un email válido"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Validar TRAEFIK_DASHBOARD_USER
if [ -z "$TRAEFIK_DASHBOARD_USER" ]; then
    echo "❌ Error: TRAEFIK_DASHBOARD_USER no está definido en .env"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Validar TRAEFIK_DASHBOARD_PASSWORD
if [ -z "$TRAEFIK_DASHBOARD_PASSWORD" ]; then
    echo "❌ Error: TRAEFIK_DASHBOARD_PASSWORD no está definido en .env"
    echo "   Genera un hash bcrypt:"
    echo "   $ htpasswd -nb admin tu_password_seguro"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
elif [ "$TRAEFIK_DASHBOARD_PASSWORD" = "admin" ] || [ ${#TRAEFIK_DASHBOARD_PASSWORD} -lt 20 ]; then
    echo "❌ Error: TRAEFIK_DASHBOARD_PASSWORD no es seguro"
    echo "   Debe ser un hash bcrypt (mín. 20 caracteres)"
    echo "   Genera uno con: htpasswd -nb admin tu_password_seguro"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Si hay errores críticos, detener
if [ $VALIDATION_ERRORS -gt 0 ]; then
    echo ""
    echo "❌ Se encontraron $VALIDATION_ERRORS error(es) crítico(s)"
    echo "   Por favor, revisa .env y corrige los valores"
    exit 1
fi

echo "✅ Variables de entorno validadas"
echo ""

# ==========================================
# CREAR DIRECTORIOS
# ==========================================
echo "📁 Creando directorios..."
mkdir -p logs/prod
mkdir -p certs/prod
mkdir -p config/dynamic/prod
echo "   ✓ Directorios verificados"

echo ""

# ==========================================
# VALIDAR Y CORREGIR PERMISOS DE acme.json
# ==========================================
echo "🔐 Validando permisos de acme.json..."

ACME_JSON="./certs/prod/acme.json"

if [ ! -f "$ACME_JSON" ]; then
    echo "   📝 Creando acme.json vacío..."
    touch "$ACME_JSON"
    chmod 600 "$ACME_JSON"
    echo "   ✓ Creado con permisos correctos (600)"
else
    # Validar JSON (si existe contenido)
    if [ -s "$ACME_JSON" ] && ! jq empty "$ACME_JSON" 2>/dev/null; then
        echo "   ⚠️  Advertencia: acme.json no es JSON válido"
        echo "   Se regenerarán los certificados"
    fi
    
    # Corregir permisos
    CURRENT_PERMS=$(stat -c %a "$ACME_JSON" 2>/dev/null || stat -f %A "$ACME_JSON" 2>/dev/null)
    if [ "$CURRENT_PERMS" != "600" ]; then
        echo "   ⚠️  Permisos incorrectos: $CURRENT_PERMS"
        echo "   Corrigiendo a 600..."
        chmod 600 "$ACME_JSON"
    fi
    
    # Información sobre backup
    if [ -s "$ACME_JSON" ]; then
        echo "   ✓ acme.json existente y válido"
        echo "   💡 Considera backup: ./scripts/backup-acme.sh"
    else
        echo "   ℹ️  Archivo vacío (se generarán certificados en primer uso)"
    fi
fi

echo ""

# ==========================================
# CREAR REDES DOCKER CON VALIDACIÓN COMPLETA
# ==========================================
echo "🌐 Validando configuración de redes Docker..."

NETWORK_NAME="${TRAEFIK_NETWORK:-traefik-public}"
NETWORK_ERRORS=0

# ==========================================
# VALIDAR RED PÚBLICA
# ==========================================
echo "   Red pública: $NETWORK_NAME"

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "   ✓ Existe"
    
    # Validar driver
    DRIVER=$(docker network inspect "$NETWORK_NAME" -f '{{.Driver}}' 2>/dev/null || echo "")
    if [ "$DRIVER" = "bridge" ]; then
        echo "   ✓ Driver correcto: bridge"
    else
        echo "   ⚠️  Driver incorrecto: $DRIVER (esperado: bridge)"
        NETWORK_ERRORS=$((NETWORK_ERRORS + 1))
    fi
    
    # Validar que la red está operativa
    if docker run --rm --network "$NETWORK_NAME" alpine ping -c 1 127.0.0.1 &>/dev/null 2>&1; then
        echo "   ✓ Operativa (test de conectividad exitoso)"
    else
        echo "   ⚠️  Red no responde a tests de conectividad"
        NETWORK_ERRORS=$((NETWORK_ERRORS + 1))
    fi
else
    echo "   Creando..."
    
    if docker_retry "docker network create --driver bridge $NETWORK_NAME &>/dev/null"; then
        echo "   ✓ Creada correctamente"
    else
        echo "   ❌ Error al crear red pública"
        NETWORK_ERRORS=$((NETWORK_ERRORS + 1))
    fi
fi

# ==========================================
# VALIDAR RED DE SOCKET-PROXY (si existe)
# ==========================================
if [ -f "docker-compose.socket-proxy.yml" ]; then
    PROXY_NETWORK="traefik-proxy"
    echo "   Red socket-proxy: $PROXY_NETWORK"
    
    if docker network inspect "$PROXY_NETWORK" &>/dev/null 2>&1; then
        echo "   ✓ Existe"
    else
        echo "   ⚠️  No existe"
        echo "   💡 Ejecuta: docker compose -f docker-compose.socket-proxy.yml up -d"
        NETWORK_ERRORS=$((NETWORK_ERRORS + 1))
    fi
fi

# Mostrar diagnóstico si hay errores
if [ $NETWORK_ERRORS -gt 0 ]; then
    echo ""
    echo "⚠️  Se detectaron problemas en las redes:"
    echo "   Diagnosticar: docker network ls && docker network inspect $NETWORK_NAME"
    echo "   Recrear: docker network rm $NETWORK_NAME && ./scripts/start-prod.sh"
fi

echo ""

# ==========================================
# MOSTRAR CONFIGURACIÓN ANTES DE CONFIRMAR
# ==========================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  RESUMEN DE CONFIGURACIÓN PRODUCCIÓN:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Dominio principal:      $PROD_DOMAIN"
echo "Email Let's Encrypt:    $LETSENCRYPT_EMAIL"
echo "Dashboard usuario:      $TRAEFIK_DASHBOARD_USER"
echo "Puerto HTTP:            ${HTTP_PORT:-80}"
echo "Puerto HTTPS:           ${HTTPS_PORT:-443}"
echo "Zona horaria:           ${TZ:-UTC}"
echo ""
echo "Directorios:"
echo "  - Logs:              ./logs/prod"
echo "  - Certificados:      ./certs/prod"
echo "  - acme.json:         $ACME_JSON"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ==========================================
# CONFIRMACIÓN DEL USUARIO
# ==========================================
read -p "¿Continuar con el inicio en PRODUCCIÓN? (s/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "❌ Cancelado"
    exit 0
fi

echo ""

# ==========================================
# LEVANTAR CONTENEDORES
# ==========================================
echo "🔄 Levantando contenedores de producción..."

if docker_retry "docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d"; then
    echo "   ✓ Contenedores iniciados"
else
    echo "   ❌ Error al levantar contenedores"
    exit 1
fi

echo ""

# ==========================================
# ESPERAR Y VALIDAR INICIACIÓN
# ==========================================
echo "⏳ Esperando a que Traefik inicie en producción..."
WAIT_TIME=0
MAX_WAIT=20

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    if docker ps 2>/dev/null | grep -q "traefik"; then
        HEALTH=$(docker inspect traefik -f '{{.State.Health.Status}}' 2>/dev/null || echo "starting")
        
        if [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "starting" ]; then
            sleep 3
            break
        fi
    fi
    
    sleep 1
    WAIT_TIME=$((WAIT_TIME + 1))
done

echo ""

# ==========================================
# VERIFICAR ESTADO FINAL
# ==========================================
if docker ps 2>/dev/null | grep -q "traefik"; then
    HEALTH=$(docker inspect traefik -f '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    
    echo "✅ Traefik iniciado correctamente en modo PRODUCCIÓN"
    echo ""
    echo "📊 Dashboard disponible en:"
    echo "   🔒 https://traefik.$PROD_DOMAIN"
    echo "   (Requiere autenticación)"
    echo ""
    echo "🔐 Certificados Let's Encrypt:"
    echo "   Se generarán automáticamente en la primera petición"
    echo "   Email: $LETSENCRYPT_EMAIL"
    echo "   Dominio: $PROD_DOMAIN"
    echo ""
    echo "📝 Ver logs en tiempo real:"
    echo "   ./scripts/logs.sh"
    echo ""
    echo "� Validar configuración:"
    echo "   ./scripts/validate-network.sh"
    echo ""
    echo "� Realizar backup de acme.json:"
    echo "   ./scripts/backup-acme.sh"
    echo ""
    echo "� Detener Traefik:"
    echo "   ./scripts/stop.sh"
    echo ""
    echo "Health Status: $HEALTH"
else
    echo "❌ Error: Traefik no se inició correctamente"
    echo ""
    echo "   Debug (últimos 30 logs):"
    docker compose -f docker-compose.yml -f docker-compose.prod.yml logs traefik 2>&1 | tail -30
    exit 1
fi
