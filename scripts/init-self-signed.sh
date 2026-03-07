#!/bin/sh
set -eu

DOMAIN="${EDGE_TLS_DOMAIN:-localhost}"
APP_DOMAIN="${EDGE_APP_DOMAIN:-app.localhost}"
API_DOMAIN="${EDGE_API_DOMAIN:-api.localhost}"
STATUS_DOMAIN="${EDGE_STATUS_DOMAIN:-status.localhost}"
CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"
CERT_FILE="${CERT_DIR}/fullchain.pem"
KEY_FILE="${CERT_DIR}/privkey.pem"
OPENSSL_CNF="$(mktemp)"

cleanup() {
  rm -f "${OPENSSL_CNF}"
}
trap cleanup EXIT

if [ -s "${CERT_FILE}" ] && [ -s "${KEY_FILE}" ]; then
  echo "TLS cert already exists for ${DOMAIN}"
  exit 0
fi

mkdir -p "${CERT_DIR}"

cat >"${OPENSSL_CNF}" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
x509_extensions = v3_req
distinguished_name = dn

[dn]
CN = ${DOMAIN}

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = ${APP_DOMAIN}
DNS.3 = ${API_DOMAIN}
DNS.4 = ${STATUS_DOMAIN}
EOF

openssl req -x509 -nodes -newkey rsa:2048 -days 7 -config "${OPENSSL_CNF}" \
  -keyout "${KEY_FILE}" \
  -out "${CERT_FILE}"

echo "Created temporary self-signed certificate for ${DOMAIN}, ${APP_DOMAIN}, ${API_DOMAIN}, ${STATUS_DOMAIN}"
