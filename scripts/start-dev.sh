#!/bin/bash

# ============================================
# INICIAR TRAEFIK EN DESARROLLO
# ============================================

set -e

# ==========================================
# CARGAR FUNCIONES COMUNES
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ==========================================
# TRAP HANDLERS
# ==========================================
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        log_error "Error al iniciar Traefik (código: $exit_code)"
        echo "   Diagnosticar:"
        echo "   - Ver logs: docker compose logs traefik"
        echo "   - Verificar red: docker network ls"
        echo "   - Revisar permisos: ls -la certs/dev/"
    fi
    exit $exit_code
}

trap cleanup EXIT

show_banner "🚀 INICIAR TRAEFIK - DESARROLLO"

# ==========================================
# VALIDACIONES INICIALES
# ==========================================
validate_docker
validate_env_file

# ==========================================
# VALIDAR VARIABLES DE DEV
# ==========================================
if [ -z "$DEV_DOMAIN" ]; then
    log_warning "DEV_DOMAIN no está definida en .env"
    echo "   Usando valor por defecto: localhost"
    DEV_DOMAIN="localhost"
fi

log_info "Domain: $DEV_DOMAIN"
echo ""

# ==========================================
# GENERAR CERTIFICADOS SI NO EXISTEN
# ==========================================
if [ ! -f ./certs/dev/localhost.crt ] || [ ! -f ./certs/dev/localhost.key ]; then
    log_warning "Certificados de desarrollo no encontrados"
    echo "   Generando certificados autofirmados..."
    
    if [ ! -f ./scripts/generate-dev-certs.sh ]; then
        log_error "Script generate-dev-certs.sh no encontrado"
        exit 1
    fi
    
    if ./scripts/generate-dev-certs.sh; then
        log_success "Certificados generados"
    else
        log_error "Error al generar certificados"
        exit 1
    fi
else
    log_success "Certificados encontrados"
fi

echo ""

# ==========================================
# CREAR DIRECTORIOS
# ==========================================
log_step "Creando directorios..."
create_secure_dir "logs/dev" 755
create_secure_dir "certs/dev" 755
create_secure_dir "config/dynamic/dev" 755
log_success "Directorios verificados"

echo ""

# ==========================================
# VALIDAR PERMISOS DE CERTIFICADOS
# ==========================================
log_step "Validando permisos de certificados..."

if [ -f ./certs/dev/localhost.crt ] && [ -f ./certs/dev/localhost.key ]; then
    chmod 644 ./certs/dev/localhost.crt 2>/dev/null || true
    chmod 600 ./certs/dev/localhost.key 2>/dev/null || true
    log_success "Permisos verificados/corregidos"
else
    log_warning "Certificados no encontrados"
fi

echo ""

# ==========================================
# LIMPIAR CONTENEDORES ANTERIORES
# ==========================================
log_step "Limpiando contenedores anteriores..."

# Detener y eliminar contenedores previos si existen
if docker ps -a --format '{{.Names}}' | grep -q '^traefik$'; then
    docker stop traefik 2>/dev/null || true
    docker rm traefik 2>/dev/null || true
    log_success "Contenedores previos eliminados"
    sleep 2
else
    log_info "No hay contenedores previos"
fi

echo ""

# ==========================================
# CREAR RED DOCKER CON VALIDACIÓN
# ==========================================
log_step "Validando configuración de red Docker..."

NETWORK_NAME="${TRAEFIK_NETWORK:-traefik-public}"

if create_docker_network "$NETWORK_NAME"; then
    log_success "Red '$NETWORK_NAME' lista"
else
    log_error "Problemas con la red Docker"
fi

echo ""

# ==========================================
# LEVANTAR CONTENEDORES
# ==========================================
log_step "Levantando contenedores..."

if docker_retry "docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d"; then
    log_success "Contenedores iniciados"
else
    log_error "Error al levantar contenedores"
    exit 1
fi

echo ""

# ==========================================
# ESPERAR Y VALIDAR INICIACIÓN
# ==========================================
wait_for_healthy "traefik" 20

echo ""

# ==========================================
# VERIFICAR ESTADO FINAL
# ==========================================
if is_container_running "traefik"; then
    HEALTH=$(get_container_health "traefik")
    
    show_banner "✅ TRAEFIK INICIADO EN DESARROLLO"
    
    echo "📊 Dashboard disponible en:"
    echo "   🌍 http://$DEV_DOMAIN:8080"
    echo "   🔒 https://$DEV_DOMAIN:8080 (con advertencia de certificado autofirmado)"
    echo ""
    echo "📝 Ver logs: ./scripts/logs.sh"
    echo "🛑 Detener: ./scripts/stop.sh"
    echo ""
    echo "Estado de salud: $HEALTH"
    echo ""
else
    log_error "Traefik no se inició correctamente"
    echo ""
    echo "   Debug:"
    docker compose -f docker-compose.yml -f docker-compose.dev.yml logs traefik 2>&1 | tail -20
    exit 1
fi
