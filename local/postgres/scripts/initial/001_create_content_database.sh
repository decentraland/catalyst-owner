#!/bin/bash

psql << EOF
CREATE USER "$POSTGRES_CONTENT_USER" WITH PASSWORD '$POSTGRES_CONTENT_PASSWORD';
CREATE DATABASE "$POSTGRES_CONTENT_DB";
GRANT ALL PRIVILEGES ON DATABASE "$POSTGRES_CONTENT_DB" TO "$POSTGRES_CONTENT_USER";
EOF

# In PostgreSQL 15+, the default CREATE privilege on the public schema was
# revoked for non-superuser roles. We must explicitly grant it so the content
# user can create tables (e.g., the migrations table).
psql -d "$POSTGRES_CONTENT_DB" << EOF
GRANT ALL ON SCHEMA public TO "$POSTGRES_CONTENT_USER";
EOF