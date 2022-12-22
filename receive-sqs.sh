#!/bin/bash

source .env-cron

if [ -n "${SQS_QUEUE_NAME}" ]; then
  SQS_URL=$(aws sqs get-queue-url --queue-name "${SQS_QUEUE_NAME}" | jq -r .QueueUrl)
  MSG=$(aws sqs receive-message --queue-url $SQS_URL)
  if [ ! -z "$MSG" ]
  then
    COUNT=$(echo $MSG | jq ".Messages|length")
    if [ $COUNT > 0 ]
    then
      RECEIPT=$(echo $MSG | jq ".Messages[0].ReceiptHandle")
      aws sqs delete-message --queue-url $SQS_URL --receipt-handle "$RECEIPT"
      BODY=$(echo $MSG | jq ".Messages[0].Body | fromjson")
      DOCKER_TAG_CONTENT=$(echo $BODY | jq -r '.tag')
      DOCKER_TAG_LIGHTOUSE=$(echo $BODY | jq -r '.lighthouse');
      DOCKER_TAG_EXPLORER=$(echo $BODY | jq -r '.explorerbff');

      WAIT=$(echo $BODY | jq -r '.wait')
      cd /opt/ebs/catalyst-owner
      # Content docker tag
      if grep -P '^#?DOCKER_TAG.*' .env; then
        sed -i "s/^#\?DOCKER_TAG.*/DOCKER_TAG=$DOCKER_TAG_CONTENT/g" .env
      else
        echo "DOCKER_TAG=$DOCKER_TAG_CONTENT"
      fi
      # Lighthouse docker tag
      if grep -P '^#?LIGHTHOUSE_DOCKER_TAG.*' .env; then
        sed -i "s/^#\?LIGHTHOUSE_DOCKER_TAG.*/LIGHTHOUSE_DOCKER_TAG=$DOCKER_TAG_LIGHTOUSE/g" .env
      else
        echo "LIGHTHOUSE_DOCKER_TAG=$DOCKER_TAG_LIGHTOUSE"
      fi
      # Explorer BFF docker tag
      if grep -P '^#?EXPLORER_BFF_DOCKER_TAG.*' .env; then
        sed -i "s/^#\?EXPLORER_BFF_DOCKER_TAG.*/EXPLORER_BFF_DOCKER_TAG=$DOCKER_TAG_EXPLORER/g" .env
      else
        echo "EXPLORER_BFF_DOCKER_TAG=$DOCKER_TAG_EXPLORER"
      fi
      if [ $WAIT != "null" ]; then
        RANDNUM=$((RANDOM % 18000 + 3600))
        DATETEXT=$(date -u -d@$(($RANDNUM)) +"%Hh %Mm")
        source .env
        if [[ -v SLACK_WEBHOOK ]]; then
          curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"\`$LIGHTHOUSE_NAMES\` will update in $DATETEXT.\"}" $SLACK_WEBHOOK
        fi
        sleep $RANDNUM
      fi
      ./init.sh
    fi
  fi
fi
