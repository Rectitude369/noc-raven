#!/bin/bash
# 🦅 NoC Raven - Service Restart Manager
# Reliable service restart mechanism without supervisorctl dependencies

set -euo pipefail

# Configuration
readonly NOC_RAVEN_HOME="${NOC_RAVEN_HOME:-/opt/noc-raven}"
readonly LOG_DIR="/var/log/noc-raven"
readonly PID_DIR="/var/run/noc-raven"
readonly MAX_RESTART_TIME=30
readonly RESTART_TIMEOUT=45

# Service definitions with proper commands
declare -A SERVICES=(
    ["fluent-bit"]="fluent-bit -c $NOC_RAVEN_HOME/config/fluent-bit.conf"
    ["goflow2"]="$NOC_RAVEN_HOME/bin/goflow2 -config $NOC_RAVEN_HOME/config/goflow2.yml"
    ["telegraf"]="telegraf --config $NOC_RAVEN_HOME/config/telegraf.conf"
    ["vector"]="vector --config-toml $NOC_RAVEN_HOME/config/vector.toml"
    ["nginx"]="nginx -g 'daemon off;'"
    ["config-service"]="$NOC_RAVEN_HOME/bin/config-service"
)

# Service aliases for API compatibility
declare -A SERVICE_ALIASES=(
    ["syslog"]="fluent-bit"
    ["fluentbit"]="fluent-bit"
    ["netflow"]="goflow2"
    ["snmp"]="telegraf"
    ["windows"]="vector"
    ["win-events"]="vector"
    ["http-api"]="config-service"
    ["api"]="config-service"
)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

# Logging functions
log_info() { echo -e "[$(date -Iseconds)] ${CYAN}INFO${RESET}: $*" | tee -a "$LOG_DIR/service-restart.log"; }
log_success() { echo -e "[$(date -Iseconds)] ${GREEN}SUCCESS${RESET}: $*" | tee -a "$LOG_DIR/service-restart.log"; }
log_warn() { echo -e "[$(date -Iseconds)] ${YELLOW}WARN${RESET}: $*" | tee -a "$LOG_DIR/service-restart.log"; }
log_error() { echo -e "[$(date -Iseconds)] ${RED}ERROR${RESET}: $*" | tee -a "$LOG_DIR/service-restart.log"; }

# Initialize directories
init_directories() {
    # Create directories with proper permissions
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    mkdir -p "$PID_DIR" 2>/dev/null || {
        # If we can't create /var/run/noc-raven, use /tmp
        PID_DIR="/tmp/noc-raven-pids"
        mkdir -p "$PID_DIR"
    }
    touch "$LOG_DIR/service-restart.log" 2>/dev/null || true
}

# Resolve service name (handle aliases)
resolve_service_name() {
    local service_name="$1"
    
    # Check if it's an alias
    if [[ -n "${SERVICE_ALIASES[$service_name]:-}" ]]; then
        echo "${SERVICE_ALIASES[$service_name]}"
        return 0
    fi
    
    # Check if it's a valid service
    if [[ -n "${SERVICES[$service_name]:-}" ]]; then
        echo "$service_name"
        return 0
    fi
    
    return 1
}

# Get service PID
get_service_pid() {
    local service="$1"
    local pid_file="$PID_DIR/${service}.pid"

    # Check PID file first
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        else
            rm -f "$pid_file" 2>/dev/null || true
        fi
    fi

    # Try to find PID by process name - be more specific
    local cmd="${SERVICES[$service]}"
    local binary=$(echo "$cmd" | awk '{print $1}' | xargs basename)

    # Look for the process with more specific matching
    local pids
    case "$service" in
        "goflow2")
            # Look for goflow2 specifically
            pids=$(pgrep -f "goflow2.*config.*goflow2.yml" 2>/dev/null || echo "")
            ;;
        "fluent-bit")
            # Look for fluent-bit with config
            pids=$(pgrep -f "fluent-bit.*fluent-bit.conf" 2>/dev/null || echo "")
            ;;
        "telegraf")
            # Look for telegraf with config
            pids=$(pgrep -f "telegraf.*telegraf.conf" 2>/dev/null || echo "")
            ;;
        "vector")
            # Look for vector with config
            pids=$(pgrep -f "vector.*vector.toml" 2>/dev/null || echo "")
            ;;
        "nginx")
            # Look for nginx master process
            pids=$(pgrep -f "nginx.*master" 2>/dev/null || echo "")
            ;;
        "config-service")
            # Look for config-service
            pids=$(pgrep -f "config-service" 2>/dev/null || echo "")
            ;;
        *)
            # Generic fallback
            pids=$(pgrep -f "$binary" 2>/dev/null || echo "")
            ;;
    esac

    if [[ -n "$pids" ]]; then
        local pid=$(echo "$pids" | head -1)
        echo "$pid" > "$pid_file" 2>/dev/null || true
        echo "$pid"
        return 0
    fi

    return 1
}

# Stop service gracefully
stop_service() {
    local service="$1"
    local timeout="${2:-10}"

    log_info "Stopping $service..."

    # Get all PIDs for this service (there might be multiple)
    local pids
    case "$service" in
        "goflow2")
            pids=$(pgrep -f "goflow2" 2>/dev/null || echo "")
            ;;
        "fluent-bit")
            pids=$(pgrep -f "fluent-bit" 2>/dev/null || echo "")
            ;;
        "telegraf")
            pids=$(pgrep -f "telegraf" 2>/dev/null || echo "")
            ;;
        "vector")
            pids=$(pgrep -f "vector" 2>/dev/null || echo "")
            ;;
        "nginx")
            pids=$(pgrep -f "nginx" 2>/dev/null || echo "")
            ;;
        "config-service")
            pids=$(pgrep -f "config-service" 2>/dev/null || echo "")
            ;;
        *)
            local cmd="${SERVICES[$service]}"
            local binary=$(echo "$cmd" | awk '{print $1}' | xargs basename)
            pids=$(pgrep -f "$binary" 2>/dev/null || echo "")
            ;;
    esac

    if [[ -z "$pids" ]]; then
        log_info "$service is not running"
        rm -f "$PID_DIR/${service}.pid" 2>/dev/null || true
        return 0
    fi

    log_info "Found $service running with PIDs: $pids"

    # Stop all processes for this service
    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            log_debug "Stopping $service process (PID: $pid)"

            # Try graceful shutdown first
            if kill -TERM "$pid" 2>/dev/null; then
                log_debug "Sent SIGTERM to $service (PID: $pid)"

                # Wait for graceful shutdown
                local count=0
                while [[ $count -lt $timeout ]] && kill -0 "$pid" 2>/dev/null; do
                    sleep 1
                    ((count++))
                done

                # Force kill if still running
                if kill -0 "$pid" 2>/dev/null; then
                    log_warn "$service (PID: $pid) did not stop gracefully, forcing shutdown"
                    kill -KILL "$pid" 2>/dev/null || true
                    sleep 1
                fi
            fi
        fi
    done

    # Clean up PID file
    rm -f "$PID_DIR/${service}.pid" 2>/dev/null || true

    # Wait a moment for cleanup
    sleep 2

    # Verify service is stopped by checking for remaining processes
    local remaining_pids
    case "$service" in
        "goflow2")
            remaining_pids=$(pgrep -f "goflow2" 2>/dev/null || echo "")
            ;;
        "fluent-bit")
            remaining_pids=$(pgrep -f "fluent-bit" 2>/dev/null || echo "")
            ;;
        "telegraf")
            remaining_pids=$(pgrep -f "telegraf" 2>/dev/null || echo "")
            ;;
        "vector")
            remaining_pids=$(pgrep -f "vector" 2>/dev/null || echo "")
            ;;
        "nginx")
            remaining_pids=$(pgrep -f "nginx" 2>/dev/null || echo "")
            ;;
        "config-service")
            remaining_pids=$(pgrep -f "config-service" 2>/dev/null || echo "")
            ;;
        *)
            local cmd="${SERVICES[$service]}"
            local binary=$(echo "$cmd" | awk '{print $1}' | xargs basename)
            remaining_pids=$(pgrep -f "$binary" 2>/dev/null || echo "")
            ;;
    esac

    if [[ -n "$remaining_pids" ]]; then
        log_error "Failed to stop $service completely (remaining PIDs: $remaining_pids)"
        return 1
    fi

    log_success "$service stopped successfully"
    return 0
}

# Start service
start_service() {
    local service="$1"
    local cmd="${SERVICES[$service]}"
    
    log_info "Starting $service..."
    log_info "Command: $cmd"
    
    # Check if already running
    if get_service_pid "$service" >/dev/null; then
        log_warn "$service is already running"
        return 0
    fi
    
    # Start the service in background
    nohup bash -c "$cmd" > "$LOG_DIR/${service}.log" 2>&1 &
    local pid=$!
    
    # Save PID
    echo "$pid" > "$PID_DIR/${service}.pid"
    
    # Give it time to start
    sleep 3
    
    # Verify it started
    if kill -0 "$pid" 2>/dev/null; then
        log_success "$service started successfully (PID $pid)"
        return 0
    else
        log_error "$service failed to start"
        rm -f "$PID_DIR/${service}.pid"
        
        # Show error details
        if [[ -f "$LOG_DIR/${service}.log" ]]; then
            local errors=$(tail -n 5 "$LOG_DIR/${service}.log" | grep -i error || echo "No specific errors found")
            log_error "$service startup errors: $errors"
        fi
        
        return 1
    fi
}

# Restart service with timeout
restart_service() {
    local service_input="$1"
    local timeout="${2:-$RESTART_TIMEOUT}"
    
    # Resolve service name
    local service
    if ! service=$(resolve_service_name "$service_input"); then
        log_error "Unknown service: $service_input"
        log_info "Available services: ${!SERVICES[*]}"
        log_info "Available aliases: ${!SERVICE_ALIASES[*]}"
        return 1
    fi
    
    log_info "Restarting $service (resolved from $service_input)..."
    
    # Use timeout to prevent hanging
    if timeout "$timeout" bash -c "
        # Stop the service
        if ! $(declare -f stop_service); stop_service '$service' 10; then
            echo 'Failed to stop $service' >&2
            exit 1
        fi
        
        # Brief pause
        sleep 2
        
        # Start the service
        if ! $(declare -f start_service); start_service '$service'; then
            echo 'Failed to start $service' >&2
            exit 1
        fi
    "; then
        log_success "$service restarted successfully"
        return 0
    else
        log_error "$service restart failed or timed out after ${timeout}s"
        return 1
    fi
}

# Main function
main() {
    init_directories
    
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <service_name>"
        echo "Available services: ${!SERVICES[*]}"
        echo "Available aliases: ${!SERVICE_ALIASES[*]}"
        exit 1
    fi
    
    local service_name="$1"
    
    if restart_service "$service_name"; then
        log_success "Service restart completed successfully"
        exit 0
    else
        log_error "Service restart failed"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
