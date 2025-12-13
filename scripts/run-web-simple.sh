#!/usr/bin/env bash
set -euo pipefail
# Simple web deployment without VPN complications

IMAGE="${IMAGE:-noc-raven:test}"
NAME="${NAME:-noc-raven-simple}"

CONF_DIR="${CONF_DIR:-$PWD/.noc-raven-config}"
DATA_DIR="${DATA_DIR:-$PWD/.noc-raven-data}"
LOGS_DIR="${LOGS_DIR:-$PWD/.noc-raven-logs}"

mkdir -p "$CONF_DIR" "$DATA_DIR" "$LOGS_DIR"
chmod 0777 "$CONF_DIR" "$DATA_DIR" "$LOGS_DIR" || true

# Create empty VPN config to skip VPN setup
mkdir -p "$CONF_DIR/vpn"
touch "$CONF_DIR/vpn/SKIP_VPN"

(docker rm -f "$NAME" >/dev/null 2>&1) || true

exec docker run -d --name "$NAME" \
  -p 9080:8080 -p 8084:8084 \
  -p 1514:1514/udp \
  -p 2055:2055/udp -p 4739:4739/udp -p 6343:6343/udp -p 162:162/udp \
  -v "$CONF_DIR:/config" \
  -v "$DATA_DIR:/data" \
  -v "$LOGS_DIR:/var/log/noc-raven" \
  "$IMAGE" --mode=web