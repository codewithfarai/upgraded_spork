# Database Operations

## SSH to DB Nodes

```bash
# From your local machine, SSH via bastion to DB nodes
# (adjust node number: db-prod-1, db-prod-2, etc.)
ssh provision@upgraded-spork-db-prod-2
```

## Access PostgreSQL

```bash
# List running containers
sudo docker ps --format '{{.Names}}' | grep pg

# Exec into the Patroni/Spilo container
sudo docker exec -it $(sudo docker ps -q -f name=db_ha_pg-) bash

# Switch to postgres user and open psql
su - postgres -c "psql"

# Or connect directly to a specific database (no pager)
su - postgres -c "PAGER=cat psql -d onboarding"
```

## Useful psql Commands

```sql
-- List databases
\l

-- Connect to a database
\c onboarding

-- List tables
\dt

-- Describe a table's columns
\d user_profiles

-- List users/roles
\du

-- Exit psql
\q
```

## Onboarding Database

```sql
\c onboarding

-- Tables: alembic_version, driver_details, user_profiles

-- View profiles
SELECT * FROM user_profiles LIMIT 10;
SELECT count(*) FROM user_profiles;

-- View driver details
SELECT * FROM driver_details LIMIT 10;
SELECT count(*) FROM driver_details;

-- Wipe all profile data (keeps schema + migrations)
TRUNCATE driver_details, user_profiles CASCADE;

-- Delete a specific user profile
DELETE FROM user_profiles WHERE authentik_user_id = '<id>';
```

## Authentik Database

```sql
\c authentik

-- View users
SELECT username, email, name FROM authentik_core_user;

-- Count users
SELECT count(*) FROM authentik_core_user;
```

## Redis (OTP Store)

```bash
# Check Redis containers
sudo docker ps | grep redis

# View Redis logs
sudo docker logs $(sudo docker ps -q -f name=redis-1) --tail 20
```

## RabbitMQ

```bash
# Check RabbitMQ containers
sudo docker ps | grep rabbitmq

# View RabbitMQ logs
sudo docker logs $(sudo docker ps -q -f name=rabbitmq-1) --tail 20
```

## Exit Sequence

1. `q` — exit the pager (if stuck at `(END)`)
2. `\q` — exit psql
3. `exit` — exit postgres user / container bash
4. `exit` — exit SSH session
