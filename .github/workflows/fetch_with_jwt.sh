#!/bin/bash
set -e

CHALLENGE_URL=$1; shift
URL=$1; shift
EXPECTED_STATUS=$1; shift

# Get challenge

CHALLENGE_RESPONSE=$(curl $CHALLENGE_URL 2>/dev/null)
echo "Challenge: $CHALLENGE_RESPONSE"
CHALLENGE_COMPLEXITY=$(echo $CHALLENGE_RESPONSE | jq .complexity)
CHALLENGE=$(echo $CHALLENGE_RESPONSE | jq .challenge)

# Solve Challenge
CHALLENGE_NONCE=$(node ./.github/workflows/solveChallenge.js $CHALLENGE $CHALLENGE_COMPLEXITY)


# Get JWT
JWT_RESPONSE=$(curl -X POST $CHALLENGE_URL 2>/dev/null --header "Content-Type: application/json" --verbose  --data '{
    "complexity": "${CHALLENGE_COMPLEXITY}",
    "challenge": "${CHALLENGE}",
    "nonce":
      "${CHALLENGE_NONCE}"
  }' )
JWT=$(echo $JWT_RESPONSE | jq .jwt)


STATUS_CODE=$(curl --insecure --silent -v $* --output /dev/stderr --write-out "%{http_code}"  -H "Cookie: JWT=${JWT}" "$URL")

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
