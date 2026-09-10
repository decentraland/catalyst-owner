#!/bin/bash -x

if ! [ -f ".env-cron" ]; then
  echo 'Warning: .env-cron does not exist'
else
  source ".env-cron"
fi

git config pull.rebase true
git config rebase.autoStash true

# select the provided GIT_CATALYST_OWNER_BRANCH or fallback to current_branch
branch=${GIT_CATALYST_OWNER_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}

# Update the catalyst-owner version using the current branch.
# Do not continue with either action if the pull itself fails: a failed pull
# must not be interpreted as a repository update.
previousCommit=$(git rev-parse HEAD) || {
  echo 'Unable to determine the current catalyst-owner revision; skipping cron actions'
  exit 1
}

if ! git pull origin "$branch"; then
  echo "Failed to update catalyst-owner from origin/$branch; skipping reinitialization and SQS processing"
  exit 1
fi

currentCommit=$(git rev-parse HEAD) || {
  echo 'Unable to determine the updated catalyst-owner revision; skipping cron actions'
  exit 1
}

if [ "$previousCommit" != "$currentCommit" ]; then
  # Reinitialize the catalyst only when the checkout changed.
  bash ./init.sh
else
  # Process pending deployments when the checkout is already up to date.
  bash ./receive-sqs.sh
fi
