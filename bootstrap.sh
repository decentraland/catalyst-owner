#!/bin/bash

source .env

set -u # break on unbound variables
set -x # verbose

sudo bash ./mount.sh

echo "Initializing catalyst..."

export SLEEP_TIME=0

until ./init.sh; do
  echo "Retrying in 30 seconds..."
  sleep 30
done