#!/usr/bin/env bash
# =============================================================================
# PostgreSQL 12 -> 16 Migration Script
# =============================================================================
#
# This script migrates the PostgreSQL database from version 12 to 16 using
# the dump/restore approach. It must be run from the catalyst-owner root
# directory where docker-compose.yml is located.
#
# IMPORTANT: This script will cause downtime for all services while the
# migration is in progress. Duration depends on database size.
#
# Usage:
#   ./migrate-pg12-to-pg16.sh
#
# Prerequisites:
#   - Docker and docker compose must be installed and running
#   - The .env, .env-database-admin, and .env-database-content files must exist
#   - Sufficient disk space for the database dump and backup
#
# What this script does:
#   1. Verifies prerequisites and current PG version
#   2. Stops all application services (keeps only postgres running)
#   3. Creates a full database dump (pg_dumpall) from PG 12 with no active writers
#   4. Stops postgres
#   5. Backs up the existing PG 12 data directory
#   6. Starts PG 16 to initialize a fresh data directory
#   7. Restores the dump into PG 16
#   8. Starts all services and verifies health
#
# =============================================================================

set -euo pipefail

# -- Configuration ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DUMP_FILE="${SCRIPT_DIR}/backup_pg12_${TIMESTAMP}.sql"
COMPOSE_CMD="docker compose"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# -- Helper functions ---------------------------------------------------------

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

fail() {
    log_error "$1"
    exit 1
}

confirm() {
    local prompt="$1"
    local response
    echo -en "${YELLOW}${prompt} [y/N]: ${NC}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# -- Pre-flight checks --------------------------------------------------------

preflight_checks() {
    log_info "Running pre-flight checks..."

    # Must be run from project root
    log_info "  Checking docker-compose.yml..."
    if [ ! -f "${SCRIPT_DIR}/docker-compose.yml" ]; then
        fail "docker-compose.yml not found. Run this script from the catalyst-owner root directory."
    fi

    # Check docker is available
    log_info "  Checking Docker..."
    if ! command -v docker &> /dev/null; then
        fail "docker is not installed or not in PATH."
    fi

    # Check docker compose is available (try both forms)
    log_info "  Checking Docker Compose..."
    if ! ${COMPOSE_CMD} version &> /dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
        if ! ${COMPOSE_CMD} version &> /dev/null 2>&1; then
            fail "Neither 'docker compose' nor 'docker-compose' is available."
        fi
    fi

    # Check required env files exist
    log_info "  Checking required env files..."
    for envfile in .env .env-database-admin .env-database-content; do
        if [ ! -f "${SCRIPT_DIR}/${envfile}" ]; then
            fail "Required file '${envfile}' not found. Has init.sh been run?"
        fi
    done

    # Load CONTENT_SERVER_STORAGE from .env
    log_info "  Loading .env and resolving data directory..."
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/.env"
    if [ -z "${CONTENT_SERVER_STORAGE:-}" ]; then
        fail "CONTENT_SERVER_STORAGE is not set in .env"
    fi
    DATA_DIR="${CONTENT_SERVER_STORAGE}/database"

    if [ ! -d "${DATA_DIR}" ]; then
        fail "PostgreSQL data directory '${DATA_DIR}' does not exist. Is this a fresh install? If so, just start with PG 16 directly."
    fi

    # Check available disk space (need roughly 3x the data directory size for dump + backup + new data)
    # Note: du on a large PG data dir can take several minutes and may fail (e.g. permissions)
    log_info "  Checking disk space (may take a few minutes for large databases)..."
    local data_size_kb
    local available_kb
    data_size_kb=$(du -sk "${DATA_DIR}" 2>/dev/null | awk '{print $1}') || data_size_kb=""

    # If host du failed (e.g. permissions; postgres often owns the dir), try from inside the container
    if [ -z "${data_size_kb}" ] || ! [ "${data_size_kb}" -gt 0 ] 2>/dev/null; then
        local pg_container
        pg_container=$(${COMPOSE_CMD} ps -q postgres 2>/dev/null || true)
        if [ -n "${pg_container}" ] && docker ps -q --no-trunc 2>/dev/null | grep -qF "${pg_container}"; then
            log_info "  Measuring data size from postgres container (host du had no access)..."
            data_size_kb=$(docker exec "${pg_container}" du -sk /var/lib/postgresql/data 2>/dev/null | awk '{print $1}') || data_size_kb=""
        fi
    fi

    available_kb=$(df -P -k "${DATA_DIR}" 2>/dev/null | tail -1 | awk '{print $4}') || available_kb=""

    if [ -z "${available_kb}" ] || ! [ "${available_kb}" -eq "${available_kb}" ] 2>/dev/null; then
        fail "Could not determine available disk space for '${DATA_DIR}'. Check permissions and that the path is a mounted filesystem."
    fi

    local needed_kb
    if [ -n "${data_size_kb}" ] && [ "${data_size_kb}" -gt 0 ] 2>/dev/null; then
        needed_kb=$((data_size_kb * 3))
        if [ "${available_kb}" -lt "${needed_kb}" ]; then
            log_warn "Low disk space detected."
            log_warn "  Data directory size: $((data_size_kb / 1024)) MB"
            log_warn "  Available space:     $((available_kb / 1024)) MB"
            log_warn "  Recommended:         $((needed_kb / 1024)) MB (3x data size for dump + backup + new data)"
            if ! confirm "Continue anyway?"; then
                fail "Aborted due to low disk space."
            fi
        fi
    else
        # du failed or returned nothing; require at least 20GB free and warn
        needed_kb=$((20 * 1024 * 1024))
        if [ "${available_kb}" -lt "${needed_kb}" ]; then
            fail "Could not measure data directory size (du failed or timed out). Available space: $((available_kb / 1024)) MB. Recommend at least 20 GB free for migration. Check permissions on ${DATA_DIR}."
        fi
        log_warn "  Could not measure data directory size; ensuring at least 20 GB free (available: $((available_kb / 1024)) MB)."
    fi

    log_info "Pre-flight checks passed."
    log_info "  Data directory: ${DATA_DIR}"
    if [ -n "${data_size_kb}" ] && [ "${data_size_kb}" -gt 0 ] 2>/dev/null; then
        log_info "  Data size:      $((data_size_kb / 1024)) MB"
    fi
    log_info "  Dump file:      ${DUMP_FILE}"
}

# -- Step 1: Verify current PG version is 12 ----------------------------------

verify_pg12() {
    log_info "Step 1: Verifying current PostgreSQL version..."

    # Ensure postgres is running with the old (PG 12) image
    local current_image
    current_image=$(docker inspect --format='{{.Config.Image}}' postgres 2>/dev/null || echo "not running")

    if [[ "${current_image}" == *"postgres:12"* ]]; then
        log_info "  Confirmed: PostgreSQL 12 is running (image: ${current_image})."
    elif [[ "${current_image}" == "not running" ]]; then
        log_warn "  PostgreSQL container is not running. Attempting to start PG 12 temporarily for the dump..."
        # Temporarily override to PG 12 image for the dump
        POSTGRES_IMAGE=postgres:12 ${COMPOSE_CMD} up -d postgres
        sleep 5

        # Wait for PG to be ready
        local retries=30
        while ! docker exec postgres pg_isready -U postgres &>/dev/null; do
            retries=$((retries - 1))
            if [ "${retries}" -le 0 ]; then
                fail "PostgreSQL 12 did not become ready in time."
            fi
            sleep 2
        done
        log_info "  PostgreSQL 12 started successfully."
    else
        log_warn "  Current image is '${current_image}', expected postgres:12."
        if ! confirm "The running PostgreSQL does not appear to be version 12. Continue anyway?"; then
            fail "Aborted: unexpected PostgreSQL version."
        fi
    fi
}

# -- Step 2: Stop application services (keep postgres running) ----------------

stop_app_services() {
    log_info "Step 2: Stopping application services (keeping postgres running for dump)..."

    # Stop all services except postgres so there are no active writers during the dump
    local services
    services=$(${COMPOSE_CMD} config --services | grep -v '^postgres$')
    if [ -n "${services}" ]; then
        # shellcheck disable=SC2086
        ${COMPOSE_CMD} stop ${services}
    fi

    # Verify all non-postgres containers are actually stopped before proceeding
    log_info "  Verifying all application containers have stopped..."
    local retries=30
    while true; do
        local still_running
        still_running=$(docker ps --filter "status=running" --format '{{.Names}}' | grep -v '^postgres$' || true)

        if [ -z "${still_running}" ]; then
            break
        fi

        retries=$((retries - 1))
        if [ "${retries}" -le 0 ]; then
            log_error "  The following containers are still running after timeout:"
            log_error "    ${still_running}"
            fail "Could not stop all application services. Stop them manually and re-run."
        fi

        log_warn "  Waiting for containers to stop: ${still_running// /, }"
        sleep 5
    done

    log_info "  All application services stopped. Only postgres is still running."
}

# -- Step 3: Dump the database ------------------------------------------------

dump_database() {
    log_info "Step 3: Creating full database dump (no active writers)..."
    log_info "  This may take a while depending on database size."

    if ! docker exec postgres pg_dumpall -U postgres > "${DUMP_FILE}"; then
        fail "pg_dumpall failed. Check PostgreSQL logs for details."
    fi

    local dump_size
    dump_size=$(du -sh "${DUMP_FILE}" | awk '{print $1}')
    log_info "  Dump completed successfully: ${DUMP_FILE} (${dump_size})"

    # Basic sanity check on the dump
    if [ ! -s "${DUMP_FILE}" ]; then
        fail "Dump file is empty. Something went wrong."
    fi

    # Check that the dump ends with expected content (pg_dumpall: "database cluster dump complete" in PG 13+; "database dump complete" in older)
    if ! tail -5 "${DUMP_FILE}" | grep -qE "PostgreSQL database (cluster )?dump complete" 2>/dev/null; then
        log_warn "  Dump file may be incomplete (missing expected footer). Proceeding anyway."
    fi
}

# -- Step 4: Stop postgres ----------------------------------------------------

stop_postgres() {
    log_info "Step 4: Stopping postgres..."
    ${COMPOSE_CMD} down
    log_info "  All services stopped."
}

# -- Step 5: Backup the old data directory ------------------------------------

backup_data_directory() {
    log_info "Step 5: Backing up PG 12 data directory..."

    local backup_dir="${DATA_DIR}_pg12_backup_${TIMESTAMP}"

    # Use mv for speed; the old data is preserved as a backup
    mv "${DATA_DIR}" "${backup_dir}"

    log_info "  Data directory moved to: ${backup_dir}"
    log_info "  You can delete this backup after verifying the migration succeeded."

    BACKUP_DIR="${backup_dir}"
}

# -- Step 6: Start PG 16 (fresh init) ----------------------------------------

start_pg16() {
    log_info "Step 6: Starting PostgreSQL 16 (fresh initialization)..."

    # Start only the postgres service so it initializes a new PG 16 data directory
    ${COMPOSE_CMD} up -d postgres

    # Wait for PG 16 to be ready
    log_info "  Waiting for PostgreSQL 16 to initialize and become ready..."
    local retries=60
    while ! docker exec postgres pg_isready -U postgres &>/dev/null; do
        retries=$((retries - 1))
        if [ "${retries}" -le 0 ]; then
            fail "PostgreSQL 16 did not become ready in time. Check logs: docker logs postgres"
        fi
        sleep 2
    done

    # Verify it's actually PG 16
    local pg_version
    pg_version=$(docker exec postgres psql -U postgres -tAc "SHOW server_version;" 2>/dev/null)
    log_info "  PostgreSQL ${pg_version} is running and ready."
}

# -- Step 7: Restore the dump ------------------------------------------------

restore_database() {
    log_info "Step 7: Restoring database dump into PostgreSQL 16..."
    log_info "  This may take a while depending on database size."

    # Restore the dump. We use -f instead of stdin redirection for better error handling.
    # Note: Some warnings about existing roles (e.g., 'postgres') are expected and harmless.
    if docker exec -i postgres psql -U postgres -f - < "${DUMP_FILE}" > /dev/null 2>&1; then
        log_info "  Restore completed successfully."
    else
        # psql may return non-zero due to harmless warnings (e.g., "role postgres already exists")
        log_warn "  Restore completed with warnings. This is usually harmless (e.g., duplicate role errors)."
        log_warn "  Review the output above if you suspect issues."
    fi
}

# -- Step 8: Sync content user password ---------------------------------------

sync_content_user_password() {
    log_info "Step 8: Syncing content user password from .env-database-content..."

    # The restore brings back roles with passwords from the dump. The app uses
    # credentials from .env-database-content, so we must set the content user's
    # password to match the current file or the content server will get 28P01.
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/.env-database-content"

    if [ -z "${POSTGRES_CONTENT_USER:-}" ] || [ -z "${POSTGRES_CONTENT_PASSWORD:-}" ]; then
        log_warn "  Could not read POSTGRES_CONTENT_USER or POSTGRES_CONTENT_PASSWORD from .env-database-content. Skipping password sync."
        return
    fi

    # Escape single quotes in password for use inside a single-quoted SQL string
    local escaped_password
    escaped_password="${POSTGRES_CONTENT_PASSWORD//\'/\'\'}"

    if docker exec postgres psql -U postgres -d postgres -c "ALTER USER \"${POSTGRES_CONTENT_USER}\" WITH PASSWORD '${escaped_password}';" 2>/dev/null; then
        log_info "  Content user '${POSTGRES_CONTENT_USER}' password synced."
    else
        log_warn "  Failed to set password for ${POSTGRES_CONTENT_USER}. The content server may fail to connect. You can run: docker exec postgres psql -U postgres -d postgres -c \"ALTER USER \\\"${POSTGRES_CONTENT_USER}\\\" WITH PASSWORD '<password>';\""
    fi
}

# -- Step 9: Fix public schema permissions for PG 16 -------------------------

fix_schema_permissions() {
    log_info "Step 9: Granting public schema permissions (required for PG 15+)..."

    # In PostgreSQL 15+, the default CREATE privilege on the public schema was
    # revoked for non-superuser roles. After restoring a PG 12 dump into PG 16,
    # we must explicitly grant CREATE on public to the content user.
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/.env-database-content"

    if [ -z "${POSTGRES_CONTENT_USER:-}" ] || [ -z "${POSTGRES_CONTENT_DB:-}" ]; then
        log_warn "  Could not determine POSTGRES_CONTENT_USER or POSTGRES_CONTENT_DB from .env-database-content."
        log_warn "  You may need to manually run: GRANT ALL ON SCHEMA public TO <content_user>;"
        return
    fi

    docker exec postgres psql -U postgres -d "${POSTGRES_CONTENT_DB}" \
        -c "GRANT ALL ON SCHEMA public TO \"${POSTGRES_CONTENT_USER}\";" 2>/dev/null

    log_info "  Granted ALL on schema public to ${POSTGRES_CONTENT_USER} in database ${POSTGRES_CONTENT_DB}."
}

# -- Step 10: Vacuum and analyze ----------------------------------------------

vacuum_analyze() {
    log_info "Step 10: Running VACUUM ANALYZE on all databases..."

    # After a dump/restore, pg_statistic (planner statistics) is empty. Without
    # stats the query planner falls back on default estimates, which can produce
    # very poor plans. VACUUM ANALYZE rebuilds visibility maps (enabling
    # index-only scans) and collects fresh statistics for every table.
    docker exec postgres psql -U postgres -d "${POSTGRES_CONTENT_DB:-content}" \
        -c "VACUUM ANALYZE;" 2>/dev/null

    log_info "  VACUUM ANALYZE completed."
}

# -- Step 11: Verify the migration --------------------------------------------

verify_migration() {
    log_info "Step 11: Verifying migration..."

    # Check PG version
    local pg_version
    pg_version=$(docker exec postgres psql -U postgres -tAc "SHOW server_version;")
    log_info "  PostgreSQL version: ${pg_version}"

    # Check that the content database exists
    local db_exists
    db_exists=$(docker exec postgres psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='content';" 2>/dev/null || echo "0")
    if [ "${db_exists// /}" = "1" ]; then
        log_info "  Content database exists: OK"
    else
        log_error "  Content database NOT FOUND. Migration may have failed."
        log_error "  You can restore from backup: mv '${BACKUP_DIR}' '${DATA_DIR}'"
        return 1
    fi

    # Ensure pg_stat_statements extension exists in content database (for monitoring/query stats)
    local ext_exists
    ext_exists=$(docker exec postgres psql -U postgres -d content -tAc "SELECT 1 FROM pg_extension WHERE extname='pg_stat_statements';" 2>/dev/null || echo "0")
    if [ "${ext_exists// /}" = "1" ]; then
        log_info "  pg_stat_statements extension: OK"
    else
        log_info "  Creating pg_stat_statements extension in content database..."
        if docker exec postgres psql -U postgres -d content -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;" 2>/dev/null; then
            log_info "  pg_stat_statements extension created."
        else
            log_warn "  Could not create pg_stat_statements in content database (optional; used for query statistics). It may be created on next postgres restart."
        fi
    fi

    # List databases for visual confirmation
    log_info "  Databases in PostgreSQL 16:"
    docker exec postgres psql -U postgres -c "\l" 2>/dev/null | head -20

    log_info "  Verification complete."
}

# -- Step 12: Start all services ----------------------------------------------

start_all_services() {
    log_info "Step 12: Starting all services..."
    ${COMPOSE_CMD} up -d
    log_info "  All services started."
}

# -- Main execution -----------------------------------------------------------

main() {
    echo "============================================================================="
    echo "  PostgreSQL 12 -> 16 Migration"
    echo "============================================================================="
    echo ""
    log_warn "This script will migrate your PostgreSQL database from version 12 to 16."
    log_warn "ALL SERVICES WILL BE STOPPED during the migration (downtime required)."
    echo ""

    if ! confirm "Do you want to proceed with the migration?"; then
        log_info "Migration cancelled."
        exit 0
    fi

    echo ""

    cd "${SCRIPT_DIR}"

    preflight_checks
    echo ""
    verify_pg12
    echo ""
    stop_app_services
    echo ""
    dump_database
    echo ""
    stop_postgres
    echo ""
    backup_data_directory
    echo ""
    start_pg16
    echo ""
    restore_database
    echo ""
    sync_content_user_password
    echo ""
    fix_schema_permissions
    echo ""
    vacuum_analyze
    echo ""
    verify_migration
    echo ""
    start_all_services

    echo ""
    echo "============================================================================="
    log_info "Migration completed successfully!"
    echo "============================================================================="
    echo ""
    log_info "Summary:"
    log_info "  - PostgreSQL upgraded from 12 to 16"
    log_info "  - Database dump saved at: ${DUMP_FILE}"
    log_info "  - Old data directory backed up at: ${BACKUP_DIR}"
    echo ""
    log_info "Next steps:"
    log_info "  1. Verify the application is working correctly"
    log_info "  2. Once confirmed, you can safely delete the backup files:"
    log_info "       rm -f '${DUMP_FILE}'"
    log_info "       rm -rf '${BACKUP_DIR}'"
    echo ""
    log_warn "If something went wrong, you can rollback by:"
    log_warn "  1. Stopping services:   ${COMPOSE_CMD} down"
    log_warn "  2. Removing new data:   rm -rf '${DATA_DIR}'"
    log_warn "  3. Restoring backup:    mv '${BACKUP_DIR}' '${DATA_DIR}'"
    log_warn "  4. Reverting image to postgres:12 in docker-compose.yml"
    log_warn "  5. Starting services:   ${COMPOSE_CMD} up -d"
}

main "$@"
