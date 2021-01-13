#!/bin/bash

# Update the catalyst-owner version using the current branch
git pull origin "$(git rev-parse --abbrev-ref HEAD)"

# Update the version if we have messages in the SQS
bash ./receive-sqs.sh