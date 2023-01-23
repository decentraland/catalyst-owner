#!/bin/bash

source .env-cron

if [ -n "${SQS_QUEUE_NAME}" ]; then
  SQS_URL=$(aws sqs get-queue-url --queue-name "${SQS_QUEUE_NAME}" | jq -r .QueueUrl)
  MSG=$(aws sqs receive-message --queue-url $SQS_URL)
  if [ ! -z "$MSG" ]; then
    COUNT=$(echo $MSG | jq ".Messages|length")
    if [ $COUNT ] >0; then
      RECEIPT=$(echo $MSG | jq ".Messages[0].ReceiptHandle")
      aws sqs delete-message --queue-url $SQS_URL --receipt-handle "$RECEIPT"
      BODY=$(echo $MSG | jq ".Messages[0].Body | fromjson")
      DOCKER_TAG_CONTENT=$(echo $BODY | jq -r '.tag')
      DOCKER_TAG_LIGHTHOUSE=$(echo $BODY | jq -r '.lighthouse')
      DOCKER_TAG_EXPLORER=$(echo $BODY | jq -r '.explorerbff')

      WAIT=$(echo $BODY | jq -r '.wait')
      cd /opt/ebs/catalyst-owner

      echo "# $(date)"
      # Content docker tag
      if [ $DOCKER_TAG != "null" ]; then
        echo "DOCKER_TAG=$DOCKER_TAG_CONTENT" >>.env
      fi
      
      # Lighthouse docker tag
      if [ $LIGHTHOUSE_DOCKER_TAG != "null" ]; then
        echo "LIGHTHOUSE_DOCKER_TAG=$DOCKER_TAG_LIGHTHOUSE" >>.env
      fi
      
      # Explorer BFF docker tag
      if [ $EXPLORER_BFF_DOCKER_TAG != "null" ]; then
        echo "EXPLORER_BFF_DOCKER_TAG=$DOCKER_TAG_EXPLORER" >>.env
      fi
      
      if [ $WAIT != "null" ]; then
        DATETEXT=$(date -u -d@$(($WAIT)) +"%Hh %Mm")
        source .env
        if [[ -v SLACK_WEBHOOK ]]; then
          curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"\`$LIGHTHOUSE_NAMES\` will update in $DATETEXT.\"}" $SLACK_WEBHOOK
        fi
        sleep $WAIT
      fi
      ./init.sh
    fi
  fi
fi
