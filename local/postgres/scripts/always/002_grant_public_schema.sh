#!/bin/bash
# PostgreSQL 15+ revoked the default CREATE privilege on the public schema for
# non-superuser roles. This script ensures the content user has the necessary
# permissions on every startup, which is especially important after migrating
# from PostgreSQL 12 to 16 (where the init scripts don't re-run).

if [ -n "$POSTGRES_CONTENT_USER" ] && [ -n "$POSTGRES_CONTENT_DB" ]; then
    psql -d "$POSTGRES_CONTENT_DB" << EOF
GRANT ALL ON SCHEMA public TO "$POSTGRES_CONTENT_USER";
EOF
fi
