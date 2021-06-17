#!/bin/bash
set -e

CHALLENGE_URL=$1; shift
URL=$1; shift
EXPECTED_STATUS=$1; shift

# Get challenge
GIVEN_CHALLENGE=$(curl $CHALLENGE_URL 2>/dev/null)
echo "Obtained challenge: ${GIVEN_CHALLENGE}"
CHALLENGE_COMPLEXITY=$(echo ${GIVEN_CHALLENGE}| jq .complexity)
CHALLENGE=$(echo ${GIVEN_CHALLENGE} | jq .challenge)

# Solve Challenge
CHALLENGE_NONCE=$(node ./.github/workflows/solveChallenge.js $CHALLENGE $CHALLENGE_COMPLEXITY)

# Get JWT
CHALLENGE_BODY=$(echo "{\"complexity\": ${CHALLENGE_COMPLEXITY}, \"challenge\": ${CHALLENGE}, \"nonce\": \"${CHALLENGE_NONCE}\"}")
echo "Sending challenge: ${CHALLENGE_BODY}"
RESPONSE=$(curl -X POST $CHALLENGE_URL 2>/dev/null --header "Content-Type: application/json" --verbose  -d "$CHALLENGE_BODY" )
echo "Response from pow auth server: ${RESPONSE}"
JWT=$( echo ${RESPONSE}| jq .jwt)

# Make the request
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
