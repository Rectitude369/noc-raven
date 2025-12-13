#!/bin/bash
# Start Fluent Bit with dynamic syslog port from config.json
set -euo pipefail

CFG_JSON="/opt/noc-raven/web/api/config.json"
GEN_DIR="/opt/noc-raven/config/generated"
GEN_CONF="$GEN_DIR/fluent-bit-dynamic.conf"
LOG_DIR="/var/log/noc-raven"

mkdir -p "$GEN_DIR" "$LOG_DIR"

# Defaults
SYS_PORT=514
BIND_ADDR="0.0.0.0"
PROTO="udp"
ENABLED=true

# Parse JSON if available
if [ -f "$CFG_JSON" ]; then
  SYS_PORT=$(jq -r '.collection.syslog.port // 514' "$CFG_JSON" 2>/dev/null || echo 514)
  BIND_ADDR=$(jq -r '.collection.syslog.bind_address // "0.0.0.0"' "$CFG_JSON" 2>/dev/null || echo "0.0.0.0")
  PROTO=$(jq -r '.collection.syslog.protocol // "UDP"' "$CFG_JSON" 2>/dev/null | tr 'A-Z' 'a-z' || echo udp)
  ENABLED=$(jq -r '.collection.syslog.enabled // true' "$CFG_JSON" 2>/dev/null || echo true)
fi

# If disabled, run a minimal dummy config to keep process healthy
if [ "$ENABLED" != "true" ]; then
  cat > "$GEN_CONF" <<EOF
[SERVICE]
    Flush         5
    Daemon        Off
    Log_Level     info

[INPUT]
    Name          dummy
    Tag           syslog.disabled
    Dummy         {"message": "syslog disabled"}
    Rate          60

[OUTPUT]
    Name          stdout
    Match         *
EOF
  exec fluent-bit -c "$GEN_CONF"
fi

# Use IPv4-only binding with socat proxy (like goflow2)
# fluent-bit binds to localhost high port, socat handles external IPv4 traffic
INTERNAL_PORT=$((11000 + SYS_PORT))

# Start socat IPv4 proxy in background
echo "Starting IPv4-only socat proxy: $SYS_PORT -> 127.0.0.1:$INTERNAL_PORT"
socat UDP4-LISTEN:$SYS_PORT,bind=0.0.0.0,fork UDP4:127.0.0.1:$INTERNAL_PORT &
SOCAT_PID=$!

# Generate syslog input config with localhost binding
cat > "$GEN_CONF" <<EOF
[SERVICE]
    Flush         5
    Daemon        Off
    Log_Level     info
    Parsers_File  /opt/noc-raven/config/parsers.conf

[INPUT]
    Name          syslog
    Mode          $PROTO
    Listen        127.0.0.1
    Port          $INTERNAL_PORT
    Parser        syslog-rfc3164-custom
    Buffer_Chunk_Size 32KB
    Buffer_Max_Size   2MB
    Tag           syslog.udp
    Mem_Buf_Limit 100MB

# Fallback parser filter to handle cases where the input plugin parser is not applied
[FILTER]
    Name          parser
    Match         syslog.*
    Key_Name      message
    Parser        syslog-rfc3164-custom
    Reserve_Data  On
    Preserve_Key  On

# Send to buffer service for forwarding
[OUTPUT]
    Name          http
    Match         syslog.*
    Host          127.0.0.1
    Port          5005
    URI           /api/v1/ingest/syslog
    Format        json
    json_date_key timestamp
    json_date_format iso8601
    Retry_Limit   False

# Local file storage for telemetry data
[OUTPUT]
    Name          file
    Match         syslog.*
    Path          /data/syslog/
    File          production-syslog.log
EOF

# Cleanup function
cleanup() {
    echo "Cleaning up socat proxy (PID: $SOCAT_PID)"
    kill $SOCAT_PID 2>/dev/null || true
    exit 0
}
trap cleanup TERM INT

exec fluent-bit -c "$GEN_CONF"
