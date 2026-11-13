#!/bin/bash
#
# Usage: ./tooling/reindex-gin.sh [index ...]
#
# Rebuilds GIN indexes in the content database with REINDEX INDEX CONCURRENTLY,
# so reads and writes keep working while it runs. Postgres 16.16 fixes GIN
# VACUUM bugs, but indexes built before the upgrade keep any stale entries
# until rebuilt. Run once per node after it is on 16.16. Defaults to
# deployments_entity_pointers_index. Safe to re-run.
#
# Needs free disk roughly equal to each index's size while it runs.

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=/dev/null
source .env-database-content

container="${POSTGRES_HOST:-postgres}"
min_version_num=160016

if [ $# -gt 0 ]; then
  indexes=("$@")
else
  indexes=(deployments_entity_pointers_index)
fi

psqlQuery () {
  docker exec "$container" psql -U postgres -d "$POSTGRES_CONTENT_DB" -v ON_ERROR_STOP=1 -tAc "$1"
}

version_num=$(psqlQuery "SHOW server_version_num;")
if [ "$version_num" -lt "$min_version_num" ]; then
  echo "Postgres is $(psqlQuery 'SHOW server_version;'). Upgrade to 16.16 or later (./init.sh) before reindexing." >&2
  exit 1
fi

for index in "${indexes[@]}"; do
  if ! [[ "$index" =~ ^[a-z0-9_]+$ ]]; then
    echo "Invalid index name: ${index}" >&2
    exit 1
  fi

  if [ -z "$(psqlQuery "SELECT to_regclass('public.${index}');")" ]; then
    echo "Index ${index} not found, skipping."
    continue
  fi

  # An interrupted REINDEX CONCURRENTLY leaves an invalid <index>_ccnew behind.
  leftovers=$(psqlQuery "SELECT c.relname FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid WHERE c.relname ~ '^${index}_ccnew[0-9]*$' AND NOT i.indisvalid;")
  for leftover in $leftovers; do
    echo "Dropping invalid leftover index ${leftover}..."
    psqlQuery "DROP INDEX CONCURRENTLY public.${leftover};" > /dev/null
  done

  echo "Reindexing ${index} ($(psqlQuery "SELECT pg_size_pretty(pg_relation_size('public.${index}'));"))..."
  start=$(date +%s)
  psqlQuery "REINDEX INDEX CONCURRENTLY public.${index};" > /dev/null
  echo "Done in $(( $(date +%s) - start ))s, new size $(psqlQuery "SELECT pg_size_pretty(pg_relation_size('public.${index}'));")."
done
