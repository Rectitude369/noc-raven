#!/usr/bin/env bash
# NoC Raven E2E test for restart endpoints via nginx
set -euo pipefail

CONTAINER_NAME=${NOC_RAVEN_CONTAINER:-noc-raven-latest}
BASE_URL=${NOC_RAVEN_BASE_URL:-http://localhost:9080}

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }
info() { echo "[INFO] $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

require_cmd curl

# 1) GET /api/config should return JSON 200
info "Checking /api/config"
HDR=$(mktemp)
if ! curl -sS -D "$HDR" "$BASE_URL/api/config" -o /dev/null; then
  fail "/api/config request failed"
fi
if ! grep -q "HTTP/1.1 200" "$HDR"; then
  fail "/api/config did not return 200"
fi
pass "/api/config returned 200"

# 2) Restart endpoints should return 200 with success
SERVICES=(fluent-bit vector goflow2 telegraf)
for svc in "${SERVICES[@]}"; do
  info "Restarting service: $svc"
  RESP=$(curl -sS -X POST "$BASE_URL/api/services/$svc/restart") || fail "curl failed for $svc"
  echo "$RESP" | grep -q '"success": true' || fail "Service $svc restart did not indicate success"
  pass "$svc restart returned success"
  sleep 1
done

# 3) Optional: verify via container that ports are bound
if command -v docker >/dev/null 2>&1; then
  info "Verifying listening ports inside container $CONTAINER_NAME"
  docker exec "$CONTAINER_NAME" /bin/sh -lc 'ss -tulpn | grep -E ":(8080|8084|2055|4739|6343|162|514) "' >/dev/null 2>&1 \
    && pass "Ports are bound as expected" \
    || info "Port verification skipped or not all ports bound (non-fatal)"
fi

pass "E2E restart test completed successfully"

