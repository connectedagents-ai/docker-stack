#!/bin/bash
################################################################
# PostgreSQL Multi-Database Init Script
# Robert Bailey / PowerConnection AI
# Creates multiple databases for the devstack services
################################################################

set -euo pipefail

create_database() {
    local database=$1
    echo "  Creating database: $database"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
        SELECT 'CREATE DATABASE $database'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$database')\gexec

        GRANT ALL PRIVILEGES ON DATABASE $database TO $POSTGRES_USER;
EOSQL
}

if [ -n "${POSTGRES_MULTIPLE_DATABASES:-}" ]; then
    echo "==> Creating multiple databases: $POSTGRES_MULTIPLE_DATABASES"
    for db in $(echo "$POSTGRES_MULTIPLE_DATABASES" | tr ',' ' '); do
        create_database "$db"
    done

    # Enable pgvector + uuid-ossp on each DB
    for db in $(echo "$POSTGRES_MULTIPLE_DATABASES" | tr ',' ' '); do
        echo "  Enabling pgvector in: $db"
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" <<-EOSQL
            CREATE EXTENSION IF NOT EXISTS vector;
            CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOSQL
    done

    echo "==> Multi-database initialization complete."
fi
