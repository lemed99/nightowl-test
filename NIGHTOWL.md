# NightOwl Test App

A Laravel 12 app that both **generates** telemetry (via `laravel/nightwatch` on every route hit) and **hosts** the `nightowl-agent` package — matching a real self-hosted customer deployment.

## Architecture — how this matches production

This project plays the role of the **customer** in a real BYOD (Bring Your Own Database) deployment:

- The customer runs their Laravel app and installs `nightowl-agent` as a package.
- The customer owns a PostgreSQL **server**. They decide whether nightowl telemetry tables live in the same DB as their app or in a dedicated DB on the same server — NightOwl only requires the credentials.
- The customer later hands those credentials to the centrally hosted **nightowl-api** SaaS, which connects into the customer's PG as a tenant and powers the dashboard UI.

So in this test project, PostgreSQL running in `nightowl-agent/docker-compose.yml` represents the **customer's PG server**. Two databases live on it, both customer-owned:

| DB                          | Purpose                                    | Connection name |
|-----------------------------|--------------------------------------------|-----------------|
| `nightowl_test`             | Test app's own tables (`users`, `jobs`, `sessions`, `cache`) | `pgsql` (default) |
| `nightowl_test_telemetry`   | Telemetry drained by the agent (`nightowl_*`) | `nightowl` (registered by agent SP) |

Splitting them isn't required — the customer could put them in the same DB — but it's what most ops teams would do and it keeps schemas tidy.

## One-time setup

```bash
# 1. Customer's PG server (from nightowl-agent/)
cd ../nightowl-agent && docker compose up -d

# 2. Create both customer-owned databases
docker exec nightowl-agent-postgres-1 psql -U nightowl -d postgres \
  -c "CREATE DATABASE nightowl_test OWNER nightowl; \
      CREATE DATABASE nightowl_test_telemetry OWNER nightowl;"

# 3. App tables → nightowl_test
#    --path is REQUIRED: the agent service provider registers its migrations
#    globally, so a bare `migrate` would dump nightowl_* into the app DB too.
cd ../nightowl-test
php artisan migrate --path=database/migrations
php artisan db:seed

# 4. Telemetry tables → nightowl_test_telemetry (via the `nightowl` connection)
php artisan migrate --database=nightowl --path=vendor/nightowl/agent/database/migrations
```

The `nightowl` PG connection is auto-registered by the agent service provider; no extra config needed. `.env` already has:

```
NIGHTOWL_TOKEN=<seeded-agent-token>     # matches connected_apps.agent_token_hash
NIGHTWATCH_ENABLED=true                 # required for the Nightwatch SDK to instrument
```

The agent's service provider hijacks Nightwatch's ingest, so `NIGHTWATCH_INGEST_URI` and `NIGHTWATCH_TOKEN` aren't needed.

## Running

One command boots everything (web, queue, agent, scheduler, log tail) via `concurrently`:

```bash
composer dev
```

Output streams are colour-coded by process name: `web`, `queue`, `agent`, `schedule`, `logs`. Ctrl+C kills the whole group.

Make sure the customer's PG server is up first:

```bash
cd ../nightowl-agent && docker compose up -d
```

If you want to run a single process manually instead:

```bash
php artisan nightowl:agent           # TCP ingest on :2407, drain to telemetry DB
php artisan queue:work --tries=1     # so DemoJob actually runs
php artisan serve --port=8001        # test app
php artisan schedule:work            # triggers nightowl-test:demo every minute
```

Then hit the demo endpoints:

```bash
curl http://localhost:8001/demo            # route list
curl http://localhost:8001/demo/users
curl http://localhost:8001/demo/slow
curl http://localhost:8001/demo/boom
curl http://localhost:8001/demo/handled
curl http://localhost:8001/demo/cache
curl http://localhost:8001/demo/job
curl http://localhost:8001/demo/mail
curl http://localhost:8001/demo/notify
curl http://localhost:8001/demo/http
curl http://localhost:8001/demo/log
curl http://localhost:8001/demo/n-plus-one
```

Inspect what landed in the telemetry DB:

```bash
docker exec nightowl-agent-postgres-1 \
  psql -U nightowl -d nightowl_test_telemetry -c "
    SELECT 'requests' t, COUNT(*) FROM nightowl_requests
    UNION ALL SELECT 'queries', COUNT(*) FROM nightowl_queries
    UNION ALL SELECT 'exceptions', COUNT(*) FROM nightowl_exceptions
    UNION ALL SELECT 'cache', COUNT(*) FROM nightowl_cache_events
    UNION ALL SELECT 'jobs', COUNT(*) FROM nightowl_jobs
    UNION ALL SELECT 'mail', COUNT(*) FROM nightowl_mail
    UNION ALL SELECT 'notifications', COUNT(*) FROM nightowl_notifications
    UNION ALL SELECT 'outgoing', COUNT(*) FROM nightowl_outgoing_requests
    UNION ALL SELECT 'logs', COUNT(*) FROM nightowl_logs;"
```

## Telemetry coverage

| Endpoint            | Records emitted                          |
|---------------------|------------------------------------------|
| `GET /demo/users`   | request, query                           |
| `GET /demo/slow`    | request (slow), query                    |
| `GET /demo/boom`    | request, exception (unhandled)           |
| `GET /demo/handled` | request, exception (handled)             |
| `GET /demo/cache`   | request, cache_event ×4                  |
| `GET /demo/job`     | request, job (processed or failed)       |
| `GET /demo/mail`    | request, mail                            |
| `GET /demo/notify`  | request, notification, mail              |
| `GET /demo/http`    | request, outgoing_request                |
| `GET /demo/log`     | request, log ×4                          |
| `GET /demo/n-plus-one` | request, query ×N                     |
| `php artisan nightowl-test:demo` | command, query, cache, log, job |
| scheduler `nightowl-demo-heartbeat` | scheduled_task, command       |

## Health endpoint

```bash
curl http://127.0.0.1:2409/status | jq
```

## Load generation

```bash
for i in {1..50}; do curl -s http://localhost:8001/demo/users > /dev/null; done

printf '%s\n' users slow cache http log handled n-plus-one | \
  xargs -I{} -P 4 curl -s "http://localhost:8001/demo/{}" -o /dev/null
```

## Reset

```bash
# Wipe telemetry only
php artisan nightowl:clear

# Full telemetry DB reset
docker exec nightowl-agent-postgres-1 psql -U nightowl -d postgres -c "DROP DATABASE nightowl_test_telemetry WITH (FORCE);"
docker exec nightowl-agent-postgres-1 psql -U nightowl -d postgres -c "CREATE DATABASE nightowl_test_telemetry OWNER nightowl;"
php artisan migrate --database=nightowl --path=vendor/nightowl/agent/database/migrations
```
