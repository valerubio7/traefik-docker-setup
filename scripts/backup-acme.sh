#!/bin/bash

# Backup script para Let's Encrypt acme.json
# Uso: ./scripts/backup-acme.sh

set -e

ACME_FILE="./certs/prod/acme.json"
BACKUP_DIR="./certs/prod/backups"
MAX_BACKUPS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Validación inicial
if [ ! -f "$ACME_FILE" ]; then
    echo -e "${RED}❌ Archivo no encontrado: $ACME_FILE${NC}"
    exit 1
fi

# Crear directorio de backups
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# Crear backup
BACKUP_FILE="$BACKUP_DIR/acme_${TIMESTAMP}.json"
echo -e "${YELLOW}📦 Creando backup...${NC}"

if cp "$ACME_FILE" "$BACKUP_FILE"; then
    chmod 600 "$BACKUP_FILE"
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "${GREEN}✅ Backup creado: $SIZE${NC}"
else
    echo -e "${RED}❌ Error al crear backup${NC}"
    exit 1
fi

# Limpiar backups antiguos
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/acme_*.json 2>/dev/null | wc -l)

if [ $BACKUP_COUNT -gt $MAX_BACKUPS ]; then
    BACKUPS_TO_DELETE=$((BACKUP_COUNT - MAX_BACKUPS))
    echo -e "${YELLOW}🗑️  Eliminando $BACKUPS_TO_DELETE backup(s) antiguo(s)...${NC}"
    
    ls -1t "$BACKUP_DIR"/acme_*.json 2>/dev/null | tail -n $BACKUPS_TO_DELETE | xargs rm -f
fi

# Resumen
echo ""
echo -e "${GREEN}✅ Backup completado${NC}"
echo ""
echo "📋 Últimos 5 backups:"
ls -lh "$BACKUP_DIR"/acme_*.json 2>/dev/null | tail -5 | awk '{printf "   %s  %s\n", $5, $9}'
echo ""
echo "Total: $(ls -1 "$BACKUP_DIR"/acme_*.json 2>/dev/null | wc -l) backup(s)"
echo ""
echo "📝 Para restaurar:"
echo "   cp $BACKUP_DIR/acme_YYYYMMDD_HHMMSS.json ./certs/prod/acme.json"
echo "   chmod 600 ./certs/prod/acme.json"
echo "   ./scripts/stop.sh && ./scripts/start-prod.sh"
echo ""
