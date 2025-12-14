#!/bin/bash
# NOC-Raven - Port Forwarding Management
set -e
LOG_FILE="/var/log/noc-raven/port-forwarding.log"
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
pkill -9 socat 2>/dev/null || true
sleep 1
log "Starting port forwarding services..."
socat UDP4-LISTEN:1514,bind=0.0.0.0,fork,reuseaddr UDP4:127.0.0.1:12514 &
socat UDP4-LISTEN:2055,bind=0.0.0.0,fork,reuseaddr UDP4:127.0.0.1:12055 &
socat UDP4-LISTEN:4739,bind=0.0.0.0,fork,reuseaddr UDP4:127.0.0.1:14739 &
socat UDP4-LISTEN:6343,bind=0.0.0.0,fork,reuseaddr UDP4:127.0.0.1:16343 &
socat UDP4-LISTEN:162,bind=0.0.0.0,fork,reuseaddr UDP4:127.0.0.1:10162 &
sleep 2
SOCAT_COUNT=$(ps aux | grep -c '[s]ocat UDP4-LISTEN')
log "Port forwarding processes started: $SOCAT_COUNT/5"
[ "$SOCAT_COUNT" -ge 5 ] && log "✅ All port forwarding started" || log "⚠️  Warning: Only $SOCAT_COUNT/5 running"
