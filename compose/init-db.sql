-- OneWish OS PostgreSQL Initialization
-- Creates required databases and extensions for n8n and other services

-- Create n8n database if not exists
SELECT 'CREATE DATABASE n8n' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec

-- Create extensions
\c n8n
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE n8n TO postgres;
