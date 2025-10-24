#!/bin/bash

# ============================================
# INICIAR TRAEFIK EN DESARROLLO
# ============================================

set -e

echo "🚀 Iniciando Traefik en modo DESARROLLO..."

# Verificar que existe .env
if [ ! -f .env ]; then
    echo "❌ Error: archivo .env no encontrado"
    echo "   Copia .env.example a .env y configúralo:"
    echo "   cp .env.example .env"
    exit 1
fi

# Verificar que existen certificados de desarrollo
if [ ! -f ./certs/dev/localhost.crt ] || [ ! -f ./certs/dev/localhost.key ]; then
    echo "⚠️  Certificados de desarrollo no encontrados"
    echo "   Generando certificados..."
    ./scripts/generate-dev-certs.sh
fi

# Crear directorios necesarios
echo "📁 Creando directorios..."
mkdir -p logs/dev
mkdir -p certs/dev

# ==========================================
# VERIFICAR PERMISOS DE CERTIFICADOS
# ==========================================
# Certificados autofirmados deben ser legibles
echo "🔐 Verificando permisos de certificados..."
if [ -f ./certs/dev/localhost.crt ] && [ -f ./certs/dev/localhost.key ]; then
    # Asegurar que los permisos sean correctos (644 para crt, 600 para key)
    chmod 644 ./certs/dev/localhost.crt 2>/dev/null || true
    chmod 600 ./certs/dev/localhost.key 2>/dev/null || true
    echo "   ✓ Permisos de certificados verificados"
fi

# Crear red de Docker si no existe
echo "🌐 Verificando red Docker..."
if ! docker network inspect traefik-public >/dev/null 2>&1; then
    echo "   Creando red traefik-public..."
    docker network create traefik-public
else
    echo "   Red traefik-public ya existe ✓"
fi

# Levantar Traefik
echo "🔄 Levantando contenedores..."
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# Esperar a que Traefik esté listo
echo "⏳ Esperando a que Traefik inicie..."
sleep 3

# Verificar estado
if docker ps | grep -q traefik; then
    echo ""
    echo "✅ Traefik iniciado correctamente en modo DESARROLLO"
    echo ""
    echo "📊 Dashboard disponible en:"
    echo "   🌍 http://traefik.localhost:8080"
    echo "   🔒 https://traefik.localhost:8080 (con advertencia de seguridad)"
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