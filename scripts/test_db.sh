#!/usr/bin/env bash
# Runs the Supabase migrations and SQL tests against a throwaway Postgres.
# Uses local Postgres binaries if installed, otherwise a Docker container.
# Usage: scripts/test_db.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

PG_BIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1 || true)

if [[ -n "$PG_BIN" && -x "$PG_BIN/initdb" ]]; then
  # ---- local throwaway cluster ----
  DATA=$(mktemp -d)
  PORT=54329
  AS=()
  if [[ $(id -u) -eq 0 ]]; then
    id postgres >/dev/null 2>&1 || useradd -r postgres
    chown postgres "$DATA"
    AS=(runuser -u postgres --)
  fi
  "${AS[@]}" "$PG_BIN/initdb" -D "$DATA" -U postgres -A trust >/dev/null
  "${AS[@]}" "$PG_BIN/pg_ctl" -D "$DATA" -o "-p $PORT -k /tmp -c listen_addresses=''" -w start >/dev/null
  trap '"${AS[@]}" "$PG_BIN/pg_ctl" -D "$DATA" -m immediate stop >/dev/null 2>&1; rm -rf "$DATA"' EXIT
  PSQL=(psql -h /tmp -p "$PORT" -U postgres)
else
  # ---- docker container ----
  NAME=blackwake-test-db
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" -e POSTGRES_PASSWORD=test postgres:16-alpine >/dev/null
  trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT
  for _ in $(seq 1 30); do
    docker exec "$NAME" pg_isready -U postgres >/dev/null 2>&1 && break
    sleep 1
  done
  sleep 1
  PSQL=(docker exec -i "$NAME" psql -U postgres)
fi

run() {
  echo "→ $1"
  "${PSQL[@]}" -v ON_ERROR_STOP=1 -q -f - < "$ROOT/$1"
}

run supabase/tests/00_supabase_stub.sql
for f in supabase/migrations/*.sql; do run "$f"; done
run supabase/tests/10_game_rules_test.sql
