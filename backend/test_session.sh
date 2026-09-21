#!/usr/bin/env bash
# Walk the coordinator through a full session without a phone.
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:8080}"

sid=$(curl -s -X POST "$BASE/sessions" \
  -H 'content-type: application/json' \
  -d '{"device_id":"iphone-1"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["session_id"])')

echo "session $sid"

advance() {
  local event="$1"
  local extra="${2:-}"
  echo ">> $event"
  curl -s -X POST "$BASE/sessions/$sid/advance" \
    -H 'content-type: application/json' \
    -d "{\"event\":\"$event\"$extra}" | python3 -m json.tool
}

advance device_hello
advance signed_in ', "payload": {"user_id":"u-1"}'
advance local_ready
advance task_done ', "checksum": "0xDEADBEEF", "payload": {"task_id":"t-1"}'
advance task_done ', "checksum": "0xDEADBEEF", "payload": {"task_id":"t-2"}'
advance task_done ', "checksum": "0xDEADBEEF", "payload": {"task_id":"t-3"}'
