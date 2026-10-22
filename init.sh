#!/bin/bash
#
# Usage: ./init.sh [--force]
#
#   --force   Bring every container down and up again, instead of only
#             recreating the ones whose image or configuration changed.
#
export rsa_key_size=4096
export data_path="local/certbot"
# Certbot release whose TLS config we download. Pinned (not "main") so a given
# repo revision always fetches identical files; keep in sync with the certbot
# container image tag in docker-compose.yml.
export certbot_ref="v5.8.0"
export nginx_server_file="local/nginx/conf.d/00-katalyst.conf"
export nginx_server_template_http="local/nginx/conf.d/katalyst-http.conf.template"
export nginx_server_template_https="local/nginx/conf.d/katalyst-https.conf.template"
source "$(dirname "${BASH_SOURCE[0]}")/tooling/certificates.sh" || exit 1

# Renew the certificate from here when it expires within this many days. The
# certbot service renews on its own inside the same window, so this only kicks
# in when that did not happen.
export cert_renew_days=30
# After a failed Let's Encrypt request, do not try again for this long. Failed
# validations are rate limited per hostname (5 per hour) and bootstrap.sh
# retries this script every 30 seconds, so without a pause a broken DNS or
# firewall setup would quickly lock the domain out.
export cert_retry_minutes=60
export cert_failure_file=".cert-request-failed"

# Services that read configuration from bind-mounted files, as "service:path".
# Compose only recreates a container when its definition or image changes, so
# these are restarted when the files under their path change. nginx is not
# listed: it is reloaded gracefully on every run, and restarted only when its
# nginx.conf goes stale (see nginxConfStale).
export config_services="postgres:local/postgres postgres-exporter:local/postgres-exporter"
export config_checksums_file=".config-checksums"
export lock_file=".init.lock"
export lock_dir=".init.lock.d"

# ensure we have wide path options to run in different environments
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"

####
# Functions
#####

printMessage () {
    Type=$1
    case ${Type} in
      ok) echo -e "[\e[92m OK \e[39m]" ;;
      failed) echo -e "[\e[91m FAILED \e[39m]" ;;
      *) echo "";;
    esac
}

printWarning () {
  echo -e "\033[33m WARNING: $1 \033[39m"
}

compose () {
  docker-compose -f docker-compose.yml -f "platform.$(uname -s).yml" "$@"
}

# Runs certbot in a one-off container.
certbotRun () {
  compose run --rm --no-deps -T --entrypoint certbot certbot "$@"
}

# Runs the shell script $1 in a one-off certbot container, with DOMAIN and
# RENEW_DAYS set. Certificates are inspected there because certbot keeps them
# readable by root only.
certbotShell () {
  compose run --rm --no-deps -T \
    -e DOMAIN="$nginx_url" -e RENEW_DAYS="$cert_renew_days" \
    --entrypoint sh certbot -c "$1"
}

# Prints "<lineage name> <state>" for $nginx_url; see cert_state_script.
certState () {
  certbotShell "$cert_state_script" | tail -n 1
}

# Creates a self-signed certificate so nginx can start before the first
# issuance. It lives outside certbot's live/archive/renewal directories, so it
# can never overwrite or block a certificate lineage.
createBootstrapCert () {
  echo "## Creating bootstrap certificate for $nginx_url so nginx can start..."
  certbotShell '
    dir="/etc/letsencrypt/bootstrap/$DOMAIN"
    mkdir -p "$dir" &&
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
      -keyout "$dir/privkey.pem" -out "$dir/fullchain.pem" -subj "/CN=localhost"
  '
}

# certbot refuses to create a lineage over live/ or archive/ directories it does
# not manage, such as a dummy certificate left by older versions of this
# script. Move them aside (never delete them) before a first issuance.
moveStrayCertFiles () {
  certbotShell '
    [ -f "/etc/letsencrypt/renewal/$DOMAIN.conf" ] && exit 0
    stale="/etc/letsencrypt/stale/$DOMAIN-$(date +%Y%m%d%H%M%S)"
    for p in live archive; do
      if [ -e "/etc/letsencrypt/$p/$DOMAIN" ]; then
        mkdir -p "$stale" && mv "/etc/letsencrypt/$p/$DOMAIN" "$stale/$p" || exit 1
      fi
    done
  '
}

# Succeeds unless a Let's Encrypt request failed less than $cert_retry_minutes ago.
canRequestCert () {
  if [ -n "$(find "$cert_failure_file" -mmin "-${cert_retry_minutes}" 2>/dev/null)" ]; then
    printWarning "A Let's Encrypt request failed less than ${cert_retry_minutes} minutes ago, not trying again yet. Delete ${cert_failure_file} to retry now."
    return 1
  fi
  return 0
}

# Waits for nginx to answer the ACME challenge path over plain HTTP, which is
# what Let's Encrypt will hit. Only warns on timeout: the host may be unable to
# reach its own public address even when Let's Encrypt can.
waitForAcmeChallenge () {
  local url="http://${nginx_url}/.well-known/acme-challenge/init-check" code
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    code=$(curl -s -o /dev/null --max-time 5 --write-out "%{http_code}" "$url")
    if [ "$code" != "000" ] && [ "$code" -lt 500 ]; then
      return 0
    fi
    echo ">> Waiting for ${url} (status: ${code})..."
    sleep 3
  done
  printWarning "${url} did not answer, requesting the certificate anyway"
}

# The certbot service runs `certbot renew` when it starts, and certbot refuses to
# run twice at once. Wait for that run to finish, so a freshly (re)created
# service does not make our request fail.
waitForCertbotService () {
  compose exec -T certbot sh -c '
    for _ in $(seq 60); do
      pgrep -x certbot > /dev/null || exit 0
      sleep 1
    done
  ' > /dev/null 2>&1
}

# Requests a certificate for $nginx_url under the lineage name $1. An existing
# lineage is renewed in place: certbot only replaces its files once issuance
# succeeded, and keeps its renewal settings, so a failure leaves the current
# certificate untouched. nginx keeps serving the certificate it already loaded
# until it is reloaded.
issueCert () {
  local name="$1"
  canRequestCert || return 1
  waitForAcmeChallenge
  waitForCertbotService

  local args=(certonly --webroot -w /var/www/certbot -d "$nginx_url" --email "$EMAIL"
    --rsa-key-size "$rsa_key_size" --agree-tos --no-eff-email --non-interactive)

  # The dry run validates against the staging environment, so a broken setup
  # fails there without spending the production rate limits. It uses a name of
  # its own so certbot does not skip validation for a lineage that is not due;
  # dry runs never save a lineage.
  echo "## Validating the Let's Encrypt challenge for $nginx_url (dry run)..."
  if certbotRun "${args[@]}" --cert-name "${name}-dry-run" --dry-run; then
    echo "## Requesting Let's Encrypt certificate ${name} for $nginx_url..."
    if certbotRun "${args[@]}" --cert-name "$name" --force-renewal; then
      rm -f "$cert_failure_file"
      return 0
    fi
  fi

  touch "$cert_failure_file"
  return 1
}

renewCert () {
  local name="$1"
  canRequestCert || return 1
  waitForAcmeChallenge
  waitForCertbotService
  echo "## Renewing Let's Encrypt certificate ${name} for $nginx_url..."
  if certbotRun renew --cert-name "$name" --force-renewal --non-interactive; then
    rm -f "$cert_failure_file"
    return 0
  fi
  touch "$cert_failure_file"
  return 1
}

# Download $1 to $2, atomically. Streams to a temp file in the target directory
# and only moves it into place on success, so neither an HTTP error (--fail nets
# the error body) nor an interrupted transfer can leave a partial/unparseable
# file at the final path (which would make nginx fail to start). $3 is a label
# for error messages.
downloadTlsFile () {
  local url="$1" target="$2" name="$3" tmp
  tmp="$(mktemp "${target}.XXXXXX")" || {
    echo -n "Failed to create temp file for $name... "
    printMessage failed
    return 1
  }
  if curl -fsS "$url" -o "$tmp"; then
    # mktemp creates the file 0600; these are public TLS config files, so restore
    # the world-readable perms the previous `curl -o` produced before moving.
    chmod 0644 "$tmp"
    mv "$tmp" "$target"
  else
    rm -f "$tmp"
    echo -n "Failed to download $name... "
    printMessage failed
    return 1
  fi
}

# Downloads certbot's recommended TLS parameters, which the nginx HTTPS config
# includes, unless the ones for $certbot_ref are already in place.
ensureTlsConfig () {
  local options="$data_path/conf/options-ssl-nginx.conf"
  local dhparams="$data_path/conf/ssl-dhparams.pem"
  local stamp="$data_path/conf/.tls-config-ref"

  if [ -f "$options" ] && [ -f "$dhparams" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$certbot_ref" ]; then
    return 0
  fi

  echo "## Downloading recommended TLS parameters (certbot ${certbot_ref})..."
  mkdir -p "$data_path/conf" &&
  downloadTlsFile \
    "https://raw.githubusercontent.com/certbot/certbot/${certbot_ref}/certbot/src/certbot/_internal/plugins/nginx/tls_configs/options-ssl-nginx.conf" \
    "$options" "options-ssl-nginx.conf" &&
  downloadTlsFile \
    "https://raw.githubusercontent.com/certbot/certbot/${certbot_ref}/certbot/src/certbot/ssl-dhparams.pem" \
    "$dhparams" "ssl-dhparams.pem" &&
  echo "$certbot_ref" > "$stamp"
}

# Runs `nginx -t` with the nginx command given in "$@": an exec into the running
# container, or a one-off container. The upstreams are resolved by host name
# when the config loads, so the test fails while a backend container is still
# starting or restarting; give them a moment before treating it as a broken
# config. Prints nginx's output if it keeps failing.
nginxConfigTest () {
  local attempt output
  for attempt in 1 2 3 4 5 6; do
    output="$("$@" -t 2>&1)" && return 0
    test ${attempt} -lt 6 && sleep 5
  done
  echo "$output"
  return 1
}

# nginx.conf is bind-mounted as a single file. `git pull` replaces it with a new
# file the running container never sees, and a reload re-reads the stale copy,
# so it is stale whenever the container's copy differs from the repository's.
nginxConfStale () {
  [ "$(compose exec -T nginx cat /etc/nginx/nginx.conf 2> /dev/null | checksum)" != "$(checksum < local/nginx/nginx.conf)" ]
}

checksum () {
  if command -v sha256sum > /dev/null; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1
}

# Checksum of the names and contents of every file under $1.
configChecksum () {
  find "$1" -type f | LC_ALL=C sort | while IFS= read -r f; do
    echo "$f"
    cat "$f"
  done | checksum
}

storedConfigChecksum () {
  awk -v s="$1" '$1 == s { print $2 }' "$config_checksums_file" 2>/dev/null
}

##
# Main program
##
FORCE=0
for arg in "$@"; do
  case "$arg" in
    -f|--force) FORCE=1 ;;
    -h|--help) sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)" >&2; exit 1 ;;
  esac
done

if [ -t 1 ]; then
  clear
fi
echo -n "## Loading env variables... "

if ! [ -f ".env" ]; then
  echo -n "Error: .env does not exist" >&2
  printMessage failed
  exit 1
else
  source ".env"
  printMessage ok
fi

if ! [ -f ".env-advanced" ]; then
  echo -n "Error: .env-advanced does not exist" >&2
  printMessage failed
  exit 1
else
  source ".env-advanced"
  printMessage ok
fi

echo -n "## Checking if email is configured... "
if [ -n "${EMAIL}" ]; then
  printMessage ok
else
    echo -n "Failed to check the email."
    printMessage failed
    exit 1
fi

echo -n "## Checking if storage is configured... "
if [ -n "${CONTENT_SERVER_STORAGE}" ] && [ -d "${CONTENT_SERVER_STORAGE}" ]; then
    printMessage ok
else
    echo -n "Failed to check the storage."
    printMessage failed
    exit 1
fi

echo -n "## Checking if catalyst url is configured... "
if [ -n "${CATALYST_URL}" ]; then
    printMessage ok
else
    echo -n "Failed to check the catalyst url."
    printMessage failed
    exit 1
fi

echo -n "## Checking if realm name is configured... "
if [ -n "${REALM_NAME}" ]; then
    printMessage ok
else
    printMessage failed
    printWarning "REALM_NAME variable is undefined"
fi

# Define defaults
export DOCKER_TAG=${DOCKER_TAG:-latest}
export LAMB2_DOCKER_TAG=${LAMB2_DOCKER_TAG:-latest}
export CATALYST_STATS_DOCKER_TAG=${CATALYST_STATS_DOCKER_TAG:-latest}
export ARCHIPELAGO_DOCKER_TAG=${ARCHIPELAGO_DOCKER_TAG:-latest}
export ARCHIPELAGO_CORE_DOCKER_TAG=${ARCHIPELAGO_CORE_DOCKER_TAG:-0.2.3}
REGENERATE=${REGENERATE:-0}
SLEEP_TIME=${SLEEP_TIME:-5}
MAINTENANCE_MODE=${MAINTENANCE_MODE:-0}

if [ "$DOCKER_TAG" != "latest" ]; then
    printWarning "You are not running latest image of Catalyst's Content and Catalyst's Lambdas Nodes."
fi

if [ "$LAMB2_DOCKER_TAG" != "latest" ]; then
    printWarning "You are not running latest image of Lamb2 Node."
fi

if [ "$ARCHIPELAGO_DOCKER_TAG" != "latest" ]; then
    printWarning "You are not running latest image of Catalyst's Archipelago Node."
fi

if [ "$CATALYST_STATS_DOCKER_TAG" != "latest" ]; then
    printWarning "You are not running latest image of Catalyst Stats Node."
fi

echo -n " - DOCKER_TAG:                " ; echo -e "\033[33m ${DOCKER_TAG} \033[39m"
echo -n " - LAMB2_DOCKER_TAG:          " ; echo -e "\033[33m ${LAMB2_DOCKER_TAG} \033[39m"
echo -n " - ARCHIPELAGO_DOCKER_TAG:    " ; echo -e "\033[33m ${ARCHIPELAGO_DOCKER_TAG} \033[39m"
echo -n " - ARCHIPELAGO_CORE_DOCKER_TAG: " ; echo -e "\033[33m ${ARCHIPELAGO_CORE_DOCKER_TAG} \033[39m"
echo -n " - CATALYST_STATS_DOCKER_TAG: " ; echo -e "\033[33m ${CATALYST_STATS_DOCKER_TAG} \033[39m"
echo -n " - CATALYST_URL:              " ; echo -e "\033[33m ${CATALYST_URL} \033[39m"
echo -n " - CONTENT_SERVER_STORAGE:    " ; echo -e "\033[33m ${CONTENT_SERVER_STORAGE} \033[39m"
echo -n " - EMAIL:                     " ; echo -e "\033[33m ${EMAIL} \033[39m"
echo -n " - ETH_NETWORK:               " ; echo -e "\033[33m ${ETH_NETWORK} \033[39m"
echo -n " - REGENERATE:                " ; echo -e "\033[33m ${REGENERATE} \033[39m"
echo -n " - FORCE:                     " ; echo -e "\033[33m ${FORCE} \033[39m"
echo ""
echo "Starting in ${SLEEP_TIME} seconds... " && sleep "$SLEEP_TIME"

# Check if docker compose is installed
if ! [ -x "$(command -v docker-compose)" ]; then
  echo -n "Error: docker-compose is not installed..." >&2
  printMessage failed
  exit 1
fi

# The cron job and bootstrap.sh can both start this script; never let two runs
# touch the containers or the certificates at the same time.
if command -v flock > /dev/null; then
  # A lock file left by a run as another user (e.g. `sudo ./init.sh`) must not
  # pass for a run in progress.
  if ! { exec 9> "$lock_file"; } 2> /dev/null; then
    echo -n "Cannot write ${lock_file}; remove it or fix its owner"
    printMessage failed
    exit 1
  fi
  if ! flock -n 9; then
    echo -n "Another init.sh run is in progress"
    printMessage failed
    exit 1
  fi
else
  # No flock (e.g. macOS): mkdir is atomic too. A lock left behind by a killed
  # run is taken over once its process is gone. One without a pid yet was taken
  # a moment ago by a run that has not written it.
  if ! mkdir "$lock_dir" 2> /dev/null; then
    lock_pid="$(cat "$lock_dir/pid" 2> /dev/null)"
    if { [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2> /dev/null; } ||
       { [ -z "$lock_pid" ] && [ -n "$(find "$lock_dir" -maxdepth 0 -mmin -1)" ]; }; then
      echo -n "Another init.sh run is in progress"
      printMessage failed
      exit 1
    fi
    mkdir -p "$lock_dir"
  fi
  echo $$ > "$lock_dir/pid"
  trap 'rm -rf "$lock_dir"' EXIT
fi

if ! [ -f ".env-database-admin" ]; then
    ROOT_PASSWORD="$(openssl rand -hex 8)"
    {
      echo "POSTGRES_USER=postgres"
      echo "POSTGRES_PASSWORD=${ROOT_PASSWORD}"
      echo "POSTGRES_DB=postgres"
      echo "POSTGRES_HOST=postgres"
      echo "POSTGRES_PORT=5432"
    } > .env-database-admin
fi

source ".env-database-admin"

if ! [ -f ".env-database-metrics" ]; then
    {
      echo "DATA_SOURCE_NAME=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=disable"
      echo "DATA_SOURCE_URI=${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=disable"
      echo "DATA_SOURCE_USER=${POSTGRES_USER}"
      echo "DATA_SOURCE_PASS=${POSTGRES_PASSWORD}"
      echo "PG_EXPORTER_AUTO_DISCOVER_DATABASES=true"
    } > .env-database-metrics
fi

source ".env-database-metrics"

if ! [ -f ".env-database-content" ]; then
    USER="cs$(openssl rand -hex 4)"
    PASSWORD="$(openssl rand -hex 8)"
    {
      echo "POSTGRES_CONTENT_USER=${USER}"
      echo "POSTGRES_CONTENT_PASSWORD=${PASSWORD}"
      echo "POSTGRES_CONTENT_DB=content"
    } > .env-database-content
fi

source ".env-database-content"

if [ -z "$POSTGRES_CONTENT_PASSWORD" ]; then
  echo "Empty POSTGRES_CONTENT_PASSWORD"
  printMessage failed
  exit 1
fi

if [ -z "$POSTGRES_CONTENT_USER" ]; then
  echo "Empty POSTGRES_CONTENT_USER"
  printMessage failed
  exit 1
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "Empty POSTGRES_PASSWORD"
  printMessage failed
  exit 1
fi

if test ${MAINTENANCE_MODE} -eq 1; then
  echo "## Running maintenance..."
  compose down --remove-orphans
  docker-compose -f docker-compose-maintenance.yml up -d
  exit $?
fi

# If the server is localhost, do not enable https
# Setup the nginx conf file with plain http
# else, make sure there is a certificate nginx can start with
export nginx_url="${CATALYST_URL##*/}"
# It names nginx's server and the certificate files moved around as root, so
# never let a malformed CATALYST_URL (e.g. a trailing slash) turn it into an
# empty or path-like value.
if ! [[ "$nginx_url" =~ ^[A-Za-z0-9.-]+$ ]] || [[ "$nginx_url" == *..* ]]; then
  echo -n "CATALYST_URL must be a scheme and a host name, like https://catalyst.example.com (got \"${CATALYST_URL}\") "
  printMessage failed
  exit 1
fi
use_https=0
if [ "${CATALYST_URL}" != "http://localhost" ]; then
    use_https=1
    echo "## Using HTTPS."

    if ! ensureTlsConfig; then
      if [ -f "$data_path/conf/options-ssl-nginx.conf" ] && [ -f "$data_path/conf/ssl-dhparams.pem" ]; then
        printWarning "Could not update the TLS parameters, keeping the current ones"
      else
        echo -n "Failed to download the TLS parameters nginx needs... "
        printMessage failed
        exit 1
      fi
    fi

    echo "## Checking certificate for ${nginx_url}..."
    read -r cert_name cert_state <<< "$(certState)"
    case "$cert_state" in
      missing|staging|weak-key|expiring|recent|valid)
        echo "## Certificate ${cert_name}: ${cert_state}"
        ;;
      *)
        echo -n "Failed to inspect the current certificate (got \"${cert_name} ${cert_state}\"). Take a look above for errors! "
        printMessage failed
        exit 1
        ;;
    esac

    # Use the selected lineage, never assume its name is the host. Until the
    # first issuance there is none, so nginx starts with the bootstrap one.
    certificate_path="/etc/letsencrypt/live/${cert_name}"
    if [ "$cert_state" = "missing" ]; then
      if ! createBootstrapCert; then
        echo -n "Failed to create the bootstrap certificate... "
        printMessage failed
        exit 1
      fi
      certificate_path="/etc/letsencrypt/bootstrap/${nginx_url}"
    fi

    echo -n "## Replacing value \"\$katalyst_host\" on nginx server file ${nginx_url}... "
    renderHttpsConfig "$nginx_url" "$certificate_path" "$nginx_server_template_https" "$nginx_server_file" || exit 1
    printMessage ok
else
    echo "## Using HTTP because CATALYST_URL is set to http://localhost"
    echo -n "## Replacing value \$katalyst_host on nginx server file... "
    sed "s/\$katalyst_host/${nginx_url}/g" ${nginx_server_template_http} > ${nginx_server_file}
    printMessage ok
fi

if ! grep -q "${nginx_url}" "${nginx_server_file}"; then
  printMessage failed
  echo "Failed to perform changes on nginx server file, no changes found. Look into ${nginx_server_file} for more information"
  exit 1
fi

# A registry being down should not keep the node from starting with the images
# it already has. Any image that is missing locally makes `up` fail below.
echo "## Pulling images..."
if ! compose pull --quiet; then
  printWarning "Failed to pull some images, continuing with the ones available locally"
fi

if test ${FORCE} -eq 1; then
  echo "## Bringing all containers down (--force)..."
  if ! compose down --remove-orphans; then
    echo -n "Failed to stop catalyst node"
    printMessage failed
    exit 1
  fi
fi

# Remember which container backs each config-driven service, to tell below
# whether `up` already recreated it.
containers_before=""
for entry in $config_services; do
  service="${entry%%:*}"
  containers_before="${containers_before}${service} $(compose ps -q "$service")"$'\n'
done

# Unless forced, only the services whose image or definition changed are
# recreated; the rest keep running untouched.
echo "## Starting containers... "
if ! compose up -d --remove-orphans; then
  echo -n "Failed to start catalyst node"
  printMessage failed
  exit 1
fi

new_checksums=""
for entry in $config_services; do
  service="${entry%%:*}"
  sum="$(configChecksum "${entry#*:}")"
  if [ "$sum" != "$(storedConfigChecksum "$service")" ]; then
    before="$(echo "$containers_before" | awk -v s="$service" '$1 == s { print $2 }')"
    if [ -n "$before" ] && [ "$before" = "$(compose ps -q "$service")" ]; then
      echo "## Configuration of ${service} changed, restarting it..."
      if ! compose restart "$service"; then
        echo -n "Failed to restart ${service}"
        printMessage failed
        exit 1
      fi
    fi
  fi
  new_checksums="${new_checksums}${service} ${sum}"$'\n'
done
if ! { printf '%s' "$new_checksums" > "$config_checksums_file"; } 2> /dev/null; then
  printWarning "Cannot write ${config_checksums_file}, so the next run will restart ${config_services// /, } again; remove it or fix its owner"
fi

# Test the new nginx.conf in a one-off container first: restarting nginx with a
# broken one would take it down, while failing here keeps it serving.
if nginxConfStale; then
  echo "## nginx.conf changed, validating it before restarting nginx..."
  if ! nginxConfigTest compose run --rm --no-deps -T --entrypoint nginx nginx; then
    echo -n "The new nginx.conf is invalid, nginx keeps running with the previous one "
    printMessage failed
    exit 1
  fi
  if ! compose restart nginx; then
    echo -n "Failed to restart nginx"
    printMessage failed
    exit 1
  fi
fi

cert_failed=0
if test ${use_https} -eq 1; then
  case "$cert_state" in
    missing)
      echo "## No Let's Encrypt certificate for ${nginx_url} yet."
      cert_failed=1
      if moveStrayCertFiles && issueCert "$cert_name"; then
        # Point nginx at the lineage certbot actually wrote; the bootstrap
        # configuration stays in place if there is none.
        read -r cert_name cert_state <<< "$(certState)"
        case "$cert_state" in
          staging|weak-key|expiring|recent|valid)
            renderHttpsConfig "$nginx_url" "/etc/letsencrypt/live/${cert_name}" \
              "$nginx_server_template_https" "$nginx_server_file" && cert_failed=0
            ;;
          *)
            printWarning "Could not find the issued certificate (got \"${cert_name} ${cert_state}\"), keeping the bootstrap one"
            ;;
        esac
      fi
      ;;
    staging|weak-key)
      echo "## The current certificate must be replaced (${cert_state})."
      issueCert "$cert_name" || printWarning "Failed to replace the certificate, keeping the current one"
      ;;
    expiring)
      echo "## The certificate expires in less than ${cert_renew_days} days."
      renewCert "$cert_name" || printWarning "Failed to renew the certificate, the certbot service will keep trying"
      ;;
    recent)
      if test ${REGENERATE} -eq 1; then
        printWarning "REGENERATE=1 but the certificate was issued less than a day ago, so it was not regenerated. Set REGENERATE back to 0 to avoid hitting the Let's Encrypt rate limits."
      else
        echo "## Current certificates will be used."
      fi
      ;;
    valid)
      if test ${REGENERATE} -eq 1; then
        echo "## Regenerating the certificate because REGENERATE=1."
        issueCert "$cert_name" || printWarning "Failed to regenerate the certificate, keeping the current one"
      else
        echo "## Current certificates will be used."
      fi
      ;;
  esac
fi

# Picks up configuration and certificate changes without dropping connections.
echo -n "## Reloading nginx... "
if ! nginx_test="$(nginxConfigTest compose exec -T nginx nginx)"; then
  printMessage failed
  echo "$nginx_test"
  exit 1
fi
if ! compose exec -T nginx nginx -s reload > /dev/null 2>&1; then
  printMessage failed
  exit 1
fi
printMessage ok

# Images replaced by this or earlier updates are left dangling and slowly fill the disk.
docker image prune -f | tail -n 1

if test ${cert_failed} -eq 1; then
  echo -n "Failed to issue the certificate. Is ${nginx_url} pointing to this server and is port 80 reachable? "
  printMessage failed
  exit 1
fi

echo "## Catalyst server is up and running at $CATALYST_URL"
