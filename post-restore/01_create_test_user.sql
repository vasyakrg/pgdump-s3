-- Create test user with password 123123
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'testuser') THEN
        CREATE ROLE testuser WITH LOGIN PASSWORD '123123';
        RAISE NOTICE 'User testuser created';
    ELSE
        ALTER ROLE testuser WITH PASSWORD '123123';
        RAISE NOTICE 'User testuser already exists, password updated';
    END IF;
END
$$;

GRANT CONNECT ON DATABASE testdb TO testuser;
GRANT USAGE ON SCHEMA public TO testuser;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO testuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO testuser;
