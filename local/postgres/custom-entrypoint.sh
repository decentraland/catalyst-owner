#!/usr/bin/env bash
set -Eeo pipefail

# Example using the functions of the postgres entrypoint to customize startup to always run files in /always-initdb.d/
# Based on https://github.com/docker-library/postgres/pull/496

source "$(which docker-entrypoint.sh)"

docker_setup_env
docker_create_db_directories
# assumption: we are already running as the owner of PGDATA

# This is needed if the container is started as `root`
if [ "$(id -u)" = '0' ]; then
	exec gosu postgres "$BASH_SOURCE" "$@"
fi

if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
	docker_verify_minimum_env
	docker_init_database_dir
	pg_setup_hba_conf

	# only required for '--auth[-local]=md5' on POSTGRES_INITDB_ARGS
	export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"

	docker_temp_server_start "$@" -c max_locks_per_transaction=256
	docker_setup_db
	docker_process_init_files /docker-entrypoint-initdb.d/*
  docker_process_init_files /always-initdb.d/*
	docker_temp_server_stop
else
	docker_temp_server_start "$@"
	docker_process_init_files /always-initdb.d/*
	docker_temp_server_stop
fi

exec postgres "$@"