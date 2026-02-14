#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/mtls"

CA_KEY="${OUT_DIR}/ca.key"
CA_CRT="${OUT_DIR}/ca.crt"

EDGE_KEY="${OUT_DIR}/edge.key"
EDGE_CSR="${OUT_DIR}/edge.csr"
EDGE_CRT="${OUT_DIR}/edge.crt"

SERVER_KEY="${OUT_DIR}/server.key"
SERVER_CSR="${OUT_DIR}/server.csr"
SERVER_CRT="${OUT_DIR}/server.crt"

OPENSSL_BIN="${OPENSSL_BIN:-openssl}"

usage() {
  cat <<EOF
Usage:
  scripts/init-mtls.sh init
  scripts/init-mtls.sh issue-server <dns_name>

What it does:
  init:
    - creates ./mtls
    - generates CA (ca.crt/ca.key)
    - generates edge client cert (edge.crt/edge.key)
  issue-server <dns_name>:
    - generates server cert for the provided DNS name (server.crt/server.key)

Notes:
  - Use a DNS name (recommended). If you use an IP in upstreams, your server cert must include IP SAN.
  - Keep private keys secret. Do not commit ./mtls/*.key.
EOF
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing dependency: $1" >&2
    exit 1
  fi
}

ensure_dirs() {
  mkdir -p "$OUT_DIR"
  if [ ! -f "${OUT_DIR}/.gitignore" ]; then
    cat > "${OUT_DIR}/.gitignore" <<'EOF'
*.key
*.csr
*.srl
*.pem
EOF
  fi
}

init_ca() {
  if [ -f "$CA_CRT" ] && [ -f "$CA_KEY" ]; then
    return
  fi

  "$OPENSSL_BIN" genrsa -out "$CA_KEY" 4096 >/dev/null 2>&1
  "$OPENSSL_BIN" req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 3650 \
    -out "$CA_CRT" -subj "/CN=combox-mtls-ca" >/dev/null 2>&1
}

issue_cert() {
  name="$1"
  key_out="$2"
  csr_out="$3"
  crt_out="$4"
  ext_out="$5"

  "$OPENSSL_BIN" genrsa -out "$key_out" 4096 >/dev/null 2>&1
  "$OPENSSL_BIN" req -new -key "$key_out" -out "$csr_out" -subj "/CN=${name}" >/dev/null 2>&1

  cat > "$ext_out" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = DNS:${name}
EOF

  "$OPENSSL_BIN" x509 -req -in "$csr_out" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$crt_out" -days 825 -sha256 -extfile "$ext_out" >/dev/null 2>&1
}

init_edge_client_cert() {
  if [ -f "$EDGE_CRT" ] && [ -f "$EDGE_KEY" ]; then
    return
  fi

  tmp_ext="${OUT_DIR}/edge.ext"
  issue_cert "combox-edge" "$EDGE_KEY" "$EDGE_CSR" "$EDGE_CRT" "$tmp_ext"
  rm -f "$tmp_ext"
}

issue_server_cert() {
  dns_name="$1"

  if [ ! -f "$CA_CRT" ] || [ ! -f "$CA_KEY" ]; then
    echo "CA not found. Run: scripts/init-mtls.sh init" >&2
    exit 1
  fi

  tmp_ext="${OUT_DIR}/server.ext"
  issue_cert "${dns_name}" "$SERVER_KEY" "$SERVER_CSR" "$SERVER_CRT" "$tmp_ext"
  rm -f "$tmp_ext"
}

main() {
  need "$OPENSSL_BIN"
  ensure_dirs

  cmd="${1:-}"
  case "$cmd" in
    init)
      init_ca
      init_edge_client_cert
      echo "mTLS initialized in ${OUT_DIR}" >&2
      ;;
    issue-server)
      if [ "${2:-}" = "" ]; then
        usage
        exit 1
      fi
      issue_server_cert "$2"
      echo "Server cert issued in ${OUT_DIR} for DNS:${2}" >&2
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
