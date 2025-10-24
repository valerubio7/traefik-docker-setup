#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/common.sh"

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Error al detener Traefik (código: $exit_code)"
        echo "   Intenta: docker stop traefik"
    fi
    exit $exit_code
}

trap cleanup EXIT

show_banner "🛑 DETENER TRAEFIK"

validate_docker

if is_container_running traefik; then
    log_info "Contenedor encontrado: traefik"
    echo ""
    
    log_step "Deteniendo contenedor..."
    if docker stop traefik 2>&1; then
        log_success "Traefik detenido correctamente"
    else
        log_warning "Error al detener, intentando forzar..."
        docker kill traefik 2>/dev/null || true
    fi
else
    log_info "Contenedor traefik no está corriendo"
fi


echo ""

if is_container_running traefik; then
    log_warning "Contenedor aún está corriendo, intenta: docker kill traefik"
else
    log_success "Verificación: Contenedor detenido correctamente"
fi

echo ""
log_info "Para iniciar nuevamente:"
echo "   Desarrollo: ./scripts/start-dev.sh"
echo "   Producción: ./scripts/start-prod.sh"
echo ""
