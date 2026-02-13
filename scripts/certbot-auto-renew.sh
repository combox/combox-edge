#!/bin/sh
set -eu

DOMAIN="${EDGE_TLS_DOMAIN:?EDGE_TLS_DOMAIN is required}"
EMAIL="${CERTBOT_EMAIL:?CERTBOT_EMAIL is required}"
WEBROOT="/var/www/certbot"
STAGING="${CERTBOT_STAGING:-1}"

EXTRA_FLAGS=""
if [ "${STAGING}" = "1" ]; then
  EXTRA_FLAGS="--staging"
fi

while :; do
  certbot certonly --webroot -w "${WEBROOT}" \
    --non-interactive --agree-tos --email "${EMAIL}" \
    -d "${DOMAIN}" --keep-until-expiring ${EXTRA_FLAGS} || true

  certbot renew --webroot -w "${WEBROOT}" --quiet ${EXTRA_FLAGS} || true

  sleep 12h
done
