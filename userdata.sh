#!/bin/bash

set -x
set -v # verbose
set -u # no unbound variables

DOCKER_COMPOSE_VERSION="1.29.2"

apt-get -qq update
apt-get -qq install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
. /etc/os-release
DOCKER_UBUNTU_CODENAME="${VERSION_CODENAME:-focal}"
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu ${DOCKER_UBUNTU_CODENAME} stable"

apt-get -qq update
apt-get -qq upgrade -y

# install docker and utils

until docker --version; do
  apt-get -qq install docker-ce -y
  sleep 1
done

until jq --version; do
  apt-get -qq install jq -y
  sleep 1
done

until aws --version; do
  apt-get -qq install awscli -y
  sleep 1
done

# start docker and fix permissions
service docker start
usermod -a -G docker ubuntu

# auto-start docker
systemctl enable --now docker

# install a known-good legacy docker-compose binary. The operational scripts
# still invoke the hyphenated command, so keep the standalone binary instead
# of relying on the optional v2 CLI plugin.
install_docker_compose() {
  local current_version
  current_version="$(docker-compose version --short 2>/dev/null || true)"

  if [ "$current_version" = "$DOCKER_COMPOSE_VERSION" ]; then
    docker-compose version
    return 0
  fi

  echo "Installing Docker Compose ${DOCKER_COMPOSE_VERSION} (found: ${current_version:-none})..."
  local temporary_binary
  temporary_binary="$(mktemp)"

  if ! curl -fsSL \
    "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
    -o "$temporary_binary"; then
    rm -f "$temporary_binary"
    return 1
  fi

  chmod 0755 "$temporary_binary"
  install -m 0755 "$temporary_binary" /usr/local/bin/docker-compose
  rm -f "$temporary_binary"
  docker-compose version
}

until install_docker_compose; do
  sleep 10
done

WD=$(pwd)

{
  # configure crontab to run on startup
  echo "@reboot (cd ${WD} && ${WD}/bootstrap.sh 2>&1) | logger -t catalyst-owner-bootstrap"

  # and to update every 5 minutes
  echo "*/5 * * * * (cd ${WD} && ${WD}/crontab.sh 2>&1) | logger -t catalyst-owner-cron"
} > .crontab

chown ubuntu:ubuntu "${WD}/.crontab"
crontab -u ubuntu "${WD}/.crontab"

# reboot to verify everyting is OK
sudo reboot
