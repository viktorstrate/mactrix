#!/usr/bin/env bash

set -xeuo pipefail

PORT="${MATRIX_PORT:-8008}"
SERVER_NAME="${MATRIX_SERVER_NAME:-localhost}"
SERVER="${MATRIX_SERVER:-http://127.0.0.1:${PORT}}"
STATE_DIR="${STATE_DIR:-$(mktemp -d -t continuwuity-qa-XXXXXX)}"

ALICE_USER="${MATRIX_USER_ALICE:-alice}"
ALICE_PASS="${MATRIX_PASS_ALICE:-alice-password}"
BOB_USER="${MATRIX_USER_BOB:-bob}"
BOB_PASS="${MATRIX_PASS_BOB:-bob-password}"

mkdir -p "$STATE_DIR"
echo "[info] using state directory: $STATE_DIR"

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

print_server_info() {
  if [ -n "${SERVER_PID:-}" ]; then
    echo "[info] Continuwuity still running (pid $SERVER_PID, state dir $STATE_DIR)"
  fi
}
trap print_server_info EXIT

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

# Run the QA scenario.
MATRIX_SERVER="$SERVER" \
MATRIX_SERVER_NAME="$SERVER_NAME" \
  python3 "$(dirname "$0")/matrix-qa.py"
QA_EXIT=$?

exit "$QA_EXIT"
