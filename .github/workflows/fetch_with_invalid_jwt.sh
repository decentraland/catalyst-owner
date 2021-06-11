#!/bin/bash

URL=$1; shift
EXPECTED_STATUS=$1; shift


STATUS_CODE=$(curl --insecure --silent -v $* --output /dev/stderr --write-out "%{http_code}"  -H "Cookie: JWT=anInvalidJWT" "$URL")

if [ $? -ne 0 ]; then
  echo "❌ Curl failed"
  exit 1
fi
if  test "$STATUS_CODE" -ne $EXPECTED_STATUS; then
  echo "❌ Status code $STATUS_CODE != $EXPECTED_STATUS"
  exit 1
else
  echo "✅ Status code $STATUS_CODE == $EXPECTED_STATUS"
  exit 0
fi
