#!/bin/bash
# NoC Raven - Log Retention / Rotation Enforcer
# Safeguard against runaway disk usage by enforcing per-directory budgets.
# Budgets are configurable via environment variables. Defaults are conservative.
#
# Directories managed:
#   - /data/logs      (Vector sinks, flows, syslog exports)
#   - /data/metrics   (Telegraf/Vector metrics files)
#   - /data/alerts    (Vector alert files)
#   - /var/log/noc-raven (service manager and service stdout logs)
#
# Usage:
#   log-retention.sh           # run once
#   log-retention.sh --daemon  # run every 5 minutes
#
# Env overrides:
#   LOGS_MAX_MB=2048 METRICS_MAX_MB=1024 ALERTS_MAX_MB=512 VARLOG_MAX_MB=512 SLEEP_SECS=300

set -euo pipefail

LOGS_MAX_MB=${LOGS_MAX_MB:-2048}
METRICS_MAX_MB=${METRICS_MAX_MB:-1024}
ALERTS_MAX_MB=${ALERTS_MAX_MB:-512}
VARLOG_MAX_MB=${VARLOG_MAX_MB:-512}
SLEEP_SECS=${SLEEP_SECS:-300}

log() {
  echo "[$(date -Iseconds)] log-retention: $*" >> /var/log/noc-raven/log-retention.log
}

# Convert MB to bytes
mb_to_bytes() { echo $(( $1 * 1024 * 1024 )); }

# Enforce a byte budget on a directory with a filename pattern
# Args: dir pattern max_mb
enforce_budget() {
  local dir="$1" pattern="$2" max_mb="$3"
  local max_bytes; max_bytes=$(mb_to_bytes "$max_mb")
  mkdir -p "$dir" || true
  # Get file list
  mapfile -t files < <(find "$dir" -type f -name "$pattern" -printf '%T@ %s %p\n' 2>/dev/null | sort -n | awk '{print $2"\t"$3}')
  local total=0
  local -a sizes paths
  for line in "${files[@]}"; do
    sizes+=("${line%%\t*}")
    paths+=("${line#*\t}")
  done
  # Sum current usage
  for s in "${sizes[@]}"; do
    total=$(( total + s ))
  done
  if (( total <= max_bytes )); then
    log "OK: $(printf '%-18s' "$dir/$pattern") usage=$total bytes within budget $max_bytes"
    return 0
  fi
  # Reduce usage by deleting oldest files first
  local i=0
  while (( total > max_bytes && i < ${#paths[@]} )); do
    local f="${paths[$i]}"; local sz=${sizes[$i]:-0}
    if [[ -f "$f" ]]; then
      log "Deleting: $f (size=$sz) to enforce budget in $dir"
      rm -f -- "$f" || true
      total=$(( total - sz ))
    fi
    ((i++))
  done
  log "Post-clean: $(printf '%-18s' "$dir/$pattern") usage=$total bytes (budget $max_bytes)"
}

run_once() {
  enforce_budget "/data/logs"    "*.log*" "$LOGS_MAX_MB"
  enforce_budget "/data/metrics" "*.log*" "$METRICS_MAX_MB"
  enforce_budget "/data/alerts"  "*.log*" "$ALERTS_MAX_MB"
  enforce_budget "/var/log/noc-raven" "*.log" "$VARLOG_MAX_MB"
}

if [[ "${1:-}" == "--daemon" ]]; then
  log "Starting daemon mode; sleep=${SLEEP_SECS}s; budgets: logs=${LOGS_MAX_MB}MB metrics=${METRICS_MAX_MB}MB alerts=${ALERTS_MAX_MB}MB varlog=${VARLOG_MAX_MB}MB"
  while true; do
    run_once || true
    sleep "$SLEEP_SECS" || sleep 300
  done
else
  run_once
fi

