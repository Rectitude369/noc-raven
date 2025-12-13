#!/bin/bash
# 🦅 NoC Raven - Enhanced Health Check System
# Comprehensive monitoring of all telemetry services, endpoints, and system health

set -e

# Configuration
NOC_RAVEN_HOME="${NOC_RAVEN_HOME:-/opt/noc-raven}"
CONFIG_PATH="${CONFIG_PATH:-/config}"
DATA_PATH="${DATA_PATH:-/data}"
LOG_FILE="/var/log/noc-raven/health-check.log"
STATUS_FILE="/tmp/noc-raven-health-status.json"
ALERT_THRESHOLD_CPU=85
ALERT_THRESHOLD_MEMORY=90
ALERT_THRESHOLD_DISK=80

# Service definitions
declare -A SERVICES=(
    ["nginx"]="Web Interface"
    ["config-service"]="Configuration API"
    ["buffer-manager"]="Buffer Management"
    ["vector"]="Event Processing"
    ["fluent-bit"]="Syslog Collection"
    ["goflow2"]="Flow Collection"
    ["telegraf"]="Metrics Collection"
)

declare -A SERVICE_PORTS=(
    ["nginx"]="8080:tcp"
    ["config-service"]="5004:tcp"
    ["buffer-manager"]="5005:tcp"
    ["vector"]="8084:tcp"
    ["fluent-bit"]="514:udp"
    ["goflow2"]="2055:udp"
    ["telegraf"]="162:udp"
)

declare -A HEALTH_ENDPOINTS=(
    ["nginx"]="http://localhost:8080/health"
    ["config-service"]="http://localhost:5004/health"
    ["buffer-manager"]="http://localhost:5005/health"
    ["vector"]="http://localhost:8084/health"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] [health-check] $*" | tee -a "$LOG_FILE"
}

# Colored output function
print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "OK"|"HEALTHY")
            echo -e "${GREEN}✓${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠${NC} $message"
            ;;
        "ERROR"|"CRITICAL"|"FAILED")
            echo -e "${RED}✗${NC} $message"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ${NC} $message"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Check if process is running
is_process_running() {
    local process_name="$1"
    pgrep -f "$process_name" >/dev/null 2>&1
}

# Check if port is listening
is_port_listening() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    if [[ "$protocol" == "udp" ]]; then
        netstat -uln 2>/dev/null | grep -q ":$port "
    else
        netstat -tln 2>/dev/null | grep -q ":$port "
    fi
}

# Check HTTP endpoint health
check_http_health() {
    local url="$1"
    local timeout="${2:-5}"
    
    if command -v curl >/dev/null 2>&1; then
        if curl -s --max-time "$timeout" "$url" >/dev/null 2>&1; then
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --timeout="$timeout" --tries=1 -O /dev/null "$url" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# Get system resource usage
get_system_stats() {
    local stats="{}"
    
    # CPU usage
    if command -v top >/dev/null 2>&1; then
        local cpu_idle
        cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | sed 's/%id,//' 2>/dev/null || echo "0")
        local cpu_usage
        cpu_usage=$(awk "BEGIN {printf \"%.1f\", 100 - $cpu_idle}")
        stats=$(echo "$stats" | jq --arg cpu "$cpu_usage" '. + {cpu_usage: ($cpu | tonumber)}')
    fi
    
    # Memory usage
    if [[ -f /proc/meminfo ]]; then
        local mem_total mem_available mem_usage
        mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        mem_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || awk '/MemFree/ {print $2}' /proc/meminfo)
        mem_usage=$(awk "BEGIN {printf \"%.1f\", (($mem_total - $mem_available) / $mem_total) * 100}")
        stats=$(echo "$stats" | jq --arg mem "$mem_usage" '. + {memory_usage: ($mem | tonumber)}')
    fi
    
    # Disk usage for critical paths
    local disk_usage="{}"
    for path in "/" "/data" "/config" "/var/log"; do
        if [[ -d "$path" ]]; then
            local usage
            usage=$(df "$path" 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}' || echo "0")
            disk_usage=$(echo "$disk_usage" | jq --arg path "${path//\//_}" --arg usage "$usage" '. + {($path): ($usage | tonumber)}')
        fi
    done
    stats=$(echo "$stats" | jq --argjson disk "$disk_usage" '. + {disk_usage: $disk}')
    
    # Load average
    if [[ -f /proc/loadavg ]]; then
        local load_avg
        load_avg=$(awk '{print $1, $2, $3}' /proc/loadavg)
        stats=$(echo "$stats" | jq --arg load "$load_avg" '. + {load_average: $load}')
    fi
    
    # Network interface status
    local network_interfaces="{}"
    if command -v ip >/dev/null 2>&1; then
        while IFS= read -r interface; do
            local status
            if ip link show "$interface" 2>/dev/null | grep -q "state UP"; then
                status="up"
            else
                status="down"
            fi
            network_interfaces=$(echo "$network_interfaces" | jq --arg iface "$interface" --arg status "$status" '. + {($iface): $status}')
        done < <(ip link show | grep -E "^[0-9]:" | awk -F': ' '{print $2}' | grep -v lo)
    fi
    stats=$(echo "$stats" | jq --argjson net "$network_interfaces" '. + {network_interfaces: $net}')
    
    echo "$stats"
}

# Check individual service health
check_service_health() {
    local service="$1"
    local description="${SERVICES[$service]}"
    local health_status="OK"
    local details="{}"
    
    # Check if process is running
    local process_running=false
    if is_process_running "$service"; then
        process_running=true
        details=$(echo "$details" | jq '. + {process_status: "running"}')
    else
        process_running=false
        health_status="CRITICAL"
        details=$(echo "$details" | jq '. + {process_status: "stopped"}')
    fi
    
    # Check port binding if applicable
    if [[ -n "${SERVICE_PORTS[$service]:-}" ]]; then
        IFS=':' read -r port protocol <<< "${SERVICE_PORTS[$service]}"
        if is_port_listening "$port" "$protocol"; then
            details=$(echo "$details" | jq --arg port "$port" --arg proto "$protocol" '. + {port_status: "listening", port: ($port | tonumber), protocol: $proto}')
        else
            health_status="WARNING"
            details=$(echo "$details" | jq --arg port "$port" --arg proto "$protocol" '. + {port_status: "not_listening", port: ($port | tonumber), protocol: $proto}')
        fi
    fi
    
    # Check HTTP health endpoint if available
    if [[ -n "${HEALTH_ENDPOINTS[$service]:-}" ]]; then
        local endpoint="${HEALTH_ENDPOINTS[$service]}"
        if check_http_health "$endpoint"; then
            details=$(echo "$details" | jq --arg endpoint "$endpoint" '. + {http_health: "healthy", endpoint: $endpoint}')
        else
            if [[ "$health_status" == "OK" ]]; then
                health_status="WARNING"
            fi
            details=$(echo "$details" | jq --arg endpoint "$endpoint" '. + {http_health: "unhealthy", endpoint: $endpoint}')
        fi
    fi
    
    # Get process information
    if [[ "$process_running" == "true" ]]; then
        local pid cpu_percent mem_percent
        pid=$(pgrep -f "$service" | head -1 2>/dev/null || echo "")
        if [[ -n "$pid" ]]; then
            if command -v ps >/dev/null 2>&1; then
                read -r cpu_percent mem_percent < <(ps -p "$pid" -o %cpu,%mem --no-headers 2>/dev/null || echo "0.0 0.0")
                details=$(echo "$details" | jq --arg pid "$pid" --arg cpu "$cpu_percent" --arg mem "$mem_percent" '. + {pid: ($pid | tonumber), cpu_percent: ($cpu | tonumber), memory_percent: ($mem | tonumber)}')
            fi
        fi
    fi
    
    # Service-specific checks
    case "$service" in
        "fluent-bit")
            # Check if syslog is being received
            local syslog_files=("/data/syslog/"*.log)
            if [[ -f "${syslog_files[0]}" ]]; then
                local recent_entries
                recent_entries=$(find /data/syslog -name "*.log" -mmin -5 | wc -l)
                details=$(echo "$details" | jq --arg recent "$recent_entries" '. + {recent_syslog_files: ($recent | tonumber)}')
            fi
            ;;
        "goflow2")
            # Check if flows are being processed
            local flow_files=("/data/flows/"*.log)
            if [[ -f "${flow_files[0]}" ]]; then
                local recent_flows
                recent_flows=$(find /data/flows -name "*.log" -mmin -5 | wc -l)
                details=$(echo "$details" | jq --arg recent "$recent_flows" '. + {recent_flow_files: ($recent | tonumber)}')
            fi
            ;;
        "vector")
            # Check Vector internal metrics
            if check_http_health "http://localhost:8084/metrics"; then
                details=$(echo "$details" | jq '. + {metrics_endpoint: "available"}')
            fi
            ;;
        "nginx")
            # Check if web interface is accessible
            if check_http_health "http://localhost:8080"; then
                details=$(echo "$details" | jq '. + {web_interface: "accessible"}')
            fi
            ;;
    esac
    
    # Build service status object
    local service_status
    service_status=$(jq -n \
        --arg service "$service" \
        --arg description "$description" \
        --arg status "$health_status" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson details "$details" \
        '{
            service: $service,
            description: $description,
            status: $status,
            timestamp: $timestamp,
            details: $details
        }')
    
    echo "$service_status"
}

# Check all services
check_all_services() {
    local all_services="{}"
    local overall_status="OK"
    
    for service in "${!SERVICES[@]}"; do
        local service_health
        service_health=$(check_service_health "$service")
        local service_status
        service_status=$(echo "$service_health" | jq -r '.status')
        
        # Update overall status
        if [[ "$service_status" == "CRITICAL" ]]; then
            overall_status="CRITICAL"
        elif [[ "$service_status" == "WARNING" && "$overall_status" != "CRITICAL" ]]; then
            overall_status="WARNING"
        fi
        
        all_services=$(echo "$all_services" | jq --argjson service "$service_health" --arg name "$service" '. + {($name): $service}')
    done
    
    # Add overall status and timestamp
    all_services=$(echo "$all_services" | jq \
        --arg overall "$overall_status" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + {overall_status: $overall, last_check: $timestamp}')
    
    echo "$all_services"
}

# Generate comprehensive health report
generate_health_report() {
    local format="${1:-json}"
    local detailed="${2:-false}"
    
    log "INFO" "Generating comprehensive health report"
    
    # Get system statistics
    local system_stats
    system_stats=$(get_system_stats)
    
    # Get service status
    local service_status
    service_status=$(check_all_services)
    
    # Combine into full report
    local health_report
    health_report=$(jq -n \
        --argjson system "$system_stats" \
        --argjson services "$service_status" \
        --arg appliance_id "noc-raven-001" \
        --arg version "1.0.0" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            appliance: {
                id: $appliance_id,
                version: $version
            },
            timestamp: $timestamp,
            system: $system,
            services: $services
        }')
    
    # Save to status file
    echo "$health_report" > "$STATUS_FILE"
    
    # Output based on format
    case "$format" in
        "json")
            if [[ "$detailed" == "true" ]]; then
                echo "$health_report" | jq '.'
            else
                echo "$health_report" | jq '{appliance, timestamp, system: {cpu_usage, memory_usage, load_average}, services: {overall_status, last_check}}'
            fi
            ;;
        "text"|"human")
            print_text_report "$health_report"
            ;;
        "prometheus")
            print_prometheus_metrics "$health_report"
            ;;
    esac
}

# Print human-readable text report
print_text_report() {
    local health_data="$1"
    
    echo
    echo "🦅 NoC Raven Health Status Report"
    echo "=================================="
    echo "Timestamp: $(echo "$health_data" | jq -r '.timestamp')"
    echo "Appliance: $(echo "$health_data" | jq -r '.appliance.id') v$(echo "$health_data" | jq -r '.appliance.version')"
    echo
    
    # System status
    echo "📊 System Resources:"
    local cpu_usage memory_usage load_avg
    cpu_usage=$(echo "$health_data" | jq -r '.system.cpu_usage // "N/A"')
    memory_usage=$(echo "$health_data" | jq -r '.system.memory_usage // "N/A"')
    load_avg=$(echo "$health_data" | jq -r '.system.load_average // "N/A"')
    
    if [[ "$cpu_usage" != "N/A" ]]; then
        if (( $(echo "$cpu_usage > $ALERT_THRESHOLD_CPU" | bc -l) )); then
            print_status "WARNING" "CPU Usage: ${cpu_usage}% (threshold: ${ALERT_THRESHOLD_CPU}%)"
        else
            print_status "OK" "CPU Usage: ${cpu_usage}%"
        fi
    fi
    
    if [[ "$memory_usage" != "N/A" ]]; then
        if (( $(echo "$memory_usage > $ALERT_THRESHOLD_MEMORY" | bc -l) )); then
            print_status "WARNING" "Memory Usage: ${memory_usage}% (threshold: ${ALERT_THRESHOLD_MEMORY}%)"
        else
            print_status "OK" "Memory Usage: ${memory_usage}%"
        fi
    fi
    
    if [[ "$load_avg" != "N/A" ]]; then
        print_status "INFO" "Load Average: $load_avg"
    fi
    
    # Disk usage
    echo "$health_data" | jq -r '.system.disk_usage | to_entries | .[] | "  Disk " + .key + ": " + (.value | tostring) + "%"' 2>/dev/null || true
    
    echo
    echo "🔧 Service Status:"
    
    # Overall status
    local overall_status
    overall_status=$(echo "$health_data" | jq -r '.services.overall_status')
    print_status "$overall_status" "Overall Status: $overall_status"
    echo
    
    # Individual services
    for service in "${!SERVICES[@]}"; do
        local service_data
        service_data=$(echo "$health_data" | jq --arg service "$service" '.services[$service] // empty')
        
        if [[ -n "$service_data" ]]; then
            local status description
            status=$(echo "$service_data" | jq -r '.status')
            description=$(echo "$service_data" | jq -r '.description')
            
            print_status "$status" "$description ($service)"
            
            # Show additional details
            local process_status port_status
            process_status=$(echo "$service_data" | jq -r '.details.process_status // empty')
            port_status=$(echo "$service_data" | jq -r '.details.port_status // empty')
            
            if [[ -n "$process_status" ]]; then
                echo "    Process: $process_status"
            fi
            
            if [[ -n "$port_status" ]]; then
                local port protocol
                port=$(echo "$service_data" | jq -r '.details.port // empty')
                protocol=$(echo "$service_data" | jq -r '.details.protocol // empty')
                echo "    Port: $port_status ($port/$protocol)"
            fi
        fi
    done
    
    echo
}

# Print Prometheus-compatible metrics
print_prometheus_metrics() {
    local health_data="$1"
    local timestamp
    timestamp=$(date +%s000)  # Prometheus expects milliseconds
    
    echo "# HELP noc_raven_system_cpu_usage System CPU usage percentage"
    echo "# TYPE noc_raven_system_cpu_usage gauge"
    echo "noc_raven_system_cpu_usage $(echo "$health_data" | jq -r '.system.cpu_usage // 0') $timestamp"
    
    echo "# HELP noc_raven_system_memory_usage System memory usage percentage"
    echo "# TYPE noc_raven_system_memory_usage gauge"
    echo "noc_raven_system_memory_usage $(echo "$health_data" | jq -r '.system.memory_usage // 0') $timestamp"
    
    echo "# HELP noc_raven_service_status Service health status (1=OK, 0.5=WARNING, 0=CRITICAL)"
    echo "# TYPE noc_raven_service_status gauge"
    
    for service in "${!SERVICES[@]}"; do
        local status_value=0
        local status
        status=$(echo "$health_data" | jq -r --arg service "$service" '.services[$service].status // "UNKNOWN"')
        
        case "$status" in
            "OK"|"HEALTHY") status_value=1 ;;
            "WARNING") status_value=0.5 ;;
            "CRITICAL"|"ERROR") status_value=0 ;;
        esac
        
        echo "noc_raven_service_status{service=\"$service\"} $status_value $timestamp"
    done
}

# Monitor continuously
monitor_continuous() {
    local interval="${1:-30}"
    local format="${2:-text}"
    
    log "INFO" "Starting continuous health monitoring (interval: ${interval}s, format: $format)"
    
    while true; do
        generate_health_report "$format" false
        sleep "$interval"
    done
}

# Send alerts for critical conditions
check_and_alert() {
    local health_report
    health_report=$(generate_health_report json false)
    
    local overall_status
    overall_status=$(echo "$health_report" | jq -r '.services.overall_status')
    
    # Check system resource thresholds
    local cpu_usage memory_usage
    cpu_usage=$(echo "$health_report" | jq -r '.system.cpu_usage // 0')
    memory_usage=$(echo "$health_report" | jq -r '.system.memory_usage // 0')
    
    local alerts=()
    
    if [[ "$overall_status" == "CRITICAL" ]]; then
        alerts+=("CRITICAL: One or more services are in critical state")
    fi
    
    if (( $(echo "$cpu_usage > $ALERT_THRESHOLD_CPU" | bc -l) )); then
        alerts+=("WARNING: High CPU usage: ${cpu_usage}%")
    fi
    
    if (( $(echo "$memory_usage > $ALERT_THRESHOLD_MEMORY" | bc -l) )); then
        alerts+=("WARNING: High memory usage: ${memory_usage}%")
    fi
    
    # Send alerts if any exist
    if [[ ${#alerts[@]} -gt 0 ]]; then
        for alert in "${alerts[@]}"; do
            log "ALERT" "$alert"
            # Here you could integrate with external alerting systems
            # send_to_alertmanager "$alert"
            # send_email_alert "$alert"
            # send_slack_notification "$alert"
        done
    fi
}

# Main function
main() {
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case "${1:-status}" in
        "status"|"check")
            generate_health_report "${2:-text}" "${3:-false}"
            ;;
        "services")
            check_all_services | jq '.'
            ;;
        "system")
            get_system_stats | jq '.'
            ;;
        "monitor")
            monitor_continuous "${2:-30}" "${3:-text}"
            ;;
        "alert")
            check_and_alert
            ;;
        "prometheus")
            generate_health_report "prometheus"
            ;;
        "json")
            generate_health_report "json" "${2:-false}"
            ;;
        "help"|*)
            echo "Usage: $0 {status|services|system|monitor|alert|prometheus|json} [options]"
            echo ""
            echo "Commands:"
            echo "  status [format] [detailed]   - Show current health status (format: text|json, detailed: true|false)"
            echo "  services                     - Show service status only"
            echo "  system                       - Show system statistics only"
            echo "  monitor [interval] [format]  - Continuous monitoring (interval in seconds, format: text|json)"
            echo "  alert                        - Check for alert conditions"
            echo "  prometheus                   - Output Prometheus-compatible metrics"
            echo "  json [detailed]              - JSON output (detailed: true|false)"
            echo "  help                         - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 status text false         # Brief text status"
            echo "  $0 json true                 # Detailed JSON report"
            echo "  $0 monitor 60 json           # Monitor every 60 seconds with JSON output"
            echo "  $0 prometheus                # Prometheus metrics"
            ;;
    esac
}

# Handle script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi