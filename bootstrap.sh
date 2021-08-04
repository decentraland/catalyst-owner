#!/bin/bash

# This file is automatically configured by `userdata.sh` to run when
# the instance starts.

# It mounts the volumes if necessary (MOUNT_DISK env var) and starts the services.

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
