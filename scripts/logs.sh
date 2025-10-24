#!/bin/bash

# Traefik Logs Viewer - Versión Simplificada
# Opciones: -h (help), -e (errors), -t N (tail), -f (follow, default)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    cat << 'EOF'
📝 Traefik Logs Viewer

Uso: ./scripts/logs.sh [opciones]

OPCIONES:
  (sin opciones)  Seguir logs en tiempo real
  -f, --follow    Seguir logs en tiempo real (mismo que sin opciones)
  -e, --error     Ver solo errores y warnings
  -t, --tail N    Mostrar últimas N líneas (ej: -t 50)
  -h, --help      Mostrar esta ayuda

EJEMPLOS:
  ./scripts/logs.sh           # Ver logs en tiempo real
  ./scripts/logs.sh -e        # Ver solo errores
  ./scripts/logs.sh -t 50     # Ver últimas 50 líneas
  ./scripts/logs.sh -h        # Ver ayuda

ATAJOS:
  Ctrl+C          Detener

EOF
}

validate_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker no está instalado${NC}"
        exit 1
    fi
    
    if ! docker ps &>/dev/null 2>&1; then
        echo -e "${RED}❌ No se puede conectar a Docker${NC}"
        exit 1
    fi
}

check_container() {
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^traefik$"; then
        echo -e "${RED}❌ Contenedor traefik no está corriendo${NC}"
        echo "   Inicia primero:"
        echo "   ./scripts/start-dev.sh   (desarrollo)"
        echo "   ./scripts/start-prod.sh  (producción)"
        exit 1
    fi
}

# Main
validate_docker
check_container

case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
    -e|--error)
        echo -e "${RED}🚨 Errores y Warnings${NC}"
        echo ""
        docker logs traefik 2>&1 | grep -iE "error|warn|fatal" || \
            echo -e "${GREEN}✅ No hay errores${NC}"
        ;;
    -t|--tail)
        LINES=${2:-100}
        
        if ! [[ "$LINES" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}❌ -t requiere un número${NC}"
            exit 1
        fi
        
        echo -e "${YELLOW}📜 Últimas $LINES líneas${NC}"
        echo ""
        docker logs --tail "$LINES" traefik 2>&1
        ;;
    -f|--follow|"")
        echo -e "${GREEN}🔄 Logs en tiempo real (Ctrl+C para salir)${NC}"
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
