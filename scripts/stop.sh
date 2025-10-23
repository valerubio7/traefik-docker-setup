#!/bin/bash

# ============================================
# DETENER TRAEFIK
# ============================================

set -e

echo "🛑 Deteniendo Traefik..."

# Detectar qué ambiente está corriendo
if docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
    # Intentar detectar el ambiente por los volúmenes montados
    if docker inspect traefik | grep -q "traefik.dev.yml"; then
        ENVIRONMENT="dev"
    elif docker inspect traefik | grep -q "traefik.prod.yml"; then
        ENVIRONMENT="prod"
    else
        ENVIRONMENT="unknown"
    fi
    
    echo "   Ambiente detectado: $ENVIRONMENT"
    
    # Detener según ambiente
    if [ "$ENVIRONMENT" = "dev" ]; then
        docker compose -f docker-compose.yml -f docker-compose.dev.yml down
    elif [ "$ENVIRONMENT" = "prod" ]; then
        docker compose -f docker-compose.yml -f docker-compose.prod.yml down
    else
        # Si no se detecta, usar down genérico
        docker compose down
    fi
    
    echo "✅ Traefik detenido correctamente"
else
    echo "ℹ️  Traefik no está corriendo"
fi

echo ""
echo "💡 Para iniciar nuevamente:"
echo "   Desarrollo: ./scripts/start-dev.sh"
echo "   Producción: ./scripts/start-prod.sh"