#!/bin/bash
# generate-selfsigned-cert.sh - Generate self-signed certificate for stud service
# Usage: ./generate-selfsigned-cert.sh [domain] [output_dir] [days_valid] [key_size]

set -e

# Show help if requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat << EOF
generate-selfsigned-cert.sh - Generate self-signed certificate for stud service

Usage: $0 [domain] [output_dir] [days_valid] [key_size]

Arguments:
  domain      Domain name for certificate (default: localhost)
  output_dir  Directory to save certificates (default: ./certs)
  days_valid  Number of days certificate is valid (default: 365)
  key_size    RSA key size in bits (default: 2048)

Examples:
  $0                          # Generate for localhost in ./certs
  $0 example.com              # Generate for example.com
  $0 example.com /etc/ssl     # Save to /etc/ssl
  $0 example.com ./certs 730 4096  # 2-year cert with 4096-bit key

The script generates:
  - Private key (.key)
  - Certificate (.crt) 
  - Combined PEM file (.pem) for stud
  - CSR (.csr)
  - DH parameters (.pem, optional)
  - Example stud configuration

EOF
    exit 0
fi

# Default values
DOMAIN="${1:-localhost}"
OUTPUT_DIR="${2:-./certs}"
DAYS_VALID="${3:-365}"
KEY_SIZE="${4:-2048}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Generating self-signed certificate for stud service${NC}"
echo "Domain: $DOMAIN"
echo "Output directory: $OUTPUT_DIR"
echo "Valid for: $DAYS_VALID days"
echo "Key size: $KEY_SIZE bits"
echo

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate private key
echo -e "${YELLOW}Generating private key...${NC}"
openssl genrsa -out "$OUTPUT_DIR/$DOMAIN.key" "$KEY_SIZE"

# Generate CSR configuration
cat > "$OUTPUT_DIR/openssl.cnf" <<EOF
[req]
default_bits = $KEY_SIZE
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = US
ST = California
L = San Francisco
O = Example Company
OU = IT Department
CN = $DOMAIN

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = *.$DOMAIN
DNS.3 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Generate CSR
echo -e "${YELLOW}Generating Certificate Signing Request...${NC}"
openssl req -new -key "$OUTPUT_DIR/$DOMAIN.key" -out "$OUTPUT_DIR/$DOMAIN.csr" -config "$OUTPUT_DIR/openssl.cnf"

# Generate self-signed certificate
echo -e "${YELLOW}Generating self-signed certificate...${NC}"
openssl x509 -req -days "$DAYS_VALID" -in "$OUTPUT_DIR/$DOMAIN.csr" -signkey "$OUTPUT_DIR/$DOMAIN.key" -out "$OUTPUT_DIR/$DOMAIN.crt" \
  -extfile "$OUTPUT_DIR/openssl.cnf" -extensions req_ext

# Create combined PEM file (cert + key) for stud
echo -e "${YELLOW}Creating combined PEM file for stud...${NC}"
cat "$OUTPUT_DIR/$DOMAIN.crt" "$OUTPUT_DIR/$DOMAIN.key" > "$OUTPUT_DIR/$DOMAIN.pem"

# Set proper permissions
chmod 600 "$OUTPUT_DIR/$DOMAIN.key" "$OUTPUT_DIR/$DOMAIN.pem"
chmod 644 "$OUTPUT_DIR/$DOMAIN.crt" "$OUTPUT_DIR/$DOMAIN.csr"

# Clean up temporary config
rm -f "$OUTPUT_DIR/openssl.cnf"

# Generate DH parameters (optional, for better security)
echo -e "${YELLOW}Generating DH parameters (this may take a while)...${NC}"
openssl dhparam -out "$OUTPUT_DIR/dhparam.pem" 2048 2>/dev/null || echo "DH param generation skipped or failed"

echo
echo -e "${GREEN}Certificate generation complete!${NC}"
echo
echo -e "${YELLOW}Generated files:${NC}"
echo "  Private key:          $OUTPUT_DIR/$DOMAIN.key"
echo "  Certificate:          $OUTPUT_DIR/$DOMAIN.crt"
echo "  Combined PEM:         $OUTPUT_DIR/$DOMAIN.pem (for stud)"
echo "  CSR:                  $OUTPUT_DIR/$DOMAIN.csr"
echo "  DH parameters:        $OUTPUT_DIR/dhparam.pem (optional)"
echo
echo -e "${YELLOW}To use with stud:${NC}"
echo "  Update your stud configuration:"
echo "    CERT_FILE=\"$OUTPUT_DIR/$DOMAIN.pem\""
echo
echo -e "${YELLOW}To view certificate details:${NC}"
echo "  openssl x509 -in $OUTPUT_DIR/$DOMAIN.crt -text -noout"
echo
echo -e "${YELLOW}To test with openssl:${NC}"
echo "  openssl s_client -connect localhost:8443 -servername $DOMAIN"
echo
echo -e "${RED}Note: This is a self-signed certificate for testing only.${NC}"
echo -e "${RED}For production use, obtain a certificate from a trusted CA.${NC}"

# Create a simple stud configuration example
cat > "$OUTPUT_DIR/stud-example.conf" <<EOF
# Example stud configuration using self-signed certificate
FRONTEND="*:8443"
BACKEND="127.0.0.1:8080"
CERT_FILE="$OUTPUT_DIR/$DOMAIN.pem"
TLS_VERSION="tls12"
CIPHER_SUITE="HIGH:!aNULL:!MD5"
WORKERS=2
SYSLOG=0
QUIET=0
EOF

echo -e "${GREEN}Example configuration saved to: $OUTPUT_DIR/stud-example.conf${NC}"