#!/bin/bash

# ============================================
# GENERAR CERTIFICADOS DE DESARROLLO
# ============================================
# Este script genera certificados SSL autofirmados para desarrollo local

set -e

echo "🔐 Generando certificados SSL para desarrollo..."

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

# Mostrar información del certificado
echo ""
echo "✅ Certificados generados exitosamente en: $CERT_DIR"
echo ""
echo "📋 Información del certificado:"
openssl x509 -in "$CERT_DIR/localhost.crt" -noout -text | grep -A 2 "Subject:"
openssl x509 -in "$CERT_DIR/localhost.crt" -noout -text | grep -A 5 "Subject Alternative Name"

echo ""
echo "⚠️  NOTA: Los navegadores mostrarán advertencia de seguridad porque es autofirmado."
echo "   Esto es normal en desarrollo. Acepta la advertencia para continuar."
echo ""
echo "💡 OPCIONAL: Para evitar advertencias, puedes importar ca.crt como autoridad certificadora"
echo "   de confianza en tu sistema operativo/navegador."