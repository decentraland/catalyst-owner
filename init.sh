#!/bin/bash
export rsa_key_size=4096
export data_path="local/certbot"
export nginx_server_file="local/nginx/conf.d/00-katalyst.conf"
export nginx_server_template_http="local/nginx/conf.d/katalyst-http.conf.template"
export nginx_server_template_https="local/nginx/conf.d/katalyst-https.conf.template"

# ensure we have wide path options to run in different environments
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"

####
# Functions
#####

leCertEmit () {
  if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
    echo "## Downloading recommended TLS parameters ..."
    mkdir -p "$data_path/conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
    echo
  fi

  echo " Creating dummy certificate for $nginx_url..."
  path="/etc/letsencrypt/live/$nginx_url"
  mkdir -p "$data_path/conf/live/$nginx_url"
  docker-compose run --rm --entrypoint "\
    openssl req -x509 -nodes -newkey rsa:1024 -days 1\
      -keyout '$path/privkey.pem' \
      -out '$path/fullchain.pem' \
      -subj '/CN=localhost'" certbot

  echo -n "## Starting nginx ..."
  docker-compose -f docker-compose.yml -f "platform.$(uname -s).yml" up --remove-orphans --force-recreate -d nginx

  if test $? -ne 0; then
    echo -n "Failed to start nginx...  "
    printMessage failed
    exit 1
  else
    echo -n "## Dummy certificates created ..."
    printMessage ok
  fi

    echo -n "## Deleting dummy certificate for $nginx_url ..."
    docker-compose run --rm --entrypoint "\
            rm -Rf /etc/letsencrypt/live/$nginx_url && \
            rm -Rf /etc/letsencrypt/archive/$nginx_url && \
            rm -Rf /etc/letsencrypt/renewal/$nginx_url.conf" certbot
        echo

        if test $? -ne 0; then
            echo -n "Failed to remove files... "
            printMessage failed
            exit 1
        else
            echo -n "## Files deleted ... "
            printMessage ok
        fi

        echo "## Requesting Let's Encrypt certificate for $nginx_url... "
        domain_args=""
        domain_args="$domain_args -d ${nginx_url}"
        staging_arg="--staging"

        if [ "$CATALYST_OWNER_CHANNEL" = "stable" ]; then
          staging_arg=""
        fi

        # Select appropriate EMAIL arg
        case "$EMAIL" in
            "") email_arg="--register-unsafely-without-email" ;;
            *) email_arg="--email $EMAIL" ;;
        esac

        # wait until the server responds
        serverAlive=10
        until [ $serverAlive -lt 1 ]; do
          echo "Checking server liveness: ${CATALYST_URL}"
          statusCode=$(curl --insecure -I -vv -s --http1.1 --output /dev/stderr --write-out "%{http_code}" "${CATALYST_URL}")
	  returnCode=$?
          echo ">> statusCode: ${statusCode} returnCode: ${returnCode}"
          if [ "$statusCode" -lt 500 ] && [ "$returnCode" -eq 0 ]; then
            serverAlive=0
            echo ">> Success"
          else
            ((serverAlive=serverAlive+1))
            echo ">> Waiting..."
            sleep 6
          fi
        done

        docker-compose run --rm --entrypoint "\
            certbot certonly --webroot -w /var/www/certbot \
            --no-eff-email \
            $staging_arg \
            $email_arg \
            $domain_args \
            --rsa-key-size $rsa_key_size \
            --agree-tos \
            --force-renewal" certbot

        if test $? -ne 0; then
            echo -n "Failed to request certificates... "
            printMessage failed
            exit 1
        else
            echo -n "## Certificates issued "
            printMessage ok
        fi

        echo "## Reloading nginx ..."
        docker-compose restart nginx
        if test $? -ne 0; then
            echo -n "Failed to reload nginx... "
            printMessage failed
            exit 1
        else
            echo -n "## Nginx Reloaded"
            printMessage ok
        fi

        echo "## Going for the real certs..."

        docker-compose run --rm --entrypoint "\
        certbot certonly --webroot -w /var/www/certbot \
            $email_arg \
            $domain_args \
            --no-eff-email \
            --rsa-key-size $rsa_key_size \
            --agree-tos \
            --force-renewal" certbot

        if test $? -ne 0; then
            echo -n "Failed to request certificates. Handshake failed?, the URL is pointing to this server?: "
            printMessage failed
            exit 1
        else
            echo -n "Real certificates emited "
            printMessage ok
        fi


        echo "## Reloading nginx with real certs..."
        docker-compose restart nginx
        if test $? -ne 0; then
            echo -n "Failed to reload nginx... "
            printMessage failed
            exit 1
        else
            echo -n "## Nginx Reloaded"
            printMessage ok
        fi
}

printMessage () {
    Type=$1
    case ${Type} in
      ok) echo -e "[\e[92m OK \e[39m]" ;;
      failed) echo -e "[\e[91m FAILED \e[39m]" ;;
      *) echo "";;
    esac
}

##
# Main program
##
clear
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
if test ${EMAIL}; then
  printMessage ok
else
    echo -n "Failed to check the email."
    printMessage failed
    exit 1
fi

echo -n "## Checking if storage is configured... "
if test -d ${CONTENT_SERVER_STORAGE}; then
    printMessage ok
else
    echo -n "Failed to check the storage."
    printMessage failed
    exit 1
fi

echo -n "## Checking if catalyst url is configured... "
if test ${CATALYST_URL}; then
    printMessage ok
else
    echo -n "Failed to check the catalyst url."
    printMessage failed
    exit 1
fi

# Define defaults
export DOCKER_TAG=${DOCKER_TAG:-latest}
export LIGHTHOUSE_DOCKER_TAG=${LIGHTHOUSE_DOCKER_TAG:-latest}
export EXPLORER_BFF_DOCKER_TAG=${EXPLORER_BFF_DOCKER_TAG:-latest}
export ARCHIPELAGO_DOCKER_TAG=${ARCHIPELAGO_DOCKER_TAG:-latest}
REGENERATE=${REGENERATE:-0}
SLEEP_TIME=${SLEEP_TIME:-5}
MAINTENANCE_MODE=${MAINTENANCE_MODE:-0}

if [ "$DOCKER_TAG" != "latest" ]; then
    echo -e "\033[33m WARNING: You are not running latest image of Catalyst's Content and Catalyst's Lambdas Nodes. \033[39m"
fi

if [ "$LIGHTHOUSE_DOCKER_TAG" != "latest" ]; then
    echo -e "\033[33m WARNING: You are not running latest image of Catalyst's Lighthouse Node. \033[39m"
fi

if [ "$ARCHIPELAGO_DOCKER_TAG" != "latest" ]; then
    echo -e "\033[33m WARNING: You are not running latest image of Catalyst's Archipelago Node. \033[39m"
fi

if [ "$EXPLORER_BFF_DOCKER_TAG" != "latest" ]; then
    echo -e "\033[33m WARNING: You are not running latest image of Catalyst's Explorer BFF Node. \033[39m"
fi

echo -n " - DOCKER_TAG:              " ; echo -e "\033[33m ${DOCKER_TAG} \033[39m"
echo -n " - LIGHTHOUSE_DOCKER_TAG:   " ; echo -e "\033[33m ${LIGHTHOUSE_DOCKER_TAG} \033[39m"
echo -n " - CATALYST_URL:            " ; echo -e "\033[33m ${CATALYST_URL} \033[39m"
echo -n " - CONTENT_SERVER_STORAGE:  " ; echo -e "\033[33m ${CONTENT_SERVER_STORAGE} \033[39m"
echo -n " - EMAIL:                   " ; echo -e "\033[33m ${EMAIL} \033[39m"
echo -n " - ETH_NETWORK:             " ; echo -e "\033[33m ${ETH_NETWORK} \033[39m"
echo -n " - REGENERATE:              " ; echo -e "\033[33m ${REGENERATE} \033[39m"
echo ""
echo "Starting in ${SLEEP_TIME} seconds... " && sleep "$SLEEP_TIME"

# Check if docker compose is installed
if ! [ -x "$(command -v docker-compose)" ]; then
  echo -n "Error: docker-compose is not installed..." >&2
  printMessage failed
  exit 1
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

docker pull "decentraland/catalyst-content:${DOCKER_TAG:-latest}"
if [ $? -ne 0 ]; then
  echo -n "Failed to pull the content's docker image with tag ${DOCKER_TAG:-latest}"
  printMessage failed
  exit 1
fi

docker pull "decentraland/catalyst-lambdas:${DOCKER_TAG:-latest}"
if [ $? -ne 0 ]; then
  echo -n "Failed to pull the lambda's docker image with tag ${DOCKER_TAG:-latest}"
  printMessage failed
  exit 1
fi

docker pull "decentraland/catalyst-lighthouse:${LIGHTHOUSE_DOCKER_TAG:-latest}"
if [ $? -ne 0 ]; then
  echo -n "Failed to pull the lighthouse's docker image with tag ${LIGHTHOUSE_DOCKER_TAG:-latest}"
  printMessage failed
  exit 1
fi

docker pull "quay.io/decentraland/archipelago-service:${ARCHIPELAGO_DOCKER_TAG:-latest}"
if [ $? -ne 0 ]; then
  echo -n "Failed to pull the archipelago's docker image with tag ${ARCHIPELAGO_DOCKER_TAG:-latest}"
  printMessage failed
  exit 1
fi

docker pull "quay.io/decentraland/explorer-bff:${EXPLORER_BFF_DOCKER_TAG:-latest}"
if [ $? -ne 0 ]; then
  echo -n "Failed to pull the explorer-bff's docker image with tag ${EXPLORER_BFF_DOCKER_TAG:-latest}"
  printMessage failed
  exit 1
fi

docker-compose stop nginx
if [ $? -ne 0 ]; then
  echo -n "Failed to stop nginx! "
  printMessage failed
  exit 1
fi

# If the server is localhost, do not enable https
# Setup the nginx conf file with plain http
# else, create new certs
export nginx_url="$(echo "${CATALYST_URL##*/}")"
if [ "${CATALYST_URL}" != "http://localhost" ]; then
    echo "## Using HTTPS."
    echo -n "## Replacing value \"\$katalyst_host\" on nginx server file ${nginx_url}... "
    sed "s/\$katalyst_host/${nginx_url}/g" ${nginx_server_template_https} > ${nginx_server_file}

    # This is the URL without the 'http/s'
    # Needed to place the server on nginx conf file
    if [ -d "$data_path/conf/live/$nginx_url" ]; then
        echo "Existing data found for \$nginx_url."

        if test ${REGENERATE} -eq 1; then
            leCertEmit $nginx_url
        else
            echo "## Current certificates will be used."
        fi
    else
        echo "## No certificates found. Performing certificate creation... "
        leCertEmit $nginx_url

        if test $? -ne 0; then
            printMessage failed
            echo -n "Failed to deploy certificates. Take a look above for errors!"
            exit 1
        fi
    fi
    echo -n "## Finalizing Let's Encrypt setup... "
    printMessage ok
else
    echo "## Using HTTP because CATALYST_URL is set to http://localhost"
    echo -n "## Replacing value \$katalyst_host on nginx server file... "
    sed "s/\$katalyst_host/${nginx_url}/g" ${nginx_server_template_http} > ${nginx_server_file}
    printMessage ok
fi


matches=$(cat ${nginx_server_file} | grep ${nginx_url}  | wc -l)
if test $matches -eq 0; then
  printMessage failed
  echo "Failed to perform changes on nginx server file, no changes found. Look into ${nginx_server_file} for more information"
  exit 1
fi

echo "## Restarting containers... "
docker-compose down
if test ${MAINTENANCE_MODE} -eq 1; then
  echo 'Running maintenance...'
  docker-compose -f docker-compose-maintenance.yml up -d
else
  docker-compose -f docker-compose.yml -f "platform.$(uname -s).yml" up --remove-orphans -d nginx
  if test $? -ne 0; then
    echo -n "Failed to start catalyst node"
    printMessage failed
    exit 1
  fi
  echo "## Catalyst server is up and running at $CATALYST_URL"
fi
