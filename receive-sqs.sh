#!/bin/bash

# reads a message from an SQS named SQS_QUEUE_NAME and performs the update based on the .version field of the message

if [ -n "${SQS_QUEUE_NAME}" ]; then
  SQS_URL=$(aws sqs get-queue-url --queue-name "${SQS_QUEUE_NAME}" | jq -r .QueueUrl)

  # Update the version if we have messages in the SQS
  if [ -n "${SQS_URL}" ]; then
    MSG=$(aws sqs receive-message --queue-url "$SQS_URL");

    if [ -n "$MSG" ]; then
      DOCKER_TAG=$(echo "$MSG" | jq -r '.Messages[0].Body' | jq -r .Message | jq -r .version);
      export DOCKER_TAG

      if ! [ -f ".env" ]; then
        echo -n "Error: .env does not exist" >&2
      else
         {
          echo "";
          echo "# $(date)";
          echo "DOCKER_TAG=\"$DOCKER_TAG\"";
         } >> .env
      fi

      bash ./init.sh

      EXIT_CODE=$?

      # Only remove the message from the queue if the update was successful
      if [ $EXIT_CODE -eq 0 ]; then
        echo "$MSG" | jq -r '.Messages[0] | .ReceiptHandle' | (xargs -I {} aws sqs delete-message --queue-url "$SQS_URL" --receipt-handle {});
      else
        echo "[ERROR] consuming message $MSG"
        exit 1
      fi
    else
      echo 'No message was received'
    fi
  else
    echo 'No SQS_URL is set'
  fi
else
  echo 'No SQS_QUEUE_NAME is set'
fi