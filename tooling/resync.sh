#!/bin/bash

printMessage () {
    Type=$1
    case ${Type} in
      ok) echo -e "[\e[92m OK \e[39m]" ;;
      failed) echo -e "[\e[91m FAILED \e[39m]" ;;
      *) echo "";;
    esac
}

# Make sure env file exists
if ! [ -f ".env" ]; then
  echo -n "Error: .env does not exist" >&2
  printMessage failed
  exit 1
else
  # If it exists, load it
  source ".env"
fi

# Make sure that the storage exists
echo -n "## Checking if storage is configured..."
if test -d ${CONTENT_SERVER_STORAGE}; then
    printMessage ok
else
    echo -n "Failed to check the storage."
    printMessage failed
    exit 1
fi

# Set vars
IMMUTABLE=${CONTENT_SERVER_STORAGE}/history/immutableHistory.log
IMMUTABLE_OLD=${CONTENT_SERVER_STORAGE}/history/immutableHistory-old.log
TEMP=${CONTENT_SERVER_STORAGE}/history/tempHistory.log
TEMP_OLD=${CONTENT_SERVER_STORAGE}/history/tempHistory-old.log

# Check if there is an immutable history log or not
if test -f ${IMMUTABLE}; then
    # Stop the content server
    docker-compose rm -fs content-server

    # Move all immutable history into the temp history
    # Old temp and immutable logs will be stored with a '-old' suffix
    cp ${TEMP} ${TEMP_OLD}
    echo -en '\n' >> ${TEMP}
    cat ${IMMUTABLE} >> ${TEMP}
    mv ${IMMUTABLE} ${IMMUTABLE_OLD}

    # Start the content server again
    docker-compose up --force-recreate -d content-server

    echo "DONE!"
else
    echo "No immutable history found, so no resync is necessary"
fi