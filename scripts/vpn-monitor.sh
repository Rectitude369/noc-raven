#!/bin/bash
# 🦅 NoC Raven - VPN Connection Monitor
# Monitors VPN connection status and coordinates with buffer manager for failover

set -e

# Configuration
NOC_RAVEN_HOME="${NOC_RAVEN_HOME:-/opt/noc-raven}"
CONFIG_PATH="${CONFIG_PATH:-/config}"
LOG_FILE="/var/log/noc-raven/vpn-monitor.log"
PID_FILE="/var/run/noc-raven-vpn-monitor.pid"
BUFFER_MANAGER_URL="http://localhost:5005"
VPN_CHECK_INTERVAL=30
MAX_FAILURES=3
VPN_CONFIG_FILE="${CONFIG_PATH}/vpn/active.ovpn"

# VPN connection tracking
declare -g VPN_CONNECTED=false
declare -g FAILURE_COUNT=0
declare -g LAST_CHECK=0
declare -g CONNECTION_START_TIME=0
declare -g TOTAL_DOWNTIME=0

# Logging function
log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] [vpn-monitor] $*" | tee -a "$LOG_FILE"
}

# Check if VPN process is running
is_vpn_process_running() {
    if pgrep -f "openvpn.*${VPN_CONFIG_FILE}" >/dev/null 2>&1; then
        return 0
    elif pgrep -f "openvpn" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Test network connectivity through VPN
test_vpn_connectivity() {
    local target_host="${1:-obs.rectitude.net}"
    local timeout="${2:-5}"
    
    # Test DNS resolution first
    if ! nslookup "$target_host" >/dev/null 2>&1; then
        return 1
    fi
    
    # Test HTTP connectivity
    if command -v curl >/dev/null 2>&1; then
        if curl -s --max-time "$timeout" --connect-timeout "$timeout" \
           "https://$target_host/health" >/dev/null 2>&1; then
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --timeout="$timeout" --tries=1 -O /dev/null \
           "https://$target_host/health" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # Fallback to ping
    if ping -c 1 -W "$timeout" "$target_host" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Get VPN interface information
get_vpn_interface_info() {
    local interface=""
    local ip_address=""
    
    # Common VPN interface names
    for iface in tun0 tap0 ppp0 wg0; do
        if ip addr show "$iface" >/dev/null 2>&1; then
            interface="$iface"
            ip_address=$(ip addr show "$iface" | grep 'inet ' | awk '{print $2}' | head -1)
            break
        fi
    done
    
    echo "$interface,$ip_address"
}

# Calculate connection latency
measure_latency() {
    local target="${1:-obs.rectitude.net}"
    local start_time
    local end_time
    local latency
    
    start_time=$(date +%s%3N)
    
    if curl -s --max-time 5 "https://$target/health" >/dev/null 2>&1; then
        end_time=$(date +%s%3N)
        latency=$((end_time - start_time))
        echo "$latency"
    else
        echo "0"
    fi
}

# Check comprehensive VPN status
check_vpn_status() {
    local start_time
    local vpn_status="disconnected"
    local latency=0
    local interface_info
    local error_message=""
    
    start_time=$(date +%s)
    
    # Check if VPN process is running
    if ! is_vpn_process_running; then
        error_message="VPN process not running"
    # Test connectivity
    elif ! test_vpn_connectivity; then
        error_message="VPN connectivity test failed"
    else
        vpn_status="connected"
        latency=$(measure_latency)
        FAILURE_COUNT=0
        
        if [[ "$VPN_CONNECTED" != "true" ]]; then
            CONNECTION_START_TIME=$start_time
            log "INFO" "VPN connection established"
        fi
        VPN_CONNECTED=true
    fi
    
    # Handle connection failure
    if [[ "$vpn_status" == "disconnected" ]]; then
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        
        if [[ "$VPN_CONNECTED" == "true" ]]; then
            local downtime=$((start_time - CONNECTION_START_TIME))
            TOTAL_DOWNTIME=$((TOTAL_DOWNTIME + downtime))
            log "WARNING" "VPN connection lost after ${downtime}s uptime: $error_message"
        fi
        
        VPN_CONNECTED=false
        
        # Trigger reconnection after multiple failures
        if [[ $FAILURE_COUNT -ge $MAX_FAILURES ]]; then
            log "CRITICAL" "VPN failed $FAILURE_COUNT times, triggering reconnection"
            trigger_vpn_reconnection
            FAILURE_COUNT=0
        fi
    fi
    
    LAST_CHECK=$start_time
    
    # Get interface information
    interface_info=$(get_vpn_interface_info)
    local vpn_interface=$(echo "$interface_info" | cut -d',' -f1)
    local vpn_ip=$(echo "$interface_info" | cut -d',' -f2)
    
    # Create status object
    local status_json
    status_json=$(jq -n \
        --arg status "$vpn_status" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson latency "$latency" \
        --argjson failure_count "$FAILURE_COUNT" \
        --arg interface "$vpn_interface" \
        --arg ip_address "$vpn_ip" \
        --arg error "$error_message" \
        --argjson uptime "$((start_time - CONNECTION_START_TIME))" \
        --argjson total_downtime "$TOTAL_DOWNTIME" \
        '{
            status: $status,
            timestamp: $timestamp,
            latency_ms: $latency,
            failure_count: $failure_count,
            interface: $interface,
            ip_address: $ip_address,
            error_message: $error,
            uptime_seconds: $uptime,
            total_downtime_seconds: $total_downtime,
            connected: ($status == "connected")
        }')
    
    echo "$status_json"
}

# Notify buffer manager of VPN status change
notify_buffer_manager() {
    local status="$1"
    
    if ! command -v curl >/dev/null 2>&1; then
        return
    fi
    
    # Send status to buffer manager
    if ! curl -s -X POST "$BUFFER_MANAGER_URL/api/buffer/vpn/status" \
            -H "Content-Type: application/json" \
            -d "$status" >/dev/null 2>&1; then
        log "WARNING" "Failed to notify buffer manager of VPN status"
    fi
}

# Trigger VPN reconnection
trigger_vpn_reconnection() {
    log "INFO" "Triggering VPN reconnection"
    
    # Kill existing VPN processes
    if pgrep -f "openvpn" >/dev/null 2>&1; then
        pkill -f "openvpn" || true
        sleep 2
    fi
    
    # Start VPN connection if config file exists
    if [[ -f "$VPN_CONFIG_FILE" ]]; then
        log "INFO" "Starting OpenVPN with config: $VPN_CONFIG_FILE"
        nohup openvpn --config "$VPN_CONFIG_FILE" \
              --log "/var/log/noc-raven/openvpn.log" \
              --daemon >/dev/null 2>&1 &
    else
        log "ERROR" "VPN config file not found: $VPN_CONFIG_FILE"
    fi
    
    # Wait for connection to establish
    sleep 5
}

# Generate VPN statistics report
generate_vpn_report() {
    local current_time
    local total_runtime
    local uptime_percentage
    
    current_time=$(date +%s)
    total_runtime=$((current_time - $(stat -c %Y "$PID_FILE" 2>/dev/null || echo "$current_time")))
    
    if [[ $total_runtime -gt 0 ]]; then
        uptime_percentage=$(awk "BEGIN {printf \"%.2f\", (($total_runtime - $TOTAL_DOWNTIME) / $total_runtime) * 100}")
    else
        uptime_percentage="100.00"
    fi
    
    local report
    report=$(jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson connected "$VPN_CONNECTED" \
        --argjson total_runtime "$total_runtime" \
        --argjson total_downtime "$TOTAL_DOWNTIME" \
        --arg uptime_percentage "$uptime_percentage" \
        --argjson failure_count "$FAILURE_COUNT" \
        --argjson last_check "$LAST_CHECK" \
        '{
            timestamp: $timestamp,
            connected: $connected,
            total_runtime_seconds: $total_runtime,
            total_downtime_seconds: $total_downtime,
            uptime_percentage: $uptime_percentage,
            current_failure_count: $failure_count,
            last_check_timestamp: $last_check,
            monitor_status: "active"
        }')
    
    echo "$report"
}

# Main monitoring loop
monitor_vpn() {
    log "INFO" "Starting VPN monitoring (interval: ${VPN_CHECK_INTERVAL}s)"
    
    while true; do
        local vpn_status
        vpn_status=$(check_vpn_status)
        
        # Log status changes
        local connected
        connected=$(echo "$vpn_status" | jq -r '.connected')
        
        if [[ "$connected" == "true" ]]; then
            local latency
            latency=$(echo "$vpn_status" | jq -r '.latency_ms')
            log "INFO" "VPN connected (latency: ${latency}ms)"
        else
            local error
            error=$(echo "$vpn_status" | jq -r '.error_message')
            log "WARNING" "VPN disconnected: $error"
        fi
        
        # Notify buffer manager
        notify_buffer_manager "$vpn_status"
        
        # Save status to file
        echo "$vpn_status" > "/tmp/noc-raven-vpn-status.json"
        
        sleep "$VPN_CHECK_INTERVAL"
    done
}

# Handle script termination
cleanup() {
    log "INFO" "VPN monitor shutting down"
    
    if [[ -f "$PID_FILE" ]]; then
        rm -f "$PID_FILE"
    fi
    
    exit 0
}

# Set up signal handlers
trap cleanup INT TERM EXIT

# Main function
main() {
    case "${1:-monitor}" in
        "monitor")
            # Create log directory and PID file
            mkdir -p "$(dirname "$LOG_FILE")"
            echo $$ > "$PID_FILE"
            
            # Start monitoring
            monitor_vpn
            ;;
        "status")
            if [[ -f "/tmp/noc-raven-vpn-status.json" ]]; then
                cat "/tmp/noc-raven-vpn-status.json"
            else
                echo '{"error": "VPN monitor not running or status unavailable"}'
            fi
            ;;
        "report")
            generate_vpn_report
            ;;
        "reconnect")
            trigger_vpn_reconnection
            ;;
        "test")
            check_vpn_status | jq '.'
            ;;
        "stop")
            if [[ -f "$PID_FILE" ]]; then
                local pid
                pid=$(cat "$PID_FILE")
                if kill "$pid" 2>/dev/null; then
                    log "INFO" "VPN monitor stopped (PID: $pid)"
                else
                    log "WARNING" "Failed to stop VPN monitor (PID: $pid)"
                fi
            else
                log "WARNING" "VPN monitor PID file not found"
            fi
            ;;
        "help"|*)
            echo "Usage: $0 {monitor|status|report|reconnect|test|stop}"
            echo ""
            echo "Commands:"
            echo "  monitor    - Start VPN monitoring loop"
            echo "  status     - Show current VPN status"
            echo "  report     - Generate VPN statistics report"
            echo "  reconnect  - Trigger VPN reconnection"
            echo "  test       - Test VPN connection once"
            echo "  stop       - Stop VPN monitor"
            echo "  help       - Show this help message"
            ;;
    esac
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi