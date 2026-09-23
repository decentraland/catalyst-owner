#!/bin/bash

certificateMatchesHost () {
  local host="$1" directory="$2"
  [ -f "$directory/fullchain.pem" ] && [ -f "$directory/privkey.pem" ] || return 1
  openssl x509 -in "$directory/fullchain.pem" -noout -checkhost "$host" >/dev/null 2>&1
}

# Certbot's certificate name can differ from the hostname (for example, -0001).
# Prefer the unsuffixed name, then a matching numbered lineage. Do not select a
# directory just because it exists: interrupted issuance can leave it empty.
certificateNameForHost () {
  local host="$1" live_dir="$2" directory name suffix
  for directory in "$live_dir/$host" "$live_dir/$host"-*; do
    name=${directory##*/}
    if [ "$name" != "$host" ]; then
      suffix=${name#"$host"-}
      case "$suffix" in ''|*[!0-9]*) continue ;; esac
    fi
    if certificateMatchesHost "$host" "$directory"; then
      printf '%s\n' "$name"
      return
    fi
  done
  printf '%s\n' "$host"
}

renderHttpsConfig () {
  local host="$1" certificate_path="$2" template="$3" destination="$4"
  sed -e "s/\$katalyst_host/$host/g" \
      -e "s|\$certificate_path|$certificate_path|g" "$template" > "$destination"
}

# ECDSA P-256 is supported by nginx/OpenSSL; it must not be treated as RSA-256.
certificateNeedsRenewal () {
  local certificate="$1" description key_length
  openssl x509 -in "$certificate" -noout -checkend 0 >/dev/null 2>&1 || return 0
  description=$(openssl x509 -in "$certificate" -noout -text 2>/dev/null) || return 0
  if [[ "$description" == *"Public Key Algorithm: rsaEncryption"* ]]; then
    key_length=$(printf '%s\n' "$description" | sed -n 's/.*Public-Key: (\([0-9]*\) bit).*/\1/p')
    if [ -n "$key_length" ] && [ "$key_length" -lt 2048 ]; then
      return 0
    fi
  fi
  return 1
}
