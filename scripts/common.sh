#!/bin/bash

# ============================================
# FUNCIONES COMUNES PARA SCRIPTS TRAEFIK
# ============================================
# Este archivo contiene funciones reutilizables
# Usar: source ./scripts/common.sh
# ============================================

# ==========================================
# COLORES PARA OUTPUT
# ==========================================
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# ==========================================
# FUNCIÓN: Log con colores
# ==========================================
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_step() {
    echo -e "${CYAN}🔹 $1${NC}"
}

# ==========================================
# FUNCIÓN: Retry logic para docker commands
# ==========================================
# Uso: docker_retry "docker ps"
docker_retry() {
    local max_retries=3
    local retry_count=0
    local command="$@"
    
    while [ $retry_count -lt $max_retries ]; do
        if eval "$command"; then
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log_warning "Reintentando... ($retry_count/$max_retries)"
            sleep 2
        fi
    done
    
    log_error "Falló después de $max_retries intentos"
    return 1
}

# ==========================================
# FUNCIÓN: Validar Docker está disponible
# ==========================================
validate_docker() {
    log_step "Validando Docker..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker no está instalado"
        echo ""
        echo "   Instalar Docker:"
        echo "   https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! docker_retry "docker ps &>/dev/null 2>&1"; then
        log_error "No se puede conectar al daemon de Docker"
        echo ""
        echo "   Posibles causas:"
        echo "   - Docker daemon no está corriendo"
        echo "   - Tu usuario no tiene permisos (ejecuta: sudo usermod -aG docker \$USER)"
        echo "   - Conflictos con firewall/SELinux"
        exit 1
    fi
    
    log_success "Docker disponible"
}

# ==========================================
# FUNCIÓN: Validar archivo .env existe
# ==========================================
validate_env_file() {
    if [ ! -f .env ]; then
        log_error "Archivo .env no encontrado"
        echo ""
        echo "   Solución:"
        echo "   $ cp .env.example .env"
        echo "   $ nano .env  # Editar configuración"
        exit 1
    fi
    
    # Cargar variables
    source .env
    log_success "Archivo .env cargado"
}

# ==========================================
# FUNCIÓN: Detectar ambiente (dev/prod)
# ==========================================
detect_environment() {
    if docker inspect traefik &>/dev/null; then
        # Buscar label de ambiente
        local env_label=$(docker inspect traefik --format '{{index .Config.Labels "com.traefik.environment"}}' 2>/dev/null || echo "")
        
        if [ -n "$env_label" ]; then
            echo "$env_label"
            return 0
        fi
        
        # Fallback: detectar por variable de entorno
        local env_var=$(docker inspect traefik --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^ENVIRONMENT=' | cut -d'=' -f2 || echo "")
        
        if [ -n "$env_var" ]; then
            echo "$env_var"
            return 0
        fi
        
        # Si no se puede detectar
        echo "unknown"
        return 1
    else
        echo "not-running"
        return 1
    fi
}

# ==========================================
# FUNCIÓN: Validar formato de dominio
# ==========================================
validate_domain_format() {
    local domain="$1"
    local domain_regex='^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$'
    
    # Convertir a lowercase para validación
    domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
    
    if [[ ! $domain =~ $domain_regex ]]; then
        return 1
    fi
    
    # Validar que no sea localhost (inválido para Let's Encrypt)
    if [ "$domain" = "localhost" ] || [[ $domain == *.localhost ]]; then
        return 1
    fi
    
    # Validar que no contenga puerto
    if [[ $domain == *:* ]]; then
        return 1
    fi
    
    # Validar que no contenga protocolo
    if [[ $domain == http://* ]] || [[ $domain == https://* ]]; then
        return 1
    fi
    
    return 0
}

# ==========================================
# FUNCIÓN: Validar hash bcrypt
# ==========================================
validate_bcrypt_hash() {
    local hash="$1"
    
    # Validar formato bcrypt ($2a$, $2b$, $2y$) o apache MD5 ($apr1$)
    if [[ $hash =~ ^\$2[ayb]\$.{56}$ ]] || [[ $hash =~ ^\$apr1\$.{37}$ ]]; then
        return 0
    fi
    
    return 1
}

# ==========================================
# FUNCIÓN: Crear y validar red Docker
# ==========================================
create_docker_network() {
    local network_name="$1"
    
    if docker network inspect "$network_name" >/dev/null 2>&1; then
        log_success "Red '$network_name' existe"
        
        # Validar driver
        local driver=$(docker network inspect "$network_name" -f '{{.Driver}}' 2>/dev/null || echo "")
        if [ "$driver" = "bridge" ]; then
            log_success "Driver correcto: bridge"
        else
            log_warning "Driver incorrecto: $driver (esperado: bridge)"
            return 1
        fi
        
        # Validar que la red tiene configuración válida
        if ! docker network inspect "$network_name" --format '{{json .IPAM.Config}}' | jq empty &>/dev/null; then
            log_warning "Configuración de red corrupta"
            return 1
        fi
        
        return 0
    else
        log_step "Creando red $network_name..."
        
        if docker_retry "docker network create --driver bridge $network_name &>/dev/null"; then
            log_success "Red creada correctamente"
            return 0
        else
            log_error "Error al crear red"
            return 1
        fi
    fi
}

# ==========================================
# FUNCIÓN: Verificar contenedor está corriendo
# ==========================================
is_container_running() {
    local container_name="$1"
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        return 0
    else
        return 1
    fi
}

# ==========================================
# FUNCIÓN: Obtener health status de contenedor
# ==========================================
get_container_health() {
    local container_name="$1"
    
    if is_container_running "$container_name"; then
        docker inspect "$container_name" -f '{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck"
    else
        echo "not-running"
    fi
}

# ==========================================
# FUNCIÓN: Esperar a que contenedor esté healthy
# ==========================================
wait_for_healthy() {
    local container_name="$1"
    local max_wait="${2:-30}"
    local wait_time=0
    
    log_step "Esperando a que $container_name esté saludable..."
    
    while [ $wait_time -lt $max_wait ]; do
        if is_container_running "$container_name"; then
            local health=$(get_container_health "$container_name")
            
            if [ "$health" = "healthy" ]; then
                log_success "$container_name está saludable"
                return 0
            elif [ "$health" = "unhealthy" ]; then
                log_error "$container_name está unhealthy"
                return 1
            fi
            # Si está "starting" o "no-healthcheck", continuar esperando
        fi
        
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    log_warning "Timeout esperando a $container_name"
    return 1
}

# ==========================================
# FUNCIÓN: Validar dependencias de sistema
# ==========================================
check_dependencies() {
    local missing_deps=()
    
    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Dependencias faltantes: ${missing_deps[*]}"
        echo ""
        echo "   Instalar en Ubuntu/Debian:"
        echo "   $ sudo apt-get install ${missing_deps[*]}"
        echo ""
        echo "   Instalar en Alpine:"
        echo "   $ apk add ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# ==========================================
# FUNCIÓN: Crear directorio con permisos seguros
# ==========================================
create_secure_dir() {
    local dir_path="$1"
    local perms="${2:-755}"
    
    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path"
        chmod "$perms" "$dir_path"
        log_success "Directorio creado: $dir_path (permisos: $perms)"
    fi
}

# ==========================================
# FUNCIÓN: Backup de archivo con timestamp
# ==========================================
backup_file() {
    local file_path="$1"
    
    if [ -f "$file_path" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_path="${file_path}.backup_${timestamp}"
        
        cp "$file_path" "$backup_path"
        log_success "Backup creado: $backup_path"
        return 0
    else
        log_warning "Archivo no existe: $file_path"
        return 1
    fi
}

# ==========================================
# FUNCIÓN: Validar JSON
# ==========================================
validate_json() {
    local file_path="$1"
    
    if [ ! -f "$file_path" ]; then
        return 1
    fi
    
    if jq empty "$file_path" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ==========================================
# FUNCIÓN: Mostrar banner
# ==========================================
show_banner() {
    local title="$1"
    local width=60
    
    echo ""
    printf '%.0s═' $(seq 1 $width)
    echo ""
    printf "%-${width}s\n" "$title"
    printf '%.0s═' $(seq 1 $width)
    echo ""
    echo ""
}

# ==========================================
# FUNCIÓN: Confirmar acción (sí/no)
# ==========================================
confirm_action() {
    local prompt="$1"
    local default="${2:-N}"
    
    if [ "$default" = "Y" ] || [ "$default" = "y" ]; then
        read -p "$prompt (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            return 1
        else
            return 0
        fi
    else
        read -p "$prompt (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        else
            return 1
        fi
    fi
}

# ==========================================
# FUNCIÓN: Obtener IP pública del servidor
# ==========================================
get_public_ip() {
    curl -s https://api.ipify.org 2>/dev/null || \
    curl -s https://ifconfig.me 2>/dev/null || \
    curl -s https://icanhazip.com 2>/dev/null || \
    echo "unavailable"
}

# ==========================================
# FUNCIÓN: Validar puerto está libre
# ==========================================
is_port_available() {
    local port="$1"
    
    if command -v netstat &> /dev/null; then
        ! netstat -tuln 2>/dev/null | grep -q ":${port} "
    elif command -v ss &> /dev/null; then
        ! ss -tuln 2>/dev/null | grep -q ":${port} "
    else
        # Fallback: intentar bind temporal
        (echo >/dev/tcp/127.0.0.1/$port) &>/dev/null
        [ $? -ne 0 ]
    fi
}
