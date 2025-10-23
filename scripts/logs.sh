#!/bin/bash

# ============================================
# VER LOGS DE TRAEFIK
# ============================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función de ayuda
show_help() {
    echo "📝 Herramienta de logs de Traefik"
    echo ""
    echo "Uso: ./scripts/logs.sh [opción]"
    echo ""
    echo "Opciones:"
    echo "  (sin opciones)  - Logs del contenedor en tiempo real"
    echo "  -f, --follow    - Seguir logs en tiempo real (igual que sin opciones)"
    echo "  -a, --access    - Ver logs de acceso"
    echo "  -e, --error     - Ver logs de errores"
    echo "  -t, --tail N    - Mostrar últimas N líneas (default: 100)"
    echo "  -h, --help      - Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  ./scripts/logs.sh                 # Ver logs en tiempo real"
    echo "  ./scripts/logs.sh -a              # Ver logs de acceso"
    echo "  ./scripts/logs.sh -t 50           # Ver últimas 50 líneas"
    echo "  ./scripts/logs.sh -e              # Ver solo errores"
}

# Verificar que Traefik está corriendo
if ! docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
    echo -e "${RED}❌ Error: Traefik no está corriendo${NC}"
    echo "   Inicia Traefik primero:"
    echo "   ./scripts/start-dev.sh  (o start-prod.sh)"
    exit 1
fi

# Detectar ambiente
if docker inspect traefik | grep -q "traefik.dev.yml"; then
    ENVIRONMENT="dev"
    LOG_PATH="logs/dev"
elif docker inspect traefik | grep -q "traefik.prod.yml"; then
    ENVIRONMENT="prod"
    LOG_PATH="logs/prod"
else
    ENVIRONMENT="unknown"
    LOG_PATH="logs"
fi

echo -e "${BLUE}📊 Traefik logs - Ambiente: ${ENVIRONMENT}${NC}"
echo ""

# Procesar argumentos
case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
    -a|--access)
        echo -e "${GREEN}📋 Logs de acceso (Ctrl+C para salir)${NC}"
        tail -f "$LOG_PATH/access.log" 2>/dev/null || \
            echo "Archivo de logs de acceso no encontrado"
        ;;
    -e|--error)
        echo -e "${RED}🚨 Logs de errores${NC}"
        docker logs traefik 2>&1 | grep -i "error\|warn\|fatal"
        ;;
    -t|--tail)
        LINES=${2:-100}
        echo -e "${YELLOW}📜 Últimas $LINES líneas${NC}"
        docker logs --tail "$LINES" traefik
        ;;
    -f|--follow|"")
        echo -e "${GREEN}🔄 Siguiendo logs en tiempo real (Ctrl+C para salir)${NC}"
        echo ""
        docker logs -f --tail 50 traefik
        ;;
    *)
        echo -e "${RED}❌ Opción no reconocida: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac