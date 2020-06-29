#!/bin/bash

# Stop the content server
docker-compose rm -fs content-server

# Start the content server again
BOOTSTRAP_FROM_SCRATCH=true docker-compose up --force-recreate -d content-server

echo "DONE!"