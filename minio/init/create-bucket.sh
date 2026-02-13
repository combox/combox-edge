#!/bin/sh
set -eu

: "${MINIO_API_INTERNAL:?MINIO_API_INTERNAL is required}"
: "${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"
: "${MINIO_BUCKET:?MINIO_BUCKET is required}"

mc alias set local "${MINIO_API_INTERNAL}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"
mc mb --ignore-existing "local/${MINIO_BUCKET}"
mc anonymous set none "local/${MINIO_BUCKET}"