#!/bin/sh
set -eu

CONFIG_TEMPLATE_FILE="/config/configuration.template.yml"
CONFIG_OUTPUT_FILE="/data/configuration.yml"
USERS_TEMPLATE_FILE="/config/users_database.template.yml"
USERS_OUTPUT_FILE="/data/users_database.yml"

: "${EDGE_AUTHELIA_SESSION_DOMAIN:?EDGE_AUTHELIA_SESSION_DOMAIN is required}"
: "${EDGE_AUTHELIA_TOTP_ISSUER:?EDGE_AUTHELIA_TOTP_ISSUER is required}"
: "${EDGE_AUTHELIA_SESSION_SECRET:?EDGE_AUTHELIA_SESSION_SECRET is required}"
: "${EDGE_AUTHELIA_STORAGE_ENCRYPTION_KEY:?EDGE_AUTHELIA_STORAGE_ENCRYPTION_KEY is required}"
: "${EDGE_AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET:?EDGE_AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET is required}"

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

escape_yaml() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

trim_spaces() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

to_env_key() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_'
}

get_env_value() {
  var_name="$1"
  eval "printf '%s' \"\${$var_name:-}\""
}

ADMIN_HASH="${EDGE_AUTHELIA_ADMIN_PASSWORD_HASH:-}"
ADMIN_PASSWORD="${EDGE_AUTHELIA_ADMIN_PASSWORD:-}"

if [ -z "$ADMIN_HASH" ] && [ -n "$ADMIN_PASSWORD" ]; then
  ADMIN_HASH="$(authelia crypto hash generate argon2 --password "$ADMIN_PASSWORD" | sed -n 's/^Digest: //p')"
fi

if [ -z "$ADMIN_HASH" ]; then
  ADMIN_HASH=""
fi

SESSION_DOMAIN_ESCAPED="$(escape_sed "$EDGE_AUTHELIA_SESSION_DOMAIN")"
TOTP_ISSUER_ESCAPED="$(escape_sed "$EDGE_AUTHELIA_TOTP_ISSUER")"
SESSION_SECRET_ESCAPED="$(escape_sed "$EDGE_AUTHELIA_SESSION_SECRET")"
STORAGE_KEY_ESCAPED="$(escape_sed "$EDGE_AUTHELIA_STORAGE_ENCRYPTION_KEY")"
RESET_SECRET_ESCAPED="$(escape_sed "$EDGE_AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET")"
ADMIN_USER_ESCAPED="$(escape_sed "$EDGE_AUTHELIA_ADMIN_USERNAME")"
ADMIN_DISPLAY_ESCAPED="$(escape_sed "$EDGE_AUTHELIA_ADMIN_DISPLAYNAME")"
ADMIN_EMAIL_ESCAPED="$(escape_sed "$EDGE_AUTHELIA_ADMIN_EMAIL")"
ADMIN_HASH_ESCAPED="$(escape_sed "$ADMIN_HASH")"

sed \
  -e "s|__AUTHELIA_SESSION_DOMAIN__|${SESSION_DOMAIN_ESCAPED}|g" \
  -e "s|__AUTHELIA_TOTP_ISSUER__|${TOTP_ISSUER_ESCAPED}|g" \
  -e "s|__AUTHELIA_SESSION_SECRET__|${SESSION_SECRET_ESCAPED}|g" \
  -e "s|__AUTHELIA_STORAGE_ENCRYPTION_KEY__|${STORAGE_KEY_ESCAPED}|g" \
  -e "s|__AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET__|${RESET_SECRET_ESCAPED}|g" \
  "$CONFIG_TEMPLATE_FILE" > "$CONFIG_OUTPUT_FILE"

echo "users:" > "$USERS_OUTPUT_FILE"

USERS_LIST="$(trim_spaces "${EDGE_AUTHELIA_USERS:-}")"
legacy_devops_used=0
if [ -n "$USERS_LIST" ]; then
  OLD_IFS="$IFS"
  IFS=','
  for username_raw in $USERS_LIST; do
    username="$(trim_spaces "$username_raw")"
    if [ -z "$username" ]; then
      continue
    fi

    key="$(to_env_key "$username")"
    displayname_var="EDGE_AUTHELIA_USER_${key}_DISPLAYNAME"
    email_var="EDGE_AUTHELIA_USER_${key}_EMAIL"
    hash_var="EDGE_AUTHELIA_USER_${key}_PASSWORD_HASH"
    password_var="EDGE_AUTHELIA_USER_${key}_PASSWORD"

    displayname="$(get_env_value "$displayname_var")"
    email="$(get_env_value "$email_var")"
    user_hash="$(get_env_value "$hash_var")"
    user_password="$(get_env_value "$password_var")"

    # Compatibility fallback for existing second-user env keys.
    # Applies to one non-admin user if explicit per-user vars are not set.
    if [ "$legacy_devops_used" -eq 0 ] && [ -n "${EDGE_AUTHELIA_USER_DEVOPS_EMAIL:-}" ] && [ "$username" != "${EDGE_AUTHELIA_ADMIN_USERNAME:-}" ]; then
      if [ -z "$displayname" ]; then
        displayname="$(get_env_value "EDGE_AUTHELIA_USER_DEVOPS_DISPLAYNAME")"
      fi
      if [ -z "$email" ]; then
        email="$(get_env_value "EDGE_AUTHELIA_USER_DEVOPS_EMAIL")"
      fi
      if [ -z "$user_hash" ]; then
        user_hash="$(get_env_value "EDGE_AUTHELIA_USER_DEVOPS_PASSWORD_HASH")"
      fi
      if [ -z "$user_password" ]; then
        user_password="$(get_env_value "EDGE_AUTHELIA_USER_DEVOPS_PASSWORD")"
      fi
      if [ -n "$email" ] || [ -n "$user_hash" ] || [ -n "$user_password" ]; then
        legacy_devops_used=1
      fi
    fi

    # Always prefer admin-specific credentials for the admin username.
    if [ -n "${EDGE_AUTHELIA_ADMIN_USERNAME:-}" ] && [ "$username" = "$EDGE_AUTHELIA_ADMIN_USERNAME" ]; then
      displayname="${EDGE_AUTHELIA_ADMIN_DISPLAYNAME:-$displayname}"
      email="${EDGE_AUTHELIA_ADMIN_EMAIL:-$email}"
      user_hash="${EDGE_AUTHELIA_ADMIN_PASSWORD_HASH:-$user_hash}"
      user_password="${EDGE_AUTHELIA_ADMIN_PASSWORD:-$user_password}"
    fi

    if [ -z "$displayname" ]; then
      displayname="$username"
    fi
    if [ -z "$email" ]; then
      echo "error: missing ${email_var} for user ${username}" >&2
      exit 1
    fi
    if [ -z "$user_hash" ] && [ -n "$user_password" ]; then
      user_hash="$(authelia crypto hash generate argon2 --password "$user_password" | sed -n 's/^Digest: //p')"
    fi
    if [ -z "$user_hash" ]; then
      echo "error: set ${hash_var} or ${password_var} for user ${username}" >&2
      exit 1
    fi

    username_escaped="$(escape_yaml "$username")"
    displayname_escaped="$(escape_yaml "$displayname")"
    email_escaped="$(escape_yaml "$email")"
    user_hash_escaped="$(escape_yaml "$user_hash")"

    {
      echo "  ${username_escaped}:"
      echo "    displayname: \"${displayname_escaped}\""
      echo "    password: \"${user_hash_escaped}\""
      echo "    email: \"${email_escaped}\""
      echo "    groups:"
      echo "      - admins"
    } >> "$USERS_OUTPUT_FILE"
  done
  IFS="$OLD_IFS"
else
  : "${EDGE_AUTHELIA_ADMIN_USERNAME:?EDGE_AUTHELIA_ADMIN_USERNAME is required when EDGE_AUTHELIA_USERS is empty}"
  : "${EDGE_AUTHELIA_ADMIN_DISPLAYNAME:?EDGE_AUTHELIA_ADMIN_DISPLAYNAME is required when EDGE_AUTHELIA_USERS is empty}"
  : "${EDGE_AUTHELIA_ADMIN_EMAIL:?EDGE_AUTHELIA_ADMIN_EMAIL is required when EDGE_AUTHELIA_USERS is empty}"

  if [ -z "$ADMIN_HASH" ]; then
    echo "error: set EDGE_AUTHELIA_ADMIN_PASSWORD_HASH or EDGE_AUTHELIA_ADMIN_PASSWORD in .env" >&2
    exit 1
  fi

  sed \
    -e "s|__AUTHELIA_ADMIN_USERNAME__|${ADMIN_USER_ESCAPED}|g" \
    -e "s|__AUTHELIA_ADMIN_DISPLAYNAME__|${ADMIN_DISPLAY_ESCAPED}|g" \
    -e "s|__AUTHELIA_ADMIN_EMAIL__|${ADMIN_EMAIL_ESCAPED}|g" \
    -e "s|__AUTHELIA_ADMIN_PASSWORD_HASH__|${ADMIN_HASH_ESCAPED}|g" \
    "$USERS_TEMPLATE_FILE" >> "$USERS_OUTPUT_FILE"
fi

exec authelia --config "$CONFIG_OUTPUT_FILE"
