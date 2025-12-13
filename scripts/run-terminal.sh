#!/usr/bin/env bash
set -euo pipefail
# Run NoC Raven in Terminal mode with the required privileges so configuration applies
# - root user for hostname/timezone, privileged ports
# - CAP_NET_ADMIN for ip/route changes inside the container namespace

IMAGE="${IMAGE:-noc-raven:test}"
NAME="${NAME:-noc-raven-term}"

# Host bind mounts for persistence
CONF_DIR="${CONF_DIR:-$PWD/.noc-raven-config}"
DATA_DIR="${DATA_DIR:-$PWD/.noc-raven-data}"
LOGS_DIR="${LOGS_DIR:-$PWD/.noc-raven-logs}"

mkdir -p "$CONF_DIR" "$DATA_DIR" "$LOGS_DIR"
chmod 0777 "$CONF_DIR" "$DATA_DIR" "$LOGS_DIR" || true

(docker rm -f "$NAME" >/dev/null 2>&1) || true

docker run -dit \
  --user 0:0 \
  --cap-add NET_ADMIN \
  --name "$NAME" \
  -p 9080:8080 -p 8084:8084 \
  -p 2055:2055/udp -p 4739:4739/udp -p 6343:6343/udp -p 162:162/udp \
  -v "$CONF_DIR:/config" \
  -v "$DATA_DIR:/data" \
  -v "$LOGS_DIR:/var/log/noc-raven" \
  "$IMAGE" --mode=terminal

echo "Container started: $NAME"
echo "Attach with:  docker attach $NAME  (detach: Ctrl-p Ctrl-q)"

