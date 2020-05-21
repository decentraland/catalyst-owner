#!/bin/bash
export rsa_key_size=4096
export data_path="local/certbot"
export nginx_server_file="local/nginx/conf.d/00-katalyst.conf"
export nginx_server_template_http="local/nginx/conf.d/katalyst-http.conf.template"
export nginx_server_template_https="local/nginx/conf.d/katalyst-https.conf.template"

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
  docker-compose up --force-recreate -d nginx

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

        # Select appropriate EMAIL arg
        case "$EMAIL" in
            "") email_arg="--register-unsafely-without-email" ;;
            *) email_arg="--email $EMAIL" ;;
        esac


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

# Define default value of docker tag as latest
DOCKER_TAG=${DOCKER_TAG:-latest}

echo -n " - CATALYST_URL:            " ; echo -e "\033[33m ${CATALYST_URL} \033[39m"
echo -n " - CONTENT_SERVER_STORAGE:  " ; echo -e "\033[33m ${CONTENT_SERVER_STORAGE} \033[39m"
echo -n " - EMAIL:                   " ; echo -e "\033[33m ${EMAIL} \033[39m"
echo -n " - ETH_NETWORK:             " ; echo -e "\033[33m ${ETH_NETWORK} \033[39m"
echo -n " - REGENERATE:              " ; echo -e "\033[33m ${REGENERATE} \033[39m"
echo ""
echo "Starting in 5 seconds... " && sleep 5

# Check if docker compose is installed
if ! [ -x "$(command -v docker-compose)" ]; then
  echo -n "Error: docker-compose is not installed..." >&2
  printMessage failed
  exit 1
fi

if ! [ -f ".env-database-admin" ]; then
    ROOT_USER=$(cat /dev/urandom | env LC_CTYPE=C tr -dc a-z | head -c 16)
    ROOT_PASSWORD=$(cat /dev/urandom | env LC_CTYPE=C tr -dc a-zA-Z0-9 | head -c 16)
    echo "POSTGRES_USER=${ROOT_USER}" > .env-database-admin
    echo "POSTGRES_PASSWORD=${ROOT_PASSWORD}" >> .env-database-admin
    echo "POSTGRES_DB=postgres" >> .env-database-admin
    echo "POSTGRES_HOST=postgres" >> .env-database-admin
    echo "POSTGRES_PORT=5432" >> .env-database-admin
fi

source ".env-database-admin"

if ! [ -f ".env-database-content" ]; then
    USER=$(cat /dev/urandom | env LC_CTYPE=C tr -dc a-z | head -c 16)
    PASSWORD=$(cat /dev/urandom | env LC_CTYPE=C tr -dc a-zA-Z0-9 | head -c 16)
    echo "POSTGRES_CONTENT_USER=${USER}" > .env-database-content
    echo "POSTGRES_CONTENT_PASSWORD=${PASSWORD}" >> .env-database-content
    echo "POSTGRES_CONTENT_DB=content" >> .env-database-content
fi

source ".env-database-content"

docker pull decentraland/katalyst:${DOCKER_TAG}
if test $? -ne 0; then
  echo -n "Failed to stop nginx! "
  printMessage failed
  exit 1
fi

docker-compose stop nginx
if test $? -ne 0; then
  echo -n "Failed to stop nginx! "
  printMessage failed
  exit 1
fi

# If the server is localhost, do not enable https
# Setup the nginx conf file with plain http
# else, create new certs
export nginx_url=`echo "${CATALYST_URL##*/}"`
if [ ${CATALYST_URL} != "http://localhost" ]; then
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


matches=`cat ${nginx_server_file} | grep ${nginx_url}  | wc -l`
if test $matches -eq 0; then
  printMessage failed
  echo "Failed to perform changes on nginx server file, no changes found. Look into ${nginx_server_file} for more information"
  exit 1
fi

echo "## Restarting containers... "
docker-compose down
docker-compose up -d

if test $? -ne 0; then
  echo -n "Failed to start catalyst node"
  printMessage failed
  exit 1
fi
echo "## Catalyst server is up and running at $CATALYST_URL"
