#!/bin/bash
export rsa_key_size=4096
export data_path="./local/certbot"
export nginx_server_file="local/nginx/conf.d/00-katalyst.conf"
export nginx_server_template_http="local/nginx/conf.d/katalyst-http.conf.template"
export nginx_server_template_https="local/nginx/conf.d/katalyst-https.conf.template"
export nginx_url=`echo ${CATALYST_URL} | awk -F\/ '{ print $3 }'`

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

  echo " Creating dummy certificate for $CATALYST_URL ..."
  path="/etc/letsencrypt/live/$CATALYST_URL"
  mkdir -p "$data_path/conf/live/$CATALYST_URL"
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

    echo -n "## Deleting dummy certificate for $CATALYST_URL ..."
    docker-compose run --rm --entrypoint "\
            rm -Rf /etc/letsencrypt/live/$CATALYST_URL && \
            rm -Rf /etc/letsencrypt/archive/$CATALYST_URL && \
            rm -Rf /etc/letsencrypt/renewal/$CATALYST_URL.conf" certbot
        echo

        if test $? -ne 0; then
            echo -n "Failed to remove files..."
            printMessage failed
            exit 1
        else
            echo -n "## files deleted ..."
            printMessage ok
        fi

        echo "## Requesting Let's Encrypt certificate for $CATALYST_URL ..."
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
            echo -n "## Certificates requested..."
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
            echo -n "Real certs emited OK..."
            printMessage ok
        fi


        echo "## Reloading nginx with real certs ..."
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
echo -n "## Loading env variables"

if ! [ -f ".env" ]; then
  echo -n "Error: .env does not exist" >&2
  printMessage failed
  exit 1
else
  export $(cat .env | xargs)
fi

if ! [ -f ".default-env" ]; then
  echo -n "Error: .default-env does not exist" >&2
  printMessage failed
  exit 1
else
  export $(cat .default-env | xargs)
fi

echo -n "## Checking if email is configured..."
if test ${EMAIL}; then
  printMessage ok
else
    echo -n "Failed to check the email."
    printMessage failed
    exit 1
fi

echo -n "## Checking if storage is configured..."
if test -d ${CONTENT_SERVER_STORAGE}; then
    printMessage ok
else
    echo -n "Failed to check the storage."
    printMessage failed
    exit 1
fi

echo -n "## Checking if catalyst url is configured..."
if test ${CATALYST_URL}; then
    printMessage ok
else
    echo -n "Failed to check the catalyst url."
    printMessage failed
    exit 1
fi

echo -n " - REGENERATE:              " ; echo -e "\e[33m ${REGENERATE} \e[39m"
echo -n " - CATALYST_URL:            " ; echo -e "[ \e[33m ${CATALYST_URL} \e[39m ]"
echo -n " - CONTENT_SERVER_STORAGE:  " ; echo -e "[ \e[33m ${CONTENT_SERVER_STORAGE} \e[39m ]"
echo -n " - EMAIL:                   " ; echo -e "\e[33m ${EMAIL} \e[39m"
echo -n " - DCL_API_URL:             " ; echo -e "\e[33m ${DCL_API_URL} \e[39m"
echo -n " - ETH_NETWORK:             " ; echo -e "\e[33m ${ETH_NETWORK} \e[39m"
echo -n " - ENS_OWNER_PROVIDER_URL:  " ; echo -e "\e[33m ${ENS_OWNER_PROVIDER_URL} \e[39m"

echo ""
echo "Starting in 5 seconds... " && sleep 5

if ! [ -x "$(command -v docker-compose)" ]; then
  echo -n "Error: docker-compose is not installed..." >&2
  printMessage failed
  exit 1
fi

docker pull decentraland/katalyst:${DOCKER_TAG}

printMessage ok
docker-compose stop nginx

if test $? -ne 0; then
  echo -n "Failed to stop nginx"
  printMessage failed
  exit 1
fi


if [ ${CATALYST_URL} != "http://localhost" ]; then
    echo -n "## Replacing HTTPS \$katalyst_host on nginx server file... "
    sed "s/\$katalyst_host/${nginx_url}/g" ${nginx_server_template_https} > ${nginx_server_file}
    
    if [ -d "$data_path" ]; then
    echo -n "## Existing data found for $CATALYST_URL. "
    if test ${REGENERATE} -eq 1; then
        leCertEmit
    else
        echo -n "## Keeping the current certs"
    fi
    else
        echo "## No certificates found. Performing certificate creation"
        leCertEmit
    fi

    if test $? -ne 0; then
        echo -n "Failed to deploy certificates. Look upstairs for errors: "
        printMessage failed
        exit 1
    fi
    echo -n "## Certs emited: "
    printMessage ok
else
    echo -n "## Replacing HTTP \$katalyst_host on nginx server file... "
    sed "s/\$katalyst_host/${nginx_url}/g" ${nginx_server_template_http} > ${nginx_server_file}
fi


matches=`cat ${nginx_server_file} | grep ${nginx_url}  | wc -l`
if test $matches -eq 0; then
  printMessage failed
  echo "Failed to perform changes on nginx server file, no changes found. Look into ${nginx_server_file} for more information"
  exit 1
fi

echo "## Restarting containers..."
docker-compose down
docker-compose up -d

if test $? -ne 0; then
  echo -n "Failed to start catalyst node"
  printMessage failed
  exit 1
fi
echo -n "## containers started Ok... "
printMessage ok
