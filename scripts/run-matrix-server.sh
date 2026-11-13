#!/usr/bin/env bash

set -xeuo pipefail

PORT="${MATRIX_PORT:-8008}"
SERVER_NAME="${MATRIX_SERVER_NAME:-localhost}"
SERVER="${MATRIX_SERVER:-http://127.0.0.1:${PORT}}"
STATE_DIR="${STATE_DIR:-$(mktemp -d -t continuwuity-qa-XXXXXX)}"
PID_FILE="${MATRIX_PID_FILE:-$STATE_DIR/conduwuit.pid}"

ALICE_USER="${MATRIX_USER_ALICE:-alice}"
ALICE_PASS="${MATRIX_PASS_ALICE:-alice-password}"
BOB_USER="${MATRIX_USER_BOB:-bob}"
BOB_PASS="${MATRIX_PASS_BOB:-bob-password}"

mkdir -p "$STATE_DIR"

if ! command -v conduwuit >/dev/null 2>&1; then
  echo "[error] conduwuit not found in PATH. A nix-shell provides matrix-continuwuity if needed." >&2
  exit 1
fi

LOG_FILE="$STATE_DIR/conduwuit.log"
conduwuit \
  -O "port=$PORT" \
  -O "server_name=\"$SERVER_NAME\"" \
  -O "database_path=\"$STATE_DIR/db\"" \
  -O "allow_registration=true" \
  --execute "users create-user $ALICE_USER $ALICE_PASS" \
  --execute "users create-user $BOB_USER $BOB_PASS" \
  > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

echo "$SERVER_PID" > "$PID_FILE"
echo "[info] server pid $SERVER_PID written to $PID_FILE"

cleanup() {
  if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "[info] stopping Continuwuity (pid $SERVER_PID)"
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
}
trap cleanup EXIT

# Wait for the server to finish executing admin commands and start listening.
for _ in $(seq 1 60); do
  if curl -fs "$SERVER/_matrix/client/versions" >/dev/null 2>&1; then
    echo "[info] Continuwuity ready at $SERVER"
    break
  fi
  sleep 1
done

if ! curl -fs "$SERVER/_matrix/client/versions" >/dev/null 2>&1; then
  echo "[error] Continuwuity did not become ready in time" >&2
  exit 1
fi

echo "[info] press Ctrl-C to stop the server"

wait "$SERVER_PID"
