# NightOwl demo feeders (Coolify)

Three continuous `agent + simulator-loop` containers that keep the public Tier-1
demo (`demo.usenightowl.com`) populated — one per demo tenant DB. Built from this
app via `Dockerfile`; deployed as a Coolify **Docker Compose** resource on the same
box as the API + platform Postgres.

## Topology (no new database)

`SeedDemoAgency` creates the three tenant DBs **inside the existing platform
Postgres** (`nightowl_demo_nw_web`, `nightowl_demo_nw_api`, `nightowl_demo_delta`)
and migrates them. The demo account lives in `nightowl_platform`. So there is **no
new Postgres** — the feeders just drain into the platform Postgres, one database
each.

```
demo.usenightowl.com (Vercel SPA, demo mode)
   └─ /demo/* ─▶ nightowl-api ─reads─▶ nightowl_demo_{nw_web,nw_api,delta}  (in nightowl_platform Postgres)
                                              ▲ drain (COPY)
                 feeder-nw-web / feeder-nw-api / feeder-delta   (this compose)
                   each: agent (loopback 2407) + simulator-loop + scheduler(prune)
```

## Deploy sequence (order matters)

1. **Seed** (on the `nightowl-api` container):
   ```
   php artisan nightowl:seed-demo-agency        # creates the 3 tenant DBs + account; prints the two IDs
   ```
2. **Set API env + redeploy** `nightowl-api`:
   ```
   NIGHTOWL_DEMO_USER_ID=<printed>   NIGHTOWL_DEMO_APP_ID=<printed>
   ```
3. **Prime the 7d window** — run each feeder once in backfill mode (Coolify one-off
   command, or locally `docker compose run --rm -e FEEDER_MODE=backfill feeder-nw-web`,
   then `feeder-nw-api`, `feeder-delta`). Skippable, but the dashboard looks sparse
   until live data accrues without it.
4. **Workflow issue + client report** (on `nightowl-api`):
   ```
   php artisan nightowl:seed-demo-agency --post-feed
   ```
5. **Start the compose** — the three feeders run continuously.

## Required env (Coolify Compose resource)

| Var | Value |
|-----|-------|
| `DEMO_PG_HOST` | the platform Postgres internal hostname |
| `DEMO_PG_PASS` | the platform Postgres password |
| `DEMO_PG_PORT` / `DEMO_PG_USER` | default `5432` / `nightowl` |
| `FEED_TOKEN` | any string (frames agent↔simulator only; not a platform token) |

## Networking

The tenant DBs are in the platform Postgres, so attach this stack to that Postgres's
Coolify network (Compose → *Connect to Predefined Network* → the platform Postgres
network) and set `DEMO_PG_HOST` to its internal hostname. Agent ports
(`2407/2408/2409`) stay inside each container — never published.

## Notes

- `NIGHTOWL_HEALTH_REPORT_ENABLED=false` on the feeders so they don't overwrite the
  curated varied health/vitals seeded by `seed-demo-agency`.
- Raw telemetry is pruned to ~6h (`routes/console.php`), so demo **lists** show recent
  activity and **charts** stay full from rollups.
- The image re-resolves `nightowl/agent` from its GitHub VCS repo at build time (the
  local `../nightowl-agent` path repo isn't in the build context). **Build-test it
  once** (`docker build .`) before wiring Coolify — it hasn't been built here.
