#!/bin/sh
set -eu

DOMAIN="${EDGE_TLS_DOMAIN:-localhost}"
CERT_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY_FILE="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

watch_cert_changes() {
  last=""

  while :; do
    if [ -s "${CERT_FILE}" ] && [ -s "${KEY_FILE}" ]; then
      current="$(stat -c %Y "${CERT_FILE}" 2>/dev/null || echo 0):$(stat -c %Y "${KEY_FILE}" 2>/dev/null || echo 0)"

      if [ -n "${last}" ] && [ "${current}" != "${last}" ]; then
        nginx -s reload || true
      fi

      last="${current}"
    fi

    sleep 60
  done
}

watch_cert_changes &

exec /docker-entrypoint.sh nginx -g 'daemon off;'
