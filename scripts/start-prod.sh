#!/bin/bash

# ============================================
# INICIAR TRAEFIK EN PRODUCCIÓN
# ============================================
# Script robusto con validaciones exhaustivas
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
        log_error "Error al iniciar Traefik en producción (código: $exit_code)"
        echo "   Diagnosticar:"
        echo "   - Ver logs: docker compose logs traefik"
        echo "   - Verificar red: docker network ls"
        echo "   - Validar permisos: ls -la certs/prod/"
    fi
    exit $exit_code
}

trap cleanup EXIT

show_banner "🚀 INICIAR TRAEFIK - PRODUCCIÓN"

# ==========================================
# VALIDACIONES INICIALES
# ==========================================
validate_docker
validate_env_file

echo ""
log_step "Validando configuración de producción..."
echo ""

# ==========================================
# VALIDAR VARIABLES DE ENTORNO CRÍTICAS
# ==========================================
VALIDATION_ERRORS=0

# Validar PROD_DOMAIN
if [ -z "$PROD_DOMAIN" ] || [ "$PROD_DOMAIN" = "example.com" ] || [ "$PROD_DOMAIN" = "tu-dominio.com" ]; then
    log_error "PROD_DOMAIN no está configurado correctamente"
    echo "   Valor actual: ${PROD_DOMAIN:-<vacío>}"
    echo "   Debe ser un dominio real (ej: midominio.com)"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
elif ! validate_domain_format "$PROD_DOMAIN"; then
    log_error "PROD_DOMAIN tiene formato inválido"
    echo "   Valor: $PROD_DOMAIN"
    echo "   Formato válido: midominio.com (sin http://, sin puerto, sin localhost)"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
    log_success "PROD_DOMAIN válido: $PROD_DOMAIN"
fi

# Validar LETSENCRYPT_EMAIL
if [ -z "$LETSENCRYPT_EMAIL" ] || [ "$LETSENCRYPT_EMAIL" = "tu-email@example.com" ]; then
    log_error "LETSENCRYPT_EMAIL no está configurado correctamente"
    echo "   Valor actual: ${LETSENCRYPT_EMAIL:-<vacío>}"
    echo "   Debe ser un email válido"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
elif [[ ! "$LETSENCRYPT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    log_error "LETSENCRYPT_EMAIL tiene formato inválido"
    echo "   Valor: $LETSENCRYPT_EMAIL"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
    log_success "LETSENCRYPT_EMAIL válido: $LETSENCRYPT_EMAIL"
fi

# Validar TRAEFIK_DASHBOARD_USER
if [ -z "$TRAEFIK_DASHBOARD_USER" ]; then
    log_error "TRAEFIK_DASHBOARD_USER no está definido en .env"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
    log_success "TRAEFIK_DASHBOARD_USER configurado"
fi

# Validar TRAEFIK_DASHBOARD_PASSWORD (MEJORADO)
if [ -z "$TRAEFIK_DASHBOARD_PASSWORD" ]; then
    log_error "TRAEFIK_DASHBOARD_PASSWORD no está definido en .env"
    echo ""
    echo "   Genera un hash bcrypt con:"
    echo "   $ htpasswd -nbB admin tu_password_seguro"
    echo ""
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
elif ! validate_bcrypt_hash "$TRAEFIK_DASHBOARD_PASSWORD"; then
    log_error "TRAEFIK_DASHBOARD_PASSWORD no es un hash válido"
    echo "   El password debe ser un hash bcrypt o apache MD5"
    echo "   Formato esperado:"
    echo "   - bcrypt: \$2a\$... (60 caracteres)"
    echo "   - apache: \$apr1\$... (37+ caracteres)"
    echo ""
    echo "   Genera un hash con:"
    echo "   $ htpasswd -nbB admin tu_password_seguro"
    echo ""
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
else
    log_success "TRAEFIK_DASHBOARD_PASSWORD es un hash válido"
fi

# Si hay errores críticos, detener
if [ $VALIDATION_ERRORS -gt 0 ]; then
    echo ""
    log_error "Se encontraron $VALIDATION_ERRORS error(es) crítico(s)"
    echo "   Por favor, revisa .env y corrige los valores"
    exit 1
fi

echo ""

# ==========================================
# CREAR DIRECTORIOS
# ==========================================
log_step "Creando directorios..."
create_secure_dir "logs/prod" 755
create_secure_dir "certs/prod" 755
create_secure_dir "config/dynamic/prod" 755
log_success "Directorios verificados"

echo ""

# ==========================================
# VALIDAR Y CORREGIR PERMISOS DE acme.json
# ==========================================
log_step "Validando permisos de acme.json..."

ACME_JSON="./certs/prod/acme.json"

if [ ! -f "$ACME_JSON" ]; then
    log_info "Creando acme.json vacío..."
    touch "$ACME_JSON"
    chmod 600 "$ACME_JSON"
    log_success "Creado con permisos correctos (600)"
else
    # Validar JSON (si existe contenido)
    if [ -s "$ACME_JSON" ]; then
        if validate_json "$ACME_JSON"; then
            log_success "acme.json existente y válido"
            log_info "Considera backup: ./scripts/backup-acme.sh"
        else
            log_warning "acme.json no es JSON válido"
            echo "   Se regenerarán los certificados"
        fi
    else
        log_info "Archivo vacío (se generarán certificados en primer uso)"
    fi
    
    # Corregir permisos
    CURRENT_PERMS=$(stat -c %a "$ACME_JSON" 2>/dev/null || stat -f %A "$ACME_JSON" 2>/dev/null)
    if [ "$CURRENT_PERMS" != "600" ]; then
        log_warning "Permisos incorrectos: $CURRENT_PERMS"
        chmod 600 "$ACME_JSON"
        log_success "Corregidos a 600"
    fi
fi

echo ""

# ==========================================
# CREAR REDES DOCKER CON VALIDACIÓN
# ==========================================
log_step "Validando configuración de redes Docker..."

NETWORK_NAME="${TRAEFIK_NETWORK:-traefik-public}"

if create_docker_network "$NETWORK_NAME"; then
    log_success "Red '$NETWORK_NAME' lista"
else
    log_error "Problemas con la red Docker"
    echo "   Diagnosticar: docker network inspect $NETWORK_NAME"
fi

echo ""

# ==========================================
# VALIDAR PUERTOS DISPONIBLES
# ==========================================
log_step "Validando disponibilidad de puertos..."

HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"

if ! is_port_available "$HTTP_PORT"; then
    log_warning "Puerto $HTTP_PORT ya está en uso"
    echo "   Identifica el proceso: sudo lsof -i :$HTTP_PORT"
fi

if ! is_port_available "$HTTPS_PORT"; then
    log_warning "Puerto $HTTPS_PORT ya está en uso"
    echo "   Identifica el proceso: sudo lsof -i :$HTTPS_PORT"
fi

echo ""

# ==========================================
# MOSTRAR CONFIGURACIÓN
# ==========================================
show_banner "⚠️  RESUMEN DE CONFIGURACIÓN PRODUCCIÓN"

echo "Dominio principal:      $PROD_DOMAIN"
echo "Email Let's Encrypt:    $LETSENCRYPT_EMAIL"
echo "Dashboard usuario:      $TRAEFIK_DASHBOARD_USER"
echo "Puerto HTTP:            $HTTP_PORT"
echo "Puerto HTTPS:           $HTTPS_PORT"
echo "Zona horaria:           ${TZ:-UTC}"
echo "Red Docker:             $NETWORK_NAME"
echo ""
echo "Directorios:"
echo "  - Logs:              ./logs/prod"
echo "  - Certificados:      ./certs/prod"
echo "  - acme.json:         $ACME_JSON"
echo ""

if [ -n "$PROD_CORS_ORIGINS" ]; then
    echo "CORS configurado:       Sí"
    echo "  Orígenes adicionales: $PROD_CORS_ORIGINS"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ==========================================
# CONFIRMACIÓN
# ==========================================
if ! confirm_action "¿Continuar con el inicio en PRODUCCIÓN?"; then
    log_info "Cancelado por el usuario"
    exit 0
fi

echo ""

# ==========================================
# LEVANTAR CONTENEDORES
# ==========================================
log_step "Levantando contenedores de producción..."

if docker_retry "docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d"; then
    log_success "Contenedores iniciados"
else
    log_error "Error al levantar contenedores"
    exit 1
fi

echo ""

# ==========================================
# ESPERAR Y VALIDAR
# ==========================================
wait_for_healthy "traefik" 30

echo ""

# ==========================================
# VERIFICAR ESTADO FINAL
# ==========================================
if is_container_running "traefik"; then
    HEALTH=$(get_container_health "traefik")
    
    show_banner "✅ TRAEFIK INICIADO EN PRODUCCIÓN"
    
    echo "📊 Dashboard disponible en:"
    echo "   🔒 https://traefik.$PROD_DOMAIN"
    echo "   (Requiere autenticación)"
    echo ""
    echo "🔐 Certificados Let's Encrypt:"
    echo "   Se generarán automáticamente en la primera petición"
    echo "   Email: $LETSENCRYPT_EMAIL"
    echo "   Dominio: $PROD_DOMAIN"
    echo ""
    echo "📝 Ver logs: ./scripts/logs.sh"
    echo "💾 Backup acme.json: ./scripts/backup-acme.sh"
    echo "🛑 Detener: ./scripts/stop.sh"
    echo ""
    echo "Estado de salud: $HEALTH"
    echo ""
else
    log_error "Traefik no se inició correctamente"
    echo ""
    echo "   Debug (últimos 30 logs):"
    docker compose -f docker-compose.yml -f docker-compose.prod.yml logs traefik 2>&1 | tail -30
    exit 1
fi
