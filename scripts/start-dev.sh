#!/bin/bash

# ============================================
# INICIAR TRAEFIK EN DESARROLLO
# ============================================

set -e

# ==========================================
# TRAP HANDLERS
# ==========================================
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "❌ Error al iniciar Traefik (código: $exit_code)"
        echo "   Diagnosticar:"
        echo "   - Ver logs: docker compose logs traefik"
        echo "   - Verificar red: ./scripts/validate-network.sh"
        echo "   - Revisar permisos: ls -la certs/dev/"
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

echo "🚀 Iniciando Traefik en modo DESARROLLO..."

# Validar Docker
validate_docker

# ==========================================
# VALIDAR .env
# ==========================================
if [ ! -f .env ]; then
    echo "❌ Error: archivo .env no encontrado"
    echo ""
    echo "   Solución: Copia .env.example a .env"
    echo "   $ cp .env.example .env"
    echo ""
    exit 1
fi

source .env

# ==========================================
# VALIDAR VARIABLES CRÍTICAS DE DEV
# ==========================================
if [ -z "$DEV_DOMAIN" ]; then
    echo "⚠️  DEV_DOMAIN no está definida en .env"
    echo "   Usando valor por defecto: localhost"
    DEV_DOMAIN="localhost"
fi

echo "   Domain: $DEV_DOMAIN"
echo ""

# ==========================================
# GENERAR CERTIFICADOS SI NO EXISTEN
# ==========================================
if [ ! -f ./certs/dev/localhost.crt ] || [ ! -f ./certs/dev/localhost.key ]; then
    echo "⚠️  Certificados de desarrollo no encontrados"
    echo "   Generando certificados autofirmados..."
    
    if [ ! -f ./scripts/generate-dev-certs.sh ]; then
        echo "❌ Error: script generate-dev-certs.sh no encontrado"
        exit 1
    fi
    
    if ./scripts/generate-dev-certs.sh; then
        echo "✅ Certificados generados"
    else
        echo "❌ Error al generar certificados"
        exit 1
    fi
else
    echo "✓ Certificados encontrados"
fi

echo ""

# ==========================================
# CREAR DIRECTORIOS
# ==========================================
echo "📁 Creando directorios..."
mkdir -p logs/dev
mkdir -p certs/dev
mkdir -p config/dynamic/dev
echo "   ✓ Directorios verificados"

echo ""

# ==========================================
# VALIDAR PERMISOS DE CERTIFICADOS
# ==========================================
echo "🔐 Validando permisos de certificados..."

if [ -f ./certs/dev/localhost.crt ] && [ -f ./certs/dev/localhost.key ]; then
    CERT_PERMS=$(stat -c %a ./certs/dev/localhost.crt 2>/dev/null || stat -f %A ./certs/dev/localhost.crt 2>/dev/null || echo "unknown")
    KEY_PERMS=$(stat -c %a ./certs/dev/localhost.key 2>/dev/null || stat -f %A ./certs/dev/localhost.key 2>/dev/null || echo "unknown")
    
    # Ajustar permisos si es necesario
    chmod 644 ./certs/dev/localhost.crt 2>/dev/null || true
    chmod 600 ./certs/dev/localhost.key 2>/dev/null || true
    
    echo "   ✓ Permisos verificados/corregidos"
else
    echo "   ⚠️  Certificados no encontrados"
fi

echo ""

# ==========================================
# CREAR RED DOCKER CON VALIDACIÓN COMPLETA
# ==========================================
echo "🌐 Validando configuración de red Docker..."

NETWORK_NAME="${TRAEFIK_NETWORK:-traefik-public}"
NETWORK_ERRORS=0

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "   ✓ Red '$NETWORK_NAME' existe"
    
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
        echo "   ✓ Red operativa (test de conectividad exitoso)"
    else
        echo "   ⚠️  Red no responde a tests de conectividad"
        NETWORK_ERRORS=$((NETWORK_ERRORS + 1))
    fi
else
    echo "   Creando red $NETWORK_NAME (bridge)..."
    
    if docker_retry "docker network create --driver bridge $NETWORK_NAME &>/dev/null"; then
        echo "   ✓ Red creada correctamente"
    else
        echo "   ❌ Error al crear red"
        NETWORK_ERRORS=$((NETWORK_ERRORS + 1))
    fi
fi

# Si hay errores de red, mostrar diagnóstico
if [ $NETWORK_ERRORS -gt 0 ]; then
    echo ""
    echo "⚠️  Problemas detectados en la red:"
    echo "   Para diagnosticar: docker network inspect $NETWORK_NAME"
    echo "   Para recrear: docker network rm $NETWORK_NAME && ./scripts/start-dev.sh"
fi

echo ""

# ==========================================
# LEVANTAR CONTENEDORES
# ==========================================
echo "🔄 Levantando contenedores..."

if docker_retry "docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d"; then
    echo "   ✓ Contenedores iniciados"
else
    echo "   ❌ Error al levantar contenedores"
    exit 1
fi

echo ""

# ==========================================
# ESPERAR Y VALIDAR INICIACIÓN
# ==========================================
echo "⏳ Esperando a que Traefik inicie..."
WAIT_TIME=0
MAX_WAIT=15

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    if docker ps 2>/dev/null | grep -q "traefik"; then
        # Validar que healthcheck pasa
        HEALTH=$(docker inspect traefik -f '{{.State.Health.Status}}' 2>/dev/null || echo "starting")
        
        if [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "starting" ]; then
            sleep 2
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
    
    echo "✅ Traefik iniciado correctamente en modo DESARROLLO"
    echo ""
    echo "📊 Dashboard disponible en:"
    echo "   🌍 http://$DEV_DOMAIN:8080"
    echo "   🔒 https://$DEV_DOMAIN:8080 (con advertencia de certificado autofirmado)"
    echo ""
    echo "📝 Ver logs en tiempo real:"
    echo "   ./scripts/logs.sh"
    echo ""
    echo "🌐 Validar red Docker:"
    echo "   ./scripts/validate-network.sh"
    echo ""
    echo "🛑 Detener Traefik:"
    echo "   ./scripts/stop.sh"
    echo ""
    echo "Health Status: $HEALTH"
else
    echo "❌ Error: Traefik no se inició correctamente"
    echo ""
    echo "   Debug:"
    docker compose -f docker-compose.yml -f docker-compose.dev.yml logs traefik 2>&1 | tail -20
    exit 1
fi
