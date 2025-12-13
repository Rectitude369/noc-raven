#!/bin/bash

###################################################################################
# 🦅 NoC Raven - Health Check Script
# System health monitoring and validation for Docker health checks
###################################################################################

set -euo pipefail

# Configuration
readonly NOC_RAVEN_HOME="${NOC_RAVEN_HOME:-/opt/noc-raven}"
readonly DATA_PATH="${DATA_PATH:-/data}"
readonly CONFIG_PATH="${CONFIG_PATH:-/config}"
readonly HEALTH_CHECK_TIMEOUT=30

# Exit codes for Docker health check
readonly HEALTH_OK=0
readonly HEALTH_WARN=1
readonly HEALTH_CRITICAL=2

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Health check results
declare -a HEALTH_ISSUES=()
declare -a HEALTH_WARNINGS=()
declare -a HEALTH_OK_ITEMS=()

# Log function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "ERROR")   echo -e "${timestamp} [${RED}ERROR${NC}] $message" ;;
        "WARN")    echo -e "${timestamp} [${YELLOW}WARN${NC}] $message" ;;
        "INFO")    echo -e "${timestamp} [${BLUE}INFO${NC}] $message" ;;
        "SUCCESS") echo -e "${timestamp} [${GREEN}OK${NC}] $message" ;;
        *)         echo -e "${timestamp} [$level] $message" ;;
    esac
}

# Add health check result
add_health_result() {
    local status=$1
    local message=$2
    
    case $status in
        "OK")       HEALTH_OK_ITEMS+=("$message") ;;
        "WARN")     HEALTH_WARNINGS+=("$message") ;;
        "CRITICAL") HEALTH_ISSUES+=("$message") ;;
    esac
}

# Check if process is running
check_process() {
    local process_name=$1
    local description=$2
    
    if pgrep -f "$process_name" > /dev/null; then
        add_health_result "OK" "$description is running"
        return 0
    else
        add_health_result "CRITICAL" "$description is not running"
        return 1
    fi
}

# Check if port is listening
check_port() {
    local port=$1
    local description=$2
    local protocol="${3:-tcp}"
    
    if netstat -ln 2>/dev/null | grep -q ":$port "; then
        add_health_result "OK" "$description (port $port/$protocol) is listening"
        return 0
    else
        add_health_result "WARN" "$description (port $port/$protocol) is not listening"
        return 1
    fi
}

# Check disk space
check_disk_space() {
    local path=$1
    local description=$2
    local threshold_warn=${3:-85}
    local threshold_critical=${4:-95}
    
    if [[ ! -d "$path" ]]; then
        add_health_result "WARN" "$description path does not exist: $path"
        return 1
    fi
    
    local usage=$(df "$path" | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [[ $usage -ge $threshold_critical ]]; then
        add_health_result "CRITICAL" "$description disk usage critical: ${usage}%"
        return 2
    elif [[ $usage -ge $threshold_warn ]]; then
        add_health_result "WARN" "$description disk usage high: ${usage}%"
        return 1
    else
        add_health_result "OK" "$description disk usage normal: ${usage}%"
        return 0
    fi
}

# Check memory usage
check_memory() {
    local threshold_warn=${1:-80}
    local threshold_critical=${2:-90}
    
    local mem_info=$(free | grep Mem)
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    local mem_usage=$(( (mem_used * 100) / mem_total ))
    
    if [[ $mem_usage -ge $threshold_critical ]]; then
        add_health_result "CRITICAL" "Memory usage critical: ${mem_usage}%"
        return 2
    elif [[ $mem_usage -ge $threshold_warn ]]; then
        add_health_result "WARN" "Memory usage high: ${mem_usage}%"
        return 1
    else
        add_health_result "OK" "Memory usage normal: ${mem_usage}%"
        return 0
    fi
}

# Check CPU usage
check_cpu() {
    local threshold_warn=${1:-80}
    local threshold_critical=${2:-95}
    
    # Get CPU usage over 3 seconds
    local cpu_usage=$(top -bn2 -d1 | grep "Cpu(s)" | tail -1 | awk '{print $2}' | sed 's/%us,//')
    cpu_usage=${cpu_usage%.*}  # Remove decimal part
    
    if [[ $cpu_usage -ge $threshold_critical ]]; then
        add_health_result "CRITICAL" "CPU usage critical: ${cpu_usage}%"
        return 2
    elif [[ $cpu_usage -ge $threshold_warn ]]; then
        add_health_result "WARN" "CPU usage high: ${cpu_usage}%"
        return 1
    else
        add_health_result "OK" "CPU usage normal: ${cpu_usage}%"
        return 0
    fi
}

# Check file exists and is readable
check_file() {
    local file_path=$1
    local description=$2
    
    if [[ -f "$file_path" && -r "$file_path" ]]; then
        add_health_result "OK" "$description exists and is readable"
        return 0
    else
        add_health_result "WARN" "$description missing or unreadable: $file_path"
        return 1
    fi
}

# Check directory exists and is writable
check_directory() {
    local dir_path=$1
    local description=$2
    
    if [[ -d "$dir_path" && -w "$dir_path" ]]; then
        add_health_result "OK" "$description exists and is writable"
        return 0
    else
        add_health_result "CRITICAL" "$description missing or not writable: $dir_path"
        return 1
    fi
}

# Check web interface
check_web_interface() {
    local port=8080
    local timeout=5
    
    if curl -sf --max-time $timeout "http://localhost:$port" > /dev/null 2>&1; then
        add_health_result "OK" "Web interface is responding"
        return 0
    else
        add_health_result "WARN" "Web interface is not responding on port $port"
        return 1
    fi
}

# Main health check function
perform_health_check() {
    log "INFO" "Starting NoC Raven health check..."
    # Allow non-zero check functions to report WARN/CRITICAL without aborting the script
    set +e
    
    # Check essential processes (allow either supervisord or our production service manager)
    if pgrep -f "supervisord" >/dev/null 2>&1; then
        add_health_result "OK" "Supervisor daemon is running"
    elif pgrep -f "production-service-manager.sh" >/dev/null 2>&1; then
        add_health_result "OK" "Production service manager is running"
    else
        add_health_result "WARN" "No process manager detected (supervisord or production service manager)"
    fi
    check_process "goflow2" "GoFlow2 collector"
    check_process "fluent-bit" "Fluent Bit syslog processor"
    check_process "vector" "Vector data pipeline"
    check_process "telegraf" "Telegraf metrics collector"
    check_process "nginx" "Nginx web server"
    
    # Check listening ports
    check_port 514 "Syslog" "udp"
    check_port 2055 "NetFlow" "udp"
    check_port 6343 "sFlow" "udp"
    check_port 162 "SNMP Traps" "udp"
    check_port 8084 "Vector HTTP API" "tcp"
    check_port 8080 "Web Interface" "tcp"
    
    # Check system resources
    check_memory 80 90
    check_cpu 80 95
    
    # Check disk space
    check_disk_space "$DATA_PATH" "Data partition" 85 95
    check_disk_space "/var/log" "Log partition" 85 95
    check_disk_space "/" "Root partition" 90 98
    
    # Check critical directories
    check_directory "$DATA_PATH" "Data directory"
    check_directory "$CONFIG_PATH" "Config directory"
    check_directory "/var/log/noc-raven" "Log directory"
    
    # Check configuration files
    check_file "${NOC_RAVEN_HOME}/config/goflow2.yml" "GoFlow2 config"
    check_file "/etc/fluent-bit/fluent-bit.conf" "Fluent Bit config"
    check_file "/etc/vector/vector.toml" "Vector config"
    check_file "/etc/telegraf/telegraf.conf" "Telegraf config"
    check_file "/etc/nginx/nginx.conf" "Nginx config"
    
    # Check web interface (if curl is available)
    if command -v curl > /dev/null; then
        check_web_interface
    fi
}

# Display health check results
display_results() {
    echo
    log "INFO" "=== Health Check Results ==="
    
    # Display OK items
    if [[ ${#HEALTH_OK_ITEMS[@]} -gt 0 ]]; then
        echo -e "\n${GREEN}✓ Healthy Components (${#HEALTH_OK_ITEMS[@]}):${NC}"
        for item in "${HEALTH_OK_ITEMS[@]}"; do
            echo -e "  ${GREEN}✓${NC} $item"
        done
    fi
    
    # Display warnings
    if [[ ${#HEALTH_WARNINGS[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}⚠ Warnings (${#HEALTH_WARNINGS[@]}):${NC}"
        for item in "${HEALTH_WARNINGS[@]}"; do
            echo -e "  ${YELLOW}⚠${NC} $item"
        done
    fi
    
    # Display critical issues
    if [[ ${#HEALTH_ISSUES[@]} -gt 0 ]]; then
        echo -e "\n${RED}✗ Critical Issues (${#HEALTH_ISSUES[@]}):${NC}"
        for item in "${HEALTH_ISSUES[@]}"; do
            echo -e "  ${RED}✗${NC} $item"
        done
    fi
    
    echo
}

# Determine overall health status
get_health_status() {
    if [[ ${#HEALTH_ISSUES[@]} -gt 0 ]]; then
        return $HEALTH_CRITICAL
    else
        # Treat warnings as healthy for Docker healthcheck; they will still be printed
        return $HEALTH_OK
    fi
}

# Main execution
main() {
    local quiet=false
    local json_output=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quiet)
                quiet=true
                shift
                ;;
            -j|--json)
                json_output=true
                shift
                ;;
            -h|--help)
                cat << EOF
NoC Raven Health Check

Usage: $0 [OPTIONS]

Options:
    -q, --quiet     Only output summary
    -j, --json      Output results in JSON format
    -h, --help      Show this help message

Exit Codes:
    0   All checks passed
    1   Some warnings detected
    2   Critical issues detected
EOF
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Perform health check with timeout (source this script explicitly in the subshell)
    if ! timeout "$HEALTH_CHECK_TIMEOUT" bash -lc 'source "/opt/noc-raven/bin/health-check.sh"; perform_health_check'; then
        log "ERROR" "Health check failed or timed out"
        exit $HEALTH_CRITICAL
    fi
    
    # Output results
    if [[ "$json_output" == "true" ]]; then
        # JSON output for API consumption
        cat << EOF
{
  "status": "$(get_health_status && echo "healthy" || echo "unhealthy")",
  "checks": {
    "ok": ${#HEALTH_OK_ITEMS[@]},
    "warnings": ${#HEALTH_WARNINGS[@]},
    "critical": ${#HEALTH_ISSUES[@]}
  },
  "timestamp": "$(date -Iseconds)"
}
EOF
    elif [[ "$quiet" == "false" ]]; then
        display_results
    fi
    
    # Exit with appropriate code
    get_health_status
    local status=$?
    
    case $status in
        $HEALTH_OK)
            [[ "$quiet" == "false" ]] && log "SUCCESS" "🦅 NoC Raven is healthy"
            ;;
        $HEALTH_WARN)
            [[ "$quiet" == "false" ]] && log "WARN" "🦅 NoC Raven has warnings"
            ;;
        $HEALTH_CRITICAL)
            [[ "$quiet" == "false" ]] && log "ERROR" "🦅 NoC Raven has critical issues"
            ;;
    esac
    
    exit $status
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
