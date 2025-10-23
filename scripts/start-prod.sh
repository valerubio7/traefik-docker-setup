#!/bin/bash

# ============================================
# INICIAR TRAEFIK EN PRODUCCIÓN
# ============================================

set -e

echo "🚀 Iniciando Traefik en modo PRODUCCIÓN..."

# Verificar que existe .env
if [ ! -f .env ]; then
    echo "❌ Error: archivo .env no encontrado"
    exit 1
fi

# Verificar variables críticas
source .env

if [ -z "$PROD_DOMAIN" ] || [ "$PROD_DOMAIN" = "example.com" ]; then
    echo "❌ Error: PROD_DOMAIN no está configurado correctamente en .env"
    exit 1
fi

if [ -z "$LETSENCRYPT_EMAIL" ] || [ "$LETSENCRYPT_EMAIL" = "tu-email@example.com" ]; then
    echo "❌ Error: LETSENCRYPT_EMAIL no está configurado correctamente en .env"
    exit 1
fi

if [ -z "$TRAEFIK_DASHBOARD_PASSWORD" ] || [ "$TRAEFIK_DASHBOARD_PASSWORD" = "admin" ]; then
    echo "❌ Error: TRAEFIK_DASHBOARD_PASSWORD debe ser un hash seguro"
    echo "   Genera uno con: htpasswd -nb admin tu_password_seguro"
    exit 1
fi

# Crear directorios necesarios
echo "📁 Creando directorios..."
mkdir -p logs/prod
mkdir -p certs/prod

# Crear acme.json con permisos correctos (requerido por Let's Encrypt)
if [ ! -f ./certs/prod/acme.json ]; then
    echo "📝 Creando acme.json..."
    touch ./certs/prod/acme.json
    chmod 600 ./certs/prod/acme.json
fi

# Crear red de Docker si no existe
echo "🌐 Verificando red Docker..."
if ! docker network inspect traefik-public >/dev/null 2>&1; then
    echo "   Creando red traefik-public..."
    docker network create traefik-public
else
    echo "   Red traefik-public ya existe ✓"
fi

# Confirmar antes de continuar
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

# Levantar Traefik
echo "🔄 Levantando contenedores..."
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Esperar a que Traefik esté listo
echo "⏳ Esperando a que Traefik inicie..."
sleep 5

# Verificar estado
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
    echo "   Verifica logs: ./scripts/logs.sh"
    echo ""
    echo "📝 Ver logs en tiempo real:"
    echo "   ./scripts/logs.sh"
    echo ""
    echo "🛑 Detener Traefik:"
    echo "   ./scripts/stop.sh"
else
    echo "❌ Error: Traefik no se inició correctamente"
    echo "   Ver logs: docker compose logs traefik"
    exit 1
fi