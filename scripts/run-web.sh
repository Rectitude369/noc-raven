#!/usr/bin/env bash
set -euo pipefail
# Run NoC Raven in Web mode (auto-detect DHCP) with healthy defaults
# This script uses non-root user by default; override with RUN_AS_ROOT=1 to run as root

IMAGE="${IMAGE:-noc-raven:test}"
NAME="${NAME:-noc-raven-web}"
RUN_AS_ROOT="${RUN_AS_ROOT:-0}"

CONF_DIR="${CONF_DIR:-$PWD/.noc-raven-config}"
DATA_DIR="${DATA_DIR:-$PWD/.noc-raven-data}"
LOGS_DIR="${LOGS_DIR:-$PWD/.noc-raven-logs}"

mkdir -p "$CONF_DIR" "$DATA_DIR" "$LOGS_DIR"
chmod 0777 "$CONF_DIR" "$DATA_DIR" "$LOGS_DIR" || true

(docker rm -f "$NAME" >/dev/null 2>&1) || true

ARGS=(
  -dit --name "$NAME"
  -p 9080:8080 -p 8084:8084
  -p 1514:1514/udp
  -p 2055:2055/udp -p 4739:4739/udp -p 6343:6343/udp -p 162:162/udp
  -v "$CONF_DIR:/config"
  -v "$DATA_DIR:/data"
  -v "$LOGS_DIR:/var/log/noc-raven"
)

if [[ "$RUN_AS_ROOT" == "1" ]]; then
  ARGS+=(--user 0:0)
fi

exec docker run "${ARGS[@]}" "$IMAGE" --mode=auto

