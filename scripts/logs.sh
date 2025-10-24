#!/bin/bash

# ============================================
# VER LOGS DE TRAEFIK CON MANEJO ROBUSTO
# ============================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# ==========================================
# FUNCIÓN: Ayuda
# ==========================================
show_help() {
    cat << 'EOF'
📝 Herramienta de logs de Traefik

Uso: ./scripts/logs.sh [opciones]

OPCIONES:
  (sin opciones)     Logs del contenedor en tiempo real
  -f, --follow       Seguir logs en tiempo real (igual que sin opciones)
  -a, --access       Ver logs de acceso HTTP
  -e, --error        Ver solo líneas de error/warning
  -t, --tail N       Mostrar últimas N líneas (default: 100)
  -l, --live-dash    Dashboard en vivo (requiere jq)
  -s, --search STR   Buscar patrón en logs
  -h, --help         Mostrar esta ayuda

EJEMPLOS:
  ./scripts/logs.sh                 # Ver logs en tiempo real
  ./scripts/logs.sh -a              # Ver logs de acceso
  ./scripts/logs.sh -t 50           # Ver últimas 50 líneas
  ./scripts/logs.sh -e              # Ver solo errores
  ./scripts/logs.sh -s "error"      # Buscar "error" en logs
  ./scripts/logs.sh -l              # Dashboard en vivo

ATAJOS:
  Ctrl+C              Detener
  Ctrl+L              Limpiar pantalla (en tiempo real)

EOF
}

# ==========================================
# FUNCIÓN: Validar Docker
# ==========================================
validate_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Error: Docker no está instalado${NC}"
        exit 1
    fi
    
    if ! docker ps &>/dev/null 2>&1; then
        echo -e "${RED}❌ Error: No se puede conectar al daemon de Docker${NC}"
        exit 1
    fi
}

# ==========================================
# FUNCIÓN: Detectar contenedor
# ==========================================
detect_environment() {
    # Verificar que contenedor está corriendo
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^traefik$"; then
        echo -e "${RED}❌ Error: Contenedor traefik no está corriendo${NC}"
        echo "   Inicia Traefik primero:"
        echo "   ./scripts/start-dev.sh  (desarrollo)"
        echo "   ./scripts/start-prod.sh (producción)"
        exit 1
    fi
    
    # Detectar ambiente
    if docker inspect traefik 2>/dev/null | grep -q "traefik.dev.yml"; then
        ENVIRONMENT="dev"
    elif docker inspect traefik 2>/dev/null | grep -q "traefik.prod.yml"; then
        ENVIRONMENT="prod"
    else
        ENVIRONMENT="unknown"
    fi
    
    LOG_PATH="logs/$ENVIRONMENT"
}

# ==========================================
# FUNCIÓN: Dashboard en vivo
# ==========================================
show_live_dashboard() {
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠️  jq no está instalado${NC}"
    # Validar que jq está disponible
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠️  jq no está instalado${NC}"
        echo "   Para dashboard en vivo se requiere jq"
        echo ""
        echo "   Instala en Ubuntu/Debian:"
        echo "   $ sudo apt-get install jq"
        echo ""
        echo "   Instala en Alpine:"
        echo "   $ apk add jq"
        echo ""
        echo "   Alternativa: ./scripts/logs.sh -t 50"
        exit 1
    fi
    
    echo -e "${MAGENTA}🔄 Dashboard en vivo (Ctrl+C para salir)${NC}"
    echo ""
    
    while true; do
        clear
        echo -e "${MAGENTA}═══════════════════════════════════════════${NC}"
        echo -e "${MAGENTA}📊 TRAEFIK DASHBOARD EN VIVO - $ENVIRONMENT${NC}"
        echo -e "${MAGENTA}═══════════════════════════════════════════${NC}"
        echo ""
        
        # Mostrar estado del contenedor
        docker ps -a --filter name=traefik --format "Contenedor: {{.Names}}\nEstado: {{.State}}\nImagen: {{.Image}}" 2>/dev/null
        
        echo ""
        echo -e "${BLUE}───────────────────────────────────────────${NC}"
        echo "📈 Estadísticas:"
        echo -e "${BLUE}───────────────────────────────────────────${NC}"
        
        # CPU y Memoria
        if docker stats --no-stream traefik 2>/dev/null | tail -1; then
            :
        fi
        
        echo ""
        echo -e "${BLUE}───────────────────────────────────────────${NC}"
        echo "📝 Últimos logs (últimas 10 líneas):"
        echo -e "${BLUE}───────────────────────────────────────────${NC}"
        
        docker logs --tail 10 traefik 2>/dev/null | tail -10
        
        echo ""
        echo -e "${BLUE}───────────────────────────────────────────${NC}"
        echo "🔄 Actualizando en 5 segundos... (Ctrl+C para salir)"
        sleep 5
    done
}

# ==========================================
# FUNCIÓN: Buscar en logs
# ==========================================
search_logs() {
    local pattern="$1"
    
    if [ -z "$pattern" ]; then
        echo -e "${RED}❌ Error: Debes especificar un patrón${NC}"
        echo "   Uso: ./scripts/logs.sh -s 'patrón'"
        exit 1
    fi
    
    echo -e "${BLUE}🔍 Buscando: '$pattern'${NC}"
    echo ""
    
    # Buscar en logs del contenedor
    docker logs traefik 2>&1 | grep -i "$pattern" || {
        echo -e "${YELLOW}⚠️  No se encontraron coincidencias${NC}"
    }
    
    # Buscar en archivos de log locales si existen
    if [ -f "$LOG_PATH/access.log" ]; then
        echo ""
        echo -e "${BLUE}En access.log:${NC}"
        grep -i "$pattern" "$LOG_PATH/access.log" 2>/dev/null || {
            echo -e "${YELLOW}   Sin coincidencias${NC}"
        }
    fi
}

# ==========================================
# VALIDAR PREREQUISITES
# ==========================================
validate_docker
detect_environment

echo -e "${BLUE}📊 Traefik - Ambiente: ${ENVIRONMENT}${NC}"
echo ""

# ==========================================
# PROCESAR ARGUMENTOS
# ==========================================
case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
    -a|--access)
        echo -e "${GREEN}📋 Logs de acceso (Ctrl+C para salir)${NC}"
        echo ""
        
        if [ -f "$LOG_PATH/access.log" ]; then
            tail -f "$LOG_PATH/access.log"
        else
            echo -e "${YELLOW}⚠️  Archivo de logs de acceso no encontrado: $LOG_PATH/access.log${NC}"
            echo "   Alternativa: Ver docker logs"
            docker logs -f --tail 50 traefik
        fi
        ;;
    -e|--error)
        echo -e "${RED}🚨 Logs de errores y advertencias${NC}"
        echo ""
        
        # Buscar errores en logs del contenedor
        ERRORS=$(docker logs traefik 2>&1 | grep -iE "error|warn|fatal|panic" || echo "")
        
        if [ -z "$ERRORS" ]; then
            echo -e "${GREEN}✅ No se encontraron errores${NC}"
        else
            echo "$ERRORS"
        fi
        
        # También mostrar errores en archivos locales
        if [ -f "$LOG_PATH/access.log" ]; then
            echo ""
            echo -e "${RED}En access.log:${NC}"
            grep -E "5[0-9]{2} |4[0-9]{2} " "$LOG_PATH/access.log" 2>/dev/null | tail -10 || {
                echo -e "${GREEN}   Sin errores HTTP${NC}"
            }
        fi
        ;;
    -t|--tail)
        LINES=${2:-100}
        
        if ! [[ "$LINES" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}❌ Error: -t requiere un número${NC}"
            exit 1
        fi
        
        echo -e "${YELLOW}📜 Últimas $LINES líneas${NC}"
        echo ""
        docker logs --tail "$LINES" traefik 2>&1
        ;;
    -l|--live-dash)
        show_live_dashboard
        ;;
    -s|--search)
        search_logs "$2"
        ;;
    -f|--follow|"")
        echo -e "${GREEN}🔄 Siguiendo logs en tiempo real (Ctrl+C para salir)${NC}"
        echo -e "${GREEN}Consejo: Usa 'Ctrl+L' para limpiar pantalla${NC}"
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
