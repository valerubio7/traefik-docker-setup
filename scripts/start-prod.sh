#!/bin/bash

set -e

echo "🚀 Iniciando Traefik en modo PRODUCCIÓN..."

if [ ! -f .env ]; then
    echo "❌ Error: archivo .env no encontrado"
    exit 1
fi

source .env

VALIDATION_ERRORS=0

if [ -z "$PROD_DOMAIN" ] || [ "$PROD_DOMAIN" = "example.com" ]; then
    echo "❌ Error: PROD_DOMAIN no está configurado correctamente en .env"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if [ -z "$LETSENCRYPT_EMAIL" ] || [ "$LETSENCRYPT_EMAIL" = "tu-email@example.com" ]; then
    echo "❌ Error: LETSENCRYPT_EMAIL no está configurado correctamente en .env"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if [ -z "$TRAEFIK_DASHBOARD_PASSWORD" ] || [ "$TRAEFIK_DASHBOARD_PASSWORD" = "admin" ]; then
    echo "❌ Error: TRAEFIK_DASHBOARD_PASSWORD debe ser un hash seguro"
    echo "   Genera uno con: htpasswd -nb admin tu_password_seguro"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if [ -z "$TRAEFIK_DASHBOARD_USER" ]; then
    echo "❌ Error: TRAEFIK_DASHBOARD_USER no está definido en .env"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

if [ $VALIDATION_ERRORS -gt 0 ]; then
    echo ""
    echo "❌ Se encontraron $VALIDATION_ERRORS error(s) de configuración"
    echo "   Por favor, revisa .env y corrige los valores"
    exit 1
fi

echo "📁 Creando directorios..."
mkdir -p logs/prod
mkdir -p certs/prod

echo "🔐 Verificando permisos de acme.json..."
ACME_JSON="./certs/prod/acme.json"

if [ ! -f "$ACME_JSON" ]; then
    # Crear archivo si no existe
    echo "📝 Creando acme.json con permisos correctos (600)..."
    touch "$ACME_JSON"
    chmod 600 "$ACME_JSON"
    echo "   ✓ Permisos establecidos: 600"
else
    CURRENT_PERMS=$(stat -c %a "$ACME_JSON" 2>/dev/null || stat -f %A "$ACME_JSON" 2>/dev/null)
    if [ "$CURRENT_PERMS" != "600" ]; then
        echo "⚠️  Permisos incorrectos en acme.json: $CURRENT_PERMS (requiere 600)"
        echo "   Corrigiendo permisos..."
        chmod 600 "$ACME_JSON"
        echo "   ✓ Permisos corregidos: 600"
    else
        echo "   ✓ Permisos correctos: 600"
    fi
    
    if [ ! -s "$ACME_JSON" ]; then
        echo "   ℹ️  Archivo vacío (primeras ejecuciones generarán certificados)"
    fi
fi

echo "🌐 Verificando red Docker..."
if ! docker network inspect traefik-public >/dev/null 2>&1; then
    echo "   Creando red traefik-public..."
    docker network create traefik-public
else
    echo "   Red traefik-public ya existe ✓"
fi

echo ""
echo "⚠️  ADVERTENCIA: Estás a punto de iniciar Traefik en PRODUCCIÓN"
echo ""
echo "📋 Configuración:"
echo "   Dominio: $PROD_DOMAIN"
echo "   Email Let's Encrypt: $LETSENCRYPT_EMAIL"
echo ""
read -p "¿Continuar? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cancelado"
    exit 1
fi

echo "🔄 Levantando contenedores..."
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

echo "⏳ Esperando a que Traefik inicie..."
sleep 5

if docker ps | grep -q traefik; then
    echo ""
    echo "✅ Traefik iniciado correctamente en modo PRODUCCIÓN"
    echo ""
    echo "📊 Dashboard disponible en:"
    echo "   🔒 https://traefik.$PROD_DOMAIN"
    echo "   (Requiere autenticación)"
    echo ""
    echo "🔐 Let's Encrypt:"
    echo "   Los certificados se generarán automáticamente en la primera petición"
    echo "   Email configurado: $LETSENCRYPT_EMAIL"
    echo "   Dominio: $PROD_DOMAIN"
    echo "   Verifica logs: ./scripts/logs.sh"
    echo ""
    echo "📝 Ver logs en tiempo real:"
    echo "   ./scripts/logs.sh"
    echo ""
    echo "🛑 Detener Traefik:"
    echo "   ./scripts/stop.sh"
    echo ""
    echo "🔐 Validar permisos:"
    echo "   ./scripts/validate-perms.sh"
else
    echo "❌ Error: Traefik no se inició correctamente"
    echo "   Ver logs: docker compose logs traefik"
    exit 1
fi