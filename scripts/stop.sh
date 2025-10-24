#!/bin/bash

# ============================================
# DETENER TRAEFIK CON MANEJO DE ERRORES
# ============================================

set -e

# ==========================================
# TRAP HANDLERS para limpiar en caso de error
# ==========================================
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "❌ Error al detener Traefik (código: $exit_code)"
        echo "   Ejecuta 'docker compose logs traefik' para más información"
    fi
    exit $exit_code
}

trap cleanup EXIT

# ==========================================
# FUNCIÓN: Validar que Docker está disponible
# ==========================================
validate_docker() {
    if ! command -v docker &> /dev/null; then
        echo "❌ Error: Docker no está instalado o no es accesible"
        exit 1
    fi
    
    if ! docker ps &>/dev/null 2>&1; then
        echo "❌ Error: No se puede conectar al daemon de Docker"
        echo "   Verifica permisos: sudo usermod -aG docker \$USER"
        exit 1
    fi
}

# ==========================================
# FUNCIÓN: Detectar si contenedor existe
# ==========================================
container_exists() {
    local container=$1
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"
}

# ==========================================
# FUNCIÓN: Detectar ambiente con retry logic
# ==========================================
detect_environment() {
    local max_retries=3
    local retry_count=0
    
    # Reintentar inspección si falla
    while [ $retry_count -lt $max_retries ]; do
        if docker inspect traefik &>/dev/null 2>&1; then
            if docker inspect traefik 2>/dev/null | grep -q "traefik.dev.yml"; then
                echo "dev"
                return 0
            elif docker inspect traefik 2>/dev/null | grep -q "traefik.prod.yml"; then
                echo "prod"
                return 0
            else
                echo "unknown"
                return 0
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            sleep 1
        fi
    done
    
    # Si falla después de reintentos, detectar por variables de entorno
    if [ -f .env ]; then
        if grep -q "ENVIRONMENT=prod" .env; then
            echo "prod"
            return 0
        fi
    fi
    
    echo "unknown"
    return 0
}

echo "🛑 Deteniendo Traefik..."

# Validar Docker disponible
validate_docker

# Detectar si contenedor está corriendo
if container_exists traefik; then
    echo "   Contenedor encontrado: traefik"
    
    # Detectar ambiente
    ENVIRONMENT=$(detect_environment)
    echo "   Ambiente detectado: $ENVIRONMENT"
    
    # Detener según ambiente
    if [ "$ENVIRONMENT" = "dev" ]; then
        echo "   Ejecutando: docker compose -f docker-compose.yml -f docker-compose.dev.yml down"
        if docker compose -f docker-compose.yml -f docker-compose.dev.yml down 2>&1; then
            echo "✅ Traefik (dev) detenido correctamente"
        else
            echo "⚠️  Advertencia: docker compose down retornó estado de error"
            echo "   Intentando detener contenedor directamente..."
            docker stop traefik 2>/dev/null || true
        fi
    elif [ "$ENVIRONMENT" = "prod" ]; then
        echo "   Ejecutando: docker compose -f docker-compose.yml -f docker-compose.prod.yml down"
        if docker compose -f docker-compose.yml -f docker-compose.prod.yml down 2>&1; then
            echo "✅ Traefik (prod) detenido correctamente"
        else
            echo "⚠️  Advertencia: docker compose down retornó estado de error"
            echo "   Intentando detener contenedor directamente..."
            docker stop traefik 2>/dev/null || true
        fi
    else
        echo "   ⚠️  No se pudo detectar ambiente, usando down genérico"
        if docker compose down 2>&1; then
            echo "✅ Traefik detenido correctamente (modo genérico)"
        else
            docker stop traefik 2>/dev/null || true
            echo "✅ Traefik detenido (fuerza)"
        fi
    fi
else
    echo "ℹ️  Contenedor traefik no está corriendo"
fi

# Verificar estado final
if container_exists traefik && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^traefik$"; then
    echo "⚠️  Advertencia: Contenedor aún está corriendo"
    echo "   Intenta: docker rm -f traefik"
else
    echo "✅ Verificación: Contenedor no está activo"
fi

echo ""
echo "💡 Para iniciar nuevamente:"
echo "   Desarrollo: ./scripts/start-dev.sh"
echo "   Producción: ./scripts/start-prod.sh"