#!/bin/bash

set -e

ACME_FILE="./certs/prod/acme.json"
BACKUP_DIR="./certs/prod/backups"
MAX_BACKUPS="${BACKUP_RETENTION:-7}"
COMPRESS="${COMPRESS_BACKUPS:-true}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

if [ ! -f "$ACME_FILE" ]; then
    log_error "Archivo no encontrado: $ACME_FILE"
    exit 1
fi

if ! file "$ACME_FILE" | grep -q "JSON"; then
    if ! jq empty "$ACME_FILE" 2>/dev/null; then
        log_error "acme.json no es JSON válido"
        exit 1
    fi
fi

log "Iniciando backup de acme.json"
log "Archivo origen: $ACME_FILE"

if [ ! -d "$BACKUP_DIR" ]; then
    log "Creando directorio de backups: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
fi

PERMS=$(stat -c %a "$ACME_FILE" 2>/dev/null || stat -f %A "$ACME_FILE" 2>/dev/null)
if [ "$PERMS" != "600" ] && [ "$PERMS" != "644" ]; then
    log_warning "Permisos de acme.json: $PERMS (esperado: 600 o 644)"
fi

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
    if ! jq empty "$BACKUP_FILE" 2>/dev/null; then
        log_error "Backup JSON no es válido"
        rm "$BACKUP_FILE"
        exit 1
    fi
    
    log_success "Integridad validada (JSON válido)"
    
    CERT_COUNT=$(jq -r 'if type == "object" then .letsencrypt.Certificates // [] | length else 0 end' "$BACKUP_FILE" 2>/dev/null || echo "0")
    
    if [ "$CERT_COUNT" -eq "0" ]; then
        log_warning "Backup no contiene certificados (archivo vacío o recién creado)"
    else
        log_success "Backup contiene $CERT_COUNT certificado(s)"
        
        EXPIRING_SOON=0
        for i in $(seq 0 $((CERT_COUNT - 1))); do
            DOMAIN=$(jq -r ".letsencrypt.Certificates[$i].domain.main // \"unknown\"" "$BACKUP_FILE" 2>/dev/null)
            CERT_PEM=$(jq -r ".letsencrypt.Certificates[$i].certificate // \"\"" "$BACKUP_FILE" 2>/dev/null)
            
            if [ -n "$CERT_PEM" ] && [ "$CERT_PEM" != "null" ]; then
                EXPIRY=$(echo "$CERT_PEM" | base64 -d 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
                
                if [ -n "$EXPIRY" ]; then
                    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
                    NOW_EPOCH=$(date +%s)
                    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
                    
                    if [ $DAYS_LEFT -lt 30 ]; then
                        log_warning "Certificado $DOMAIN expira en $DAYS_LEFT días"
                        EXPIRING_SOON=$((EXPIRING_SOON + 1))
                    fi
                fi
            fi
        done
        
        if [ $EXPIRING_SOON -gt 0 ]; then
            log_warning "$EXPIRING_SOON certificado(s) expiran pronto. Considera renovarlos."
        fi
    fi
fi

log "Limpiando backups antiguos (mantener: $MAX_BACKUPS)"

BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/acme_*.json* 2>/dev/null | wc -l)

if [ $BACKUP_COUNT -gt $MAX_BACKUPS ]; then
    BACKUPS_TO_DELETE=$((BACKUP_COUNT - MAX_BACKUPS))
    log_warning "Hay $BACKUP_COUNT backups. Eliminando $BACKUPS_TO_DELETE más antiguos..."
    
    ls -1t "$BACKUP_DIR"/acme_*.json* 2>/dev/null | tail -n $BACKUPS_TO_DELETE | while read -r old_backup; do
        log "Eliminando backup antiguo: $(basename "$old_backup")"
        rm "$old_backup"
    done
    
    log_success "Backups antiguos eliminados"
fi

echo ""
log_success "Backup completado exitosamente"
echo ""
echo "📋 Resumen de backups:"
echo "────────────────────────────────────"
ls -lh "$BACKUP_DIR"/acme_*.json* 2>/dev/null | tail -5 | awk '{printf "   %s  %s\n", $5, $9}'
echo ""
echo "Total: $(ls -1 "$BACKUP_DIR"/acme_*.json* 2>/dev/null | wc -l) backup(s)"
echo ""

if [ -z "$PS1" ]; then
    log "Ejecución desde cron completada"
else
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
