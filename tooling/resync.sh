#!/bin/bash

# shellcheck source=../compose.sh
source "$(dirname "$0")/../compose.sh"

# Stop the content server
$COMPOSE_CMD rm -fs content-server

# Start the content server again
BOOTSTRAP_FROM_SCRATCH=true $COMPOSE_CMD -f docker-compose.yml -f "platform.$(uname -s).yml" up --force-recreate -d content-server

echo "DONE!"