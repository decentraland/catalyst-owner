#!/bin/bash
set -e

URL=$1; shift
EXPECTED_STATUS=$1; shift


STATUS_CODE=$(curl --cookie-jar cookie.txt --insecure --silent -v $* --output /dev/stderr --write-out "%{http_code}"  -H "Cookie: JWT=anInvalidJWT" "$URL")

if [ $? -ne 0 ]; then
  echo "❌ Curl failed"
  exit 1
fi
if  test "$STATUS_CODE" -ne $EXPECTED_STATUS; then
  echo "❌ Status code $STATUS_CODE != $EXPECTED_STATUS"
  exit 1
else
  COOKIE=$(cat cookie.txt | grep -o 'JWT.*' | xargs)
  if test "$COOKIE" = "JWT=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT"; then
    echo "✅ Status code $STATUS_CODE == $EXPECTED_STATUS"
    exit 0
  else 
    echo "❌ Set Cookie JWT: $COOKIE != ''"
    exit 1
  fi
fi
