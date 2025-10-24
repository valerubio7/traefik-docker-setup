#!/bin/bash

# ============================================
# DETENER TRAEFIK CON MANEJO DE ERRORES
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
        log_error "Error al detener Traefik (código: $exit_code)"
        echo "   Ejecuta 'docker compose logs traefik' para más información"
    fi
    exit $exit_code
}

trap cleanup EXIT

show_banner "🛑 DETENER TRAEFIK"

# Validar Docker disponible
validate_docker

# Detectar si contenedor está corriendo
if is_container_running traefik; then
    log_info "Contenedor encontrado: traefik"
    
    # Detectar ambiente por label
    ENVIRONMENT=$(detect_environment)
    log_info "Ambiente detectado: $ENVIRONMENT"
    echo ""
    
    # Detener según ambiente
    case "$ENVIRONMENT" in
        dev)
            log_step "Ejecutando: docker compose -f docker-compose.yml -f docker-compose.dev.yml down"
            if docker compose -f docker-compose.yml -f docker-compose.dev.yml down 2>&1; then
                log_success "Traefik (dev) detenido correctamente"
            else
                log_warning "docker compose down retornó estado de error"
                echo "   Intentando detener contenedor directamente..."
                docker stop traefik 2>/dev/null || true
            fi
            ;;
        prod)
            log_step "Ejecutando: docker compose -f docker-compose.yml -f docker-compose.prod.yml down"
            if docker compose -f docker-compose.yml -f docker-compose.prod.yml down 2>&1; then
                log_success "Traefik (prod) detenido correctamente"
            else
                log_warning "docker compose down retornó estado de error"
                echo "   Intentando detener contenedor directamente..."
                docker stop traefik 2>/dev/null || true
            fi
            ;;
        *)
            log_warning "No se pudo detectar ambiente, usando down genérico"
            if docker compose down 2>&1; then
                log_success "Traefik detenido correctamente (modo genérico)"
            else
                docker stop traefik 2>/dev/null || true
                log_success "Traefik detenido (fuerza)"
            fi
            ;;
    esac
else
    log_info "Contenedor traefik no está corriendo"
fi

echo ""

# Verificar estado final
if is_container_running traefik; then
    log_warning "Contenedor aún está corriendo"
    echo "   Intenta: docker rm -f traefik"
else
    log_success "Verificación: Contenedor no está activo"
fi

echo ""
log_info "Para iniciar nuevamente:"
echo "   Desarrollo: ./scripts/start-dev.sh"
echo "   Producción: ./scripts/start-prod.sh"
echo ""
