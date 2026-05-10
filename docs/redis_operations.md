# Redis Operations Guide

This guide covers how to interact with the Redis HA cluster in production.

## Connectivity

Redis is exposed via HAProxy on `db_ha_pgpool:6379`. You must use the Redis password for authentication.

### Connect from Manager
Run a one-off Redis client container on the backend network:

```bash
docker run -it --rm --network shared-backend redis:7-alpine redis-cli -h db_ha_pgpool -a "$(cat /opt/docker/stacks/database_ha/secrets/redis_password)" --no-auth-warning
```

---

## Common Key Patterns

### User Statistics (Synced from Onboarding)
Used by the Ride Service to display ratings and ride counts in real-time.
- **Key**: `user:stats:{userId}`
- **TTL**: 24 Hours
- **Type**: Hash

```bash
# Get all stats for a user
HGETALL user:stats:8

# Expected Output:
# 1) "rider_rating"
# 2) "5.0"
# 3) "rider_rides"
# 4) "0"
```

### Driver Live Locations
Used by the Bidding Engine and Map.
- **Key**: `driver:loc:{driverId}`
- **Type**: Hash

```bash
# Check driver location and current ride
HGETALL driver:loc:8
```

---

## Debugging Commands

### List All Keys
> [!WARNING]
> Use `SCAN` instead of `KEYS *` in production if there are many keys.

```bash
# Pattern match stats keys
SCAN 0 MATCH user:stats:*
```

### Check TTL (Time to Live)
```bash
TTL user:stats:8
```

### Flush Cache (Emergency Only)
```bash
# Clear all stats cache
FLUSHDB
```

### Monitor Real-time Activity
See commands as they happen (useful for verifying RabbitMQ sync):
```bash
MONITOR
```
