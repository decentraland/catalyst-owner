#!/bin/bash

git config pull.rebase true
git config rebase.autoStash true

# select the provided GIT_CATALYST_OWNER_BRANCH or fallback to current_branch
branch=${GIT_CATALYST_OWNER_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}

# Update the catalyst-owner version using the current branch
git pull origin "$branch" | grep -o 'Already up to date.'
isUpToDate=$?

export SLEEP_TIME=0

if [ $isUpToDate -eq 0 ]; then
  # if it is not up to date, reinit the catalyst to apply changes
  bash ./init.sh
else
  # update the version if we have messages in the SQS
  bash ./receive-sqs.sh
fi
