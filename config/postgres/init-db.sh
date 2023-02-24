#!/bin/bash
set -e

# Create the 'dbdemo' database
echo "Creating database 'dbdemo'..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE dbdemo;
    GRANT ALL PRIVILEGES ON DATABASE dbdemo TO $POSTGRES_USER;
EOSQL

# Create a user with the same name as the database
echo "Creating user 'dbdemo'..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE USER dbdemo WITH PASSWORD '$POSTGRES_PASSWORD';
    GRANT ALL PRIVILEGES ON DATABASE dbdemo TO dbdemo;
EOSQL

echo "Database initialization complete!"
