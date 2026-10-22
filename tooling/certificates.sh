#!/bin/bash

renderHttpsConfig () {
  local host="$1" certificate_path="$2" template="$3" destination="$4"
  sed -e "s/\$katalyst_host/$host/g" \
      -e "s|\$certificate_path|$certificate_path|g" "$template" > "$destination"
}

# POSIX sh script that selects the certificate lineage for $DOMAIN and prints
# "<name> <state>". init.sh runs it inside the certbot container, because
# certbot keeps archive/ readable by root only; LE_DIR lets the tests point it
# at fixtures instead of /etc/letsencrypt.
#
# Certbot's certificate name can differ from the hostname (for example, -0001).
# A lineage is only considered when certbot manages it (it has a renewal
# configuration) and its certificate covers the host: interrupted issuance can
# leave a directory empty, and a certificate certbot cannot renew is no better
# than none. Among those, the first valid one wins, the unsuffixed name before
# the numbered ones; if none is valid, the first one is picked to be renewed.
#
# States:
#   missing    no usable lineage; the name is the host, for a first issuance
#   staging    issued by the Let's Encrypt staging environment, so not trusted
#   weak-key   RSA key under 2048 bits, which OpenSSL 3 rejects (ECDSA P-256 is
#              fine and must not be mistaken for RSA-256)
#   expiring   expires within $RENEW_DAYS days
#   recent     valid and issued less than a day ago
#   valid      valid
cert_state_script='
  le="${LE_DIR:-/etc/letsencrypt}"

  state () {
    cert="$le/live/$1/fullchain.pem"
    if openssl x509 -in "$cert" -noout -issuer | grep -qi staging; then echo staging; return; fi
    text="$(openssl x509 -in "$cert" -noout -text)"
    if echo "$text" | grep -q "Public Key Algorithm: rsaEncryption"; then
      bits="$(echo "$text" | sed -n "s/.*Public-Key: (\([0-9]*\) bit).*/\1/p")"
      if [ -n "$bits" ] && [ "$bits" -lt 2048 ]; then echo weak-key; return; fi
    fi
    if ! openssl x509 -in "$cert" -noout -checkend $((RENEW_DAYS * 86400)) > /dev/null; then echo expiring; return; fi
    if [ -n "$(find "$(readlink -f "$cert")" -mmin -1440)" ]; then echo recent; return; fi
    echo valid
  }

  first=""
  for dir in "$le/live/$DOMAIN" "$le/live/$DOMAIN"-*; do
    candidate="${dir##*/}"
    if [ "$candidate" != "$DOMAIN" ]; then
      case "${candidate#"$DOMAIN"-}" in ""|*[!0-9]*) continue ;; esac
    fi
    [ -f "$dir/fullchain.pem" ] && [ -f "$dir/privkey.pem" ] && [ -f "$le/renewal/$candidate.conf" ] || continue
    # Match on the message: older OpenSSL releases (e.g. 3.0) exit 0 on a mismatch too.
    openssl x509 -in "$dir/fullchain.pem" -noout -checkhost "$DOMAIN" 2> /dev/null | grep -q " does match " || continue
    s="$(state "$candidate")"
    case "$s" in valid|recent) echo "$candidate $s"; exit 0 ;; esac
    [ -n "$first" ] || first="$candidate $s"
  done
  echo "${first:-$DOMAIN missing}"
'
