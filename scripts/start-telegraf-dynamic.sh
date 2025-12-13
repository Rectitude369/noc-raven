#!/bin/bash
# Start Telegraf with dynamic SNMP trap port from config.json
set -euo pipefail

CFG_JSON="/opt/noc-raven/web/api/config.json"
GEN_DIR="/opt/noc-raven/config/generated"
GEN_CONF="$GEN_DIR/telegraf-dynamic.conf"
LOG_DIR="/var/log/noc-raven"

mkdir -p "$GEN_DIR" "$LOG_DIR" /data/metrics

TRAP_PORT=162
ENABLED=true
if [ -f "$CFG_JSON" ]; then
  TRAP_PORT=$(jq -r '.collection.snmp.trap_port // 162' "$CFG_JSON" 2>/dev/null || echo 162)
  ENABLED=$(jq -r '.collection.snmp.enabled // true' "$CFG_JSON" 2>/dev/null || echo true)
fi

cat > "$GEN_CONF" <<EOF
[agent]
  interval = "30s"
  round_interval = true
  flush_interval = "30s"
  flush_jitter = "5s"

# System metrics
[[inputs.cpu]]
  percpu = true
  totalcpu = true
[[inputs.mem]]
[[inputs.system]]

# SNMP Trap receiver (dynamic) - using high port to avoid IPv6 binding
[[inputs.snmp_trap]]
  service_address = "udp://127.0.0.1:$((TRAP_PORT + 10000))"
  path = ["/data/snmp"]

# Output to file
[[outputs.file]]
  files = ["/data/metrics/telegraf-production-%Y-%m-%d.log"]
  data_format = "json"
EOF

# Start IPv4-only UDP proxy for SNMP traps using socat
socat UDP4-LISTEN:${TRAP_PORT},bind=0.0.0.0,fork UDP4:127.0.0.1:$((TRAP_PORT + 10000)) &

exec telegraf --config "$GEN_CONF"
