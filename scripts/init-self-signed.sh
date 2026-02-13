#!/bin/sh
set -eu

DOMAIN="${EDGE_TLS_DOMAIN:-localhost}"
CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"
CERT_FILE="${CERT_DIR}/fullchain.pem"
KEY_FILE="${CERT_DIR}/privkey.pem"

if [ -s "${CERT_FILE}" ] && [ -s "${KEY_FILE}" ]; then
  echo "TLS cert already exists for ${DOMAIN}"
  exit 0
fi

mkdir -p "${CERT_DIR}"

openssl req -x509 -nodes -newkey rsa:2048 -days 7 \
  -keyout "${KEY_FILE}" \
  -out "${CERT_FILE}" \
  -subj "/CN=${DOMAIN}"

echo "Created temporary self-signed certificate for ${DOMAIN}"
