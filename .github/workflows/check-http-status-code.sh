#!/bin/bash

URL=$1; shift
EXPECTED_STATUS=$1; shift

STATUSCODE=$(curl --silent -v $* --output /dev/stderr --write-out "%{http_code}" "$URL")
if [ $? -ne 0 ]; then
  echo "❌ Curl failed"
  exit 1
fi
if  test "$STATUSCODE" -ne $EXPECTED_STATUS; then
  echo "❌ Status code $STATUSCODE != $EXPECTED_STATUS"
  exit 1
else
  echo "✅ Status code $STATUSCODE == $EXPECTED_STATUS"
  exit 0
fi