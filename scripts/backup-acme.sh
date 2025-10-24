#!/bin/bash

# ============================================
# BACKUP AUTOMÁTICO DE acme.json
# ============================================
# Realiza backups de acme.json (certificados Let's Encrypt)
# - Mantiene N copias (default: 7)
# - Valida integridad
# - Puede ejecutarse desde cron
# - Compresión gzip opcional
# ============================================

set -e

# Configuración
ACME_FILE="./certs/prod/acme.json"
BACKUP_DIR="./certs/prod/backups"
MAX_BACKUPS="${BACKUP_RETENTION:-7}"
COMPRESS="${COMPRESS_BACKUPS:-true}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ==========================================
# FUNCIÓN: Log con timestamp
# ==========================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: $1${NC}" >&2
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

# ==========================================
# VALIDAR ARCHIVO EXISTE
# ==========================================
if [ ! -f "$ACME_FILE" ]; then
    log_error "Archivo no encontrado: $ACME_FILE"
    exit 1
fi

# Validar que es JSON válido
if ! file "$ACME_FILE" | grep -q "JSON"; then
    if ! jq empty "$ACME_FILE" 2>/dev/null; then
        log_error "acme.json no es JSON válido"
        exit 1
    fi
fi

log "Iniciando backup de acme.json"
log "Archivo origen: $ACME_FILE"

# ==========================================
# CREAR DIRECTORIO DE BACKUPS
# ==========================================
if [ ! -d "$BACKUP_DIR" ]; then
    log "Creando directorio de backups: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
fi

# ==========================================
# VALIDAR PERMISOS DE ACME.JSON
# ==========================================
PERMS=$(stat -c %a "$ACME_FILE" 2>/dev/null || stat -f %A "$ACME_FILE" 2>/dev/null)
if [ "$PERMS" != "600" ] && [ "$PERMS" != "644" ]; then
    log_warning "Permisos de acme.json: $PERMS (esperado: 600 o 644)"
fi

# ==========================================
# REALIZAR BACKUP
# ==========================================
if [ "$COMPRESS" = "true" ]; then
    BACKUP_FILE="$BACKUP_DIR/acme_${TIMESTAMP}.json.gz"
    log "Creando backup comprimido: $BACKUP_FILE"
    
    if gzip -c "$ACME_FILE" > "$BACKUP_FILE"; then
        chmod 600 "$BACKUP_FILE"
        SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        log_success "Backup creado: $SIZE"
    else
        log_error "Fallo al crear backup comprimido"
        exit 1
    fi
else
    BACKUP_FILE="$BACKUP_DIR/acme_${TIMESTAMP}.json"
    log "Creando backup: $BACKUP_FILE"
    
    if cp "$ACME_FILE" "$BACKUP_FILE"; then
        chmod 600 "$BACKUP_FILE"
        SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        log_success "Backup creado: $SIZE"
    else
        log_error "Fallo al crear backup"
        exit 1
    fi
fi

# ==========================================
# VALIDAR INTEGRIDAD DEL BACKUP
# ==========================================
log "Validando integridad del backup..."

if [ "$COMPRESS" = "true" ]; then
    if gunzip -t "$BACKUP_FILE" &>/dev/null; then
        log_success "Integridad validada (comprimido)"
    else
        log_error "Archivo comprimido corrupto"
        rm "$BACKUP_FILE"
        exit 1
    fi
else
    if jq empty "$BACKUP_FILE" 2>/dev/null; then
        log_success "Integridad validada (JSON válido)"
    else
        log_error "Backup JSON no es válido"
        rm "$BACKUP_FILE"
        exit 1
    fi
fi

# ==========================================
# LIMPIAR BACKUPS ANTIGUOS
# ==========================================
log "Limpiando backups antiguos (mantener: $MAX_BACKUPS)"

# Contar backups existentes
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/acme_*.json* 2>/dev/null | wc -l)

if [ $BACKUP_COUNT -gt $MAX_BACKUPS ]; then
    # Borrar los más antiguos, manteniendo MAX_BACKUPS
    BACKUPS_TO_DELETE=$((BACKUP_COUNT - MAX_BACKUPS))
    log_warning "Hay $BACKUP_COUNT backups. Eliminando $BACKUPS_TO_DELETE más antiguos..."
    
    ls -1t "$BACKUP_DIR"/acme_*.json* 2>/dev/null | tail -n $BACKUPS_TO_DELETE | while read -r old_backup; do
        log "Eliminando backup antiguo: $(basename "$old_backup")"
        rm "$old_backup"
    done
    
    log_success "Backups antiguos eliminados"
fi

# ==========================================
# MOSTRAR RESUMEN
# ==========================================
echo ""
log_success "Backup completado exitosamente"
echo ""
echo "📋 Resumen de backups:"
echo "────────────────────────────────────"
ls -lh "$BACKUP_DIR"/acme_*.json* 2>/dev/null | tail -5 | awk '{printf "   %s  %s\n", $5, $9}'
echo ""
echo "Total: $(ls -1 "$BACKUP_DIR"/acme_*.json* 2>/dev/null | wc -l) backup(s)"
echo ""

# ==========================================
# INFORMACIÓN PARA CRON
# ==========================================
if [ -z "$PS1" ]; then
    # Ejecutado desde cron (no interactivo)
    log "Ejecución desde cron completada"
else
    # Ejecutado interactivamente
    echo "💡 Para automatizar en cron (diario a las 3 AM):"
    echo ""
    echo "   0 3 * * * cd /home/valerubio_7/Dev/infra/traefik && ./scripts/backup-acme.sh >> /var/log/traefik-backup.log 2>&1"
    echo ""
    echo "📝 Para restaurar un backup:"
    echo ""
    echo "   # Descomprimir (si está comprimido)"
    echo "   gunzip -c $BACKUP_DIR/acme_YYYYMMDD_HHMMSS.json.gz > ./certs/prod/acme.json"
    echo ""
    echo "   # Restaurar permisos"
    echo "   chmod 600 ./certs/prod/acme.json"
    echo ""
    echo "   # Reiniciar Traefik"
    echo "   ./scripts/stop.sh && ./scripts/start-prod.sh"
    echo ""
fi
