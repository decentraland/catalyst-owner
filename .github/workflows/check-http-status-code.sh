#!/bin/bash
set -e

URL=$1; shift
EXPECTED_STATUS=$1; shift

# STATUSCODE=$(docker run --network container:nginx curlimages/curl --silent -v $* --output /dev/stderr --write-out "%{http_code}" "$URL")
STATUSCODE=$(curl --insecure --silent -v $* --output /dev/stderr --write-out "%{http_code}" "$URL")

if  test "$STATUSCODE" -ne $EXPECTED_STATUS; then
  echo "❌ Status code $STATUSCODE != $EXPECTED_STATUS"
  exit 1
else
  echo "✅ Status code $STATUSCODE == $EXPECTED_STATUS"
  exit 0
fi
