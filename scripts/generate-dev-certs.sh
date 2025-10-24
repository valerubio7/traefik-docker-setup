#!/bin/bash

# ============================================
# GENERAR CERTIFICADOS DE DESARROLLO
# ============================================
# Este script genera certificados SSL autofirmados para desarrollo local
# 
# MEJORAS:
# • Verifica si certificados válidos ya existen
# • Muestra fecha de expiración y días restantes
# • Solo regenera si están próximos a expirar (< 30 días)
# • Previene sobrescritura innecesaria cuando contenedores están corriendo
# • Tiene flag --force para regenerar aunque sean válidos

set -e

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar información
info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Directorio de certificados
CERT_DIR="./certs/dev"
mkdir -p "$CERT_DIR"

# Configuración
COUNTRY="AR"
STATE="Mendoza"
CITY="San Rafael"
ORG="Development"
CN="localhost"
DAYS=365
DAYS_WARNING=30  # Regenerar si quedan < 30 días

# Flag para forzar regeneración
FORCE=false
if [ "${1:-}" = "--force" ]; then
    FORCE=true
    echo "🔄 Modo FORCE: Regenerando certificados aunque sean válidos..."
fi

echo "🔐 Verificando certificados SSL para desarrollo..."
echo ""

# ==========================================
# VERIFICAR CERTIFICADOS EXISTENTES
# ==========================================
SHOULD_REGENERATE=false
REGEN_REASON=""

if [ -f "$CERT_DIR/localhost.crt" ] && [ -f "$CERT_DIR/localhost.key" ]; then
    info "Certificados encontrados"
    
    # Obtener fecha de expiración
    EXPIRY_DATE=$(openssl x509 -in "$CERT_DIR/localhost.crt" -noout -dates | grep notAfter | cut -d= -f2)
    EXPIRY_UNIX=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || date -j -f "%b %d %T %Z %Y" "$EXPIRY_DATE" +%s)
    NOW_UNIX=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_UNIX - $NOW_UNIX) / 86400 ))
    
    info "Fecha de expiración: $EXPIRY_DATE"
    
    if [ $DAYS_LEFT -lt 0 ]; then
        error "Certificado EXPIRADO hace $((-$DAYS_LEFT)) días"
        SHOULD_REGENERATE=true
        REGEN_REASON="certificado expirado"
    elif [ $DAYS_LEFT -lt $DAYS_WARNING ]; then
        warning "Certificado expira en $DAYS_LEFT días (< $DAYS_WARNING de umbral)"
        SHOULD_REGENERATE=true
        REGEN_REASON="próximo a expirar"
    else
        success "Certificado válido por $DAYS_LEFT días más"
        
        # Verificar SANs
        SANS=$(openssl x509 -in "$CERT_DIR/localhost.crt" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" || echo "")
        if echo "$SANS" | grep -q "localhost" && echo "$SANS" | grep -q "127.0.0.1"; then
            success "Certificado tiene SANs correctos (localhost, 127.0.0.1)"
        else
            warning "Certificado puede carecer de algunos SANs, considerando regeneración"
            SHOULD_REGENERATE=true
            REGEN_REASON="SANs incompletos"
        fi
    fi
    
    echo ""
else
    info "Certificados NO encontrados"
    SHOULD_REGENERATE=true
    REGEN_REASON="certificados no existen"
fi

echo ""

# ==========================================
# DECIDIR SI REGENERAR
# ==========================================
if [ "$FORCE" = true ]; then
    warning "Flag --force activado, regenerando aunque certificado sea válido"
    SHOULD_REGENERATE=true
    REGEN_REASON="regeneración forzada"
elif [ "$SHOULD_REGENERATE" = false ]; then
    success "No es necesario regenerar certificados"
    echo ""
    echo "💡 Para forzar regeneración: $0 --force"
    exit 0
fi

echo "Razón de regeneración: $REGEN_REASON"
echo ""

# Hacer backup si existen
if [ -f "$CERT_DIR/localhost.crt" ]; then
    BACKUP_DIR="$CERT_DIR/backups"
    mkdir -p "$BACKUP_DIR"
    BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
    
    info "Creando backup de certificados antiguos..."
    cp "$CERT_DIR/localhost.crt" "$BACKUP_DIR/localhost.crt.$BACKUP_DATE"
    cp "$CERT_DIR/localhost.key" "$BACKUP_DIR/localhost.key.$BACKUP_DATE"
    if [ -f "$CERT_DIR/ca.crt" ]; then
        cp "$CERT_DIR/ca.crt" "$BACKUP_DIR/ca.crt.$BACKUP_DATE"
    fi
    success "Backup creado en: $BACKUP_DIR/"
    echo ""
fi

# ==========================================
# REGENERAR CERTIFICADOS
# ==========================================
info "Generando nuevos certificados SSL..."
echo ""

# Generar clave privada
echo "📝 Generando clave privada..."
openssl genrsa -out "$CERT_DIR/localhost.key" 2048

# Crear archivo de configuración para SANs (Subject Alternative Names)
cat > "$CERT_DIR/openssl.cnf" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=$COUNTRY
ST=$STATE
L=$CITY
O=$ORG
CN=$CN

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
DNS.3 = traefik.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Generar certificado autofirmado
echo "📜 Generando certificado autofirmado..."
openssl req -new -x509 \
    -key "$CERT_DIR/localhost.key" \
    -out "$CERT_DIR/localhost.crt" \
    -days $DAYS \
    -config "$CERT_DIR/openssl.cnf" \
    -extensions v3_req

# Generar CA certificate (opcional, para mayor compatibilidad)
echo "🏛️  Generando CA certificate..."
openssl req -new -x509 \
    -key "$CERT_DIR/localhost.key" \
    -out "$CERT_DIR/ca.crt" \
    -days $DAYS \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/CN=Development CA"

# Limpiar archivo temporal
rm "$CERT_DIR/openssl.cnf"

# ==========================================
# INFORMACIÓN DE CERTIFICADOS NUEVOS
# ==========================================
echo ""
success "Certificados generados exitosamente"
echo ""

# Obtener información del certificado nuevo
NEW_EXPIRY_DATE=$(openssl x509 -in "$CERT_DIR/localhost.crt" -noout -dates | grep notAfter | cut -d= -f2)
NEW_EXPIRY_UNIX=$(date -d "$NEW_EXPIRY_DATE" +%s 2>/dev/null || date -j -f "%b %d %T %Z %Y" "$NEW_EXPIRY_DATE" +%s)
NEW_DAYS_LEFT=$(( ($NEW_EXPIRY_UNIX - $(date +%s)) / 86400 ))

info "Ubicación: $CERT_DIR"
info "Expiración: $NEW_EXPIRY_DATE"
info "Válido por: $NEW_DAYS_LEFT días"
echo ""

info "Información del certificado:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
openssl x509 -in "$CERT_DIR/localhost.crt" -noout -text | grep -E "Subject:|Issuer:|Not Before|Not After" | sed 's/^/  /'
echo ""
openssl x509 -in "$CERT_DIR/localhost.crt" -noout -text | grep -A1 "Subject Alternative Name" | sed 's/^/  /'
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "⚠️  NOTA: Los navegadores mostrarán advertencia de seguridad porque es autofirmado."
echo "   Esto es NORMAL en desarrollo. Acepta la advertencia para continuar."
echo ""

echo "💡 OPCIONES:"
echo "   • Para evitar advertencias: importa $CERT_DIR/ca.crt en tu navegador"
echo "   • Para regenerar: ejecuta: $0 --force"
echo "   • Para ver certificados backups: ls -la $CERT_DIR/backups/"
echo ""

success "¡Listo para usarse en desarrollo!"