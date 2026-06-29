#!/usr/bin/env bash
#
# Demo feeder entrypoint. Two modes (FEEDER_MODE):
#   loop      (default) — wait for the tenant DB, then run agent + simulator-loop
#                         + scheduler under supervisord (continuous live feed).
#   backfill            — one-shot: start the agent, backdate ~BACKFILL_HOURS of
#                         traffic into the tenant DB, wait for the buffer to fully
#                         drain, then exit. Run this ONCE per tenant to prime the
#                         dashboard's 7d window (Coolify one-off / `compose run`).
#
set -euo pipefail

: "${NIGHTOWL_DB_HOST:?NIGHTOWL_DB_HOST required (the platform Postgres host)}"
: "${NIGHTOWL_DB_DATABASE:?NIGHTOWL_DB_DATABASE required - the tenant DB for this app}"
: "${NIGHTOWL_TOKEN:?NIGHTOWL_TOKEN required (must match agent <-> simulator)}"

MODE="${FEEDER_MODE:-loop}"
PORT="${NIGHTOWL_AGENT_PORT:-2407}"
BUFFER="/app/storage/nightowl/agent-buffer.sqlite"

# Generate an APP_KEY if none was provided, so artisan can boot. The feeder stores
# no encrypted data, so an ephemeral per-container key is fine.
if [ -z "${APP_KEY:-}" ]; then
  php /app/artisan key:generate --force >/dev/null 2>&1 || true
fi

db_ready() {
  php -r '
    try {
      new PDO(
        "pgsql:host=".getenv("NIGHTOWL_DB_HOST").";port=".(getenv("NIGHTOWL_DB_PORT") ?: "5432").";dbname=".getenv("NIGHTOWL_DB_DATABASE"),
        getenv("NIGHTOWL_DB_USERNAME"), getenv("NIGHTOWL_DB_PASSWORD"),
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
      );
    } catch (Throwable $e) { exit(1); }
  '
}

echo "[feeder] mode=${MODE} db=${NIGHTOWL_DB_DATABASE} on ${NIGHTOWL_DB_HOST}:${NIGHTOWL_DB_PORT:-5432}"
echo "[feeder] waiting for the tenant DB (created + migrated by nightowl:seed-demo-agency) ..."
for i in $(seq 1 60); do
  if db_ready; then echo "[feeder] tenant DB reachable."; break; fi
  if [ "$i" -eq 60 ]; then
    echo "[feeder] tenant DB ${NIGHTOWL_DB_DATABASE} unreachable after 120s — has nightowl:seed-demo-agency run yet? exiting." >&2
    exit 1
  fi
  sleep 2
done

if [ "$MODE" = "backfill" ]; then
  HOURS="${BACKFILL_HOURS:-72}"
  EVENTS="${BACKFILL_EVENTS:-600}"
  echo "[feeder] one-shot backfill: ${EVENTS} events across ${HOURS}h"

  php /app/artisan nightowl:agent >/tmp/feeder-agent.log 2>&1 &
  AGENT_PID=$!
  trap 'kill "$AGENT_PID" 2>/dev/null || true' EXIT

  # Wait for the agent to bind its TCP ingest.
  for _ in $(seq 1 30); do
    php -r '$c=@fsockopen("127.0.0.1",(int)(getenv("NIGHTOWL_AGENT_PORT")?:2407),$e,$s,1); exit($c?0:1);' && break
    sleep 0.5
  done

  php /app/artisan nightowl:simulator-backfill --token="$NIGHTOWL_TOKEN" --hours="$HOURS" --events="$EVENTS"

  # Wait for the SQLite buffer to fully drain so no backfilled rows are lost (two
  # consecutive zeroes to absorb the COPY -> cleanup window).
  echo -n "[feeder] draining"
  zero=0
  for _ in $(seq 1 240); do
    sleep 0.5; echo -n "."
    pend=$(php -r '
      $f = "/app/storage/nightowl/agent-buffer.sqlite";
      if (! file_exists($f)) { echo 0; exit; }
      try { $d = new PDO("sqlite:".$f); $d->setAttribute(PDO::ATTR_TIMEOUT, 2);
            echo (int) $d->query("SELECT count(*) FROM buffer WHERE synced != 1")->fetchColumn();
      } catch (Throwable $e) { echo -1; }
    ')
    if [ "$pend" = "0" ]; then zero=$((zero + 1)); [ "$zero" -ge 2 ] && break; else zero=0; fi
  done
  echo " done."
  kill "$AGENT_PID" 2>/dev/null || true; wait "$AGENT_PID" 2>/dev/null || true
  echo "[feeder] backfill complete for ${NIGHTOWL_DB_DATABASE}."
  exit 0
fi

echo "[feeder] starting continuous feed (agent + simulator-loop + scheduler)"
exec supervisord -c /etc/supervisor/feeder.conf -n
