#!/bin/bash

# Update the version if we have messages in the SQS
if [ -n "${SQS_URL}" ]; then
  MSG=$(aws sqs receive-message --queue-url "$SQS_URL");
  if [ -n "$MSG" ]
  then
    DOCKER_TAG=$(echo "$MSG" | jq -r '.Messages[] | .Body' | jq -r '.MessageAttributes.version.Values');
    export DOCKER_TAG

    bash ./init.sh

    EXIT_CODE=$?

    # Only remove the message from the queue if the update was successful
    if [ $EXIT_CODE -eq 0 ]; then
      echo "$MSG" | jq -r '.Messages[] | .ReceiptHandle' | (xargs -I {} aws sqs delete-message --queue-url "$SQS_URL" --receipt-handle {});
    else
      echo "Error consuming message $MSG"
    fi
  fi
fi