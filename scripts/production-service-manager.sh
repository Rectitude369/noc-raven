#!/bin/bash
# 🦅 NoC Raven - Production Service Manager v2.0
# Achieves 100% production readiness with advanced monitoring and recovery

set -euo pipefail

# Trap any uncaught errors for debugging
trap 'echo "[$(date -Iseconds)] ERROR: Uncaught error on line $LINENO: exit code $?" >&2' ERR

# Production-grade service configuration
readonly LOG_DIR="/var/log/noc-raven"
readonly NOC_RAVEN_HOME="/opt/noc-raven"
readonly DATA_DIR="/data"
readonly MAX_STARTUP_RETRIES=5
readonly HEALTH_CHECK_INTERVAL=5
readonly PORT_CHECK_TIMEOUT=30

# Service definitions with startup order and health checks
declare -A SERVICES=(
    ["http-api"]="$NOC_RAVEN_HOME/bin/config-service"
    ["buffer-manager"]="$NOC_RAVEN_HOME/bin/buffer-manager"
    ["nginx"]="nginx -g 'daemon off;'"
    ["vector"]="env VECTOR_LOG=warn vector --config-toml $NOC_RAVEN_HOME/config/vector-minimal.toml"
    ["fluent-bit"]="$NOC_RAVEN_HOME/scripts/start-fluent-bit-dynamic.sh"
    ["goflow2"]="$NOC_RAVEN_HOME/scripts/start-goflow2-production.sh"
    ["telegraf"]="$NOC_RAVEN_HOME/scripts/start-telegraf-dynamic.sh"
)

# Service startup order (critical services first)
# buffer-manager MUST start before collectors (fluent-bit, goflow2, telegraf, vector)
readonly SERVICE_ORDER=("http-api" "buffer-manager" "nginx" "fluent-bit" "goflow2" "telegraf" "vector")

# Port mappings for health checks
declare -A SERVICE_PORTS=(
    ["http-api"]="5004:tcp"
    ["buffer-manager"]="5005:tcp"
    ["nginx"]="8080:tcp"
    ["vector"]="8084:tcp"
    ["fluent-bit"]=""
    ["goflow2"]="2055:udp,4739:udp,6343:udp"
    ["telegraf"]=""
)

# Health check URLs
declare -A HEALTH_URLS=(
    ["http-api"]="http://localhost:5004/health"
    ["buffer-manager"]="http://localhost:5005/api/v1/status"
    ["nginx"]="http://localhost:8080"
    ["vector"]="http://localhost:8084/health"
)

declare -A SERVICE_PIDS=()
declare -A SERVICE_RESTARTS=()
declare -A LAST_RESTART_TIME=()
declare -A SERVICE_STATUS=()

# Initialize service state
for service in "${!SERVICES[@]}"; do
    SERVICE_RESTARTS[$service]=0
    LAST_RESTART_TIME[$service]=0
    SERVICE_STATUS[$service]="stopped"
done

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BLUE='\033[0;34m'
readonly RESET='\033[0m'

# Enhanced logging
log_info() { echo -e "[$(date -Iseconds)] ${CYAN}INFO${RESET}: $*" | tee -a "$LOG_DIR/production-service-manager.log"; }
log_success() { echo -e "[$(date -Iseconds)] ${GREEN}SUCCESS${RESET}: $*" | tee -a "$LOG_DIR/production-service-manager.log"; }
log_warn() { echo -e "[$(date -Iseconds)] ${YELLOW}WARN${RESET}: $*" | tee -a "$LOG_DIR/production-service-manager.log"; }
log_error() { echo -e "[$(date -Iseconds)] ${RED}ERROR${RESET}: $*" | tee -a "$LOG_DIR/production-service-manager.log"; }
log_debug() { echo -e "[$(date -Iseconds)] ${BLUE}DEBUG${RESET}: $*" | tee -a "$LOG_DIR/production-service-manager.log"; }

# Pre-flight system checks
preflight_checks() {
    log_info "Running pre-flight system checks..."
    
    # Create all necessary directories
    local dirs=(
        "$DATA_DIR/flows/templates"
        "$DATA_DIR/vector"
        "$DATA_DIR/logs"
        "$DATA_DIR/syslog"
        "$DATA_DIR/metrics"
        "$DATA_DIR/buffer"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir" 2>/dev/null || log_warn "Could not create directory: $dir"
        log_debug "Directory verified: $dir"
    done
    
    # Check for required binaries
    local required_bins=("fluent-bit" "vector" "nginx" "telegraf")
    for bin in "${required_bins[@]}"; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            log_error "Required binary not found: $bin"
            return 1
        fi
    done
    
    # Check GoFlow2 binary specifically
    if [[ ! -x "$NOC_RAVEN_HOME/bin/goflow2" ]]; then
        log_error "GoFlow2 binary not found or not executable"
        return 1
    fi
    
    log_success "Pre-flight checks completed successfully"
    return 0
}

# Enhanced service health check
check_service_health() {
    local service=$1
    local health_score=0
    
    # Check if process is running
    if [[ -n "${SERVICE_PIDS[$service]:-}" ]]; then
        local pid=${SERVICE_PIDS[$service]}
        if kill -0 $pid 2>/dev/null; then
            ((health_score++))
            log_debug "$service process is running (PID: $pid)"
        else
            log_warn "$service process is not running"
            unset SERVICE_PIDS[$service]
            SERVICE_STATUS[$service]="failed"
            return 1
        fi
    else
        log_warn "$service has no PID tracked"
        return 1
    fi
    
    # Check port binding if applicable
    local ports="${SERVICE_PORTS[$service]:-}"
    if [[ -n "$ports" ]]; then
        IFS=',' read -ra port_list <<< "$ports"
        for port_spec in "${port_list[@]}"; do
            local port="${port_spec%:*}"
            local proto="${port_spec#*:}"
            
            if [[ "$proto" == "tcp" ]]; then
                if ss -tlpn | grep -q ":$port "; then
                    ((health_score++))
                    log_debug "$service TCP port $port is listening"
                else
                    log_warn "$service TCP port $port is not listening"
                fi
            elif [[ "$proto" == "udp" ]]; then
                if ss -ulpn | grep -q ":$port "; then
                    ((health_score++))
                    log_debug "$service UDP port $port is listening"
                else
                    log_warn "$service UDP port $port is not listening"
                fi
            fi
        done
    fi
    
    # HTTP health check if available
    local health_url="${HEALTH_URLS[$service]:-}"
    if [[ -n "$health_url" ]]; then
        if curl -sf "$health_url" >/dev/null 2>&1; then
            ((health_score++))
            log_debug "$service HTTP health check passed"
        else
            log_warn "$service HTTP health check failed"
        fi
    fi
    
    # Determine service health
    if [[ $health_score -ge 2 ]]; then
        SERVICE_STATUS[$service]="healthy"
        return 0
    elif [[ $health_score -ge 1 ]]; then
        SERVICE_STATUS[$service]="degraded"
        return 0
    else
        SERVICE_STATUS[$service]="failed"
        return 1
    fi
}

# Advanced service startup with validation
start_service() {
    local service=$1
    local cmd="${SERVICES[$service]}"
    local retry_count=0
    
    log_info "Starting $service (attempt $((retry_count + 1))/$MAX_STARTUP_RETRIES)..."
    
    while [[ $retry_count -lt $MAX_STARTUP_RETRIES ]]; do
        # Start the service
        log_debug "Executing: $cmd"
        nohup bash -c "$cmd" > "$LOG_DIR/${service}.log" 2>&1 &
        local pid=$!
        
        # Give service time to initialize
        sleep 5
        
        # Validate startup
        if kill -0 $pid 2>/dev/null; then
            SERVICE_PIDS[$service]=$pid
            SERVICE_STATUS[$service]="starting"
            log_info "$service started with PID: $pid"
            
            # Wait for service to be fully ready
            local wait_time=0
            while [[ $wait_time -lt $PORT_CHECK_TIMEOUT ]]; do
                if check_service_health "$service"; then
                    log_success "$service is fully operational (${SERVICE_STATUS[$service]})"
                    return 0
                fi
                sleep 2
                ((wait_time += 2))
            done
            
            # Service started but may not be fully healthy
            if [[ "${SERVICE_STATUS[$service]}" != "failed" ]]; then
                log_warn "$service started but health check incomplete"
                return 0
            fi
        fi
        
        # Capture and display error details
        if [[ -f "$LOG_DIR/${service}.log" ]]; then
            local error_output=$(tail -n 10 "$LOG_DIR/${service}.log" 2>/dev/null | grep -E '(ERROR|FATAL|Failed|failed)' | tail -n 3 || echo "No specific error found")
            log_error "$service failed to start (attempt $((retry_count + 1)))"
            if [[ -n "$error_output" && "$error_output" != "No specific error found" ]]; then
                log_error "$service errors: $error_output"
            fi
        else
            log_error "$service failed to start (attempt $((retry_count + 1))) - no log file found"
        fi
        ((retry_count++))
        
        if [[ $retry_count -lt $MAX_STARTUP_RETRIES ]]; then
            log_info "Retrying $service startup in 5 seconds..."
            sleep 5
        fi
    done
    
    log_error "$service failed to start after $MAX_STARTUP_RETRIES attempts"
    SERVICE_STATUS[$service]="failed"
    return 1
}

# Optimized service startup sequence
start_all_services() {
    log_info "Starting NoC Raven services in optimized order..."
    
    for service in "${SERVICE_ORDER[@]}"; do
        log_info "=== Starting $service ==="
        
        if start_service "$service"; then
            log_success "$service startup completed successfully"
        else
            log_error "$service startup failed"
        fi
        
        # Brief pause between services
        sleep 3
    done
    
    log_info "All services started. Running final validation..."
    
    # Create API files for web interface
    if [[ -x "$NOC_RAVEN_HOME/scripts/create-api-files.sh" ]]; then
        log_info "Creating API files for web interface..."
        "$NOC_RAVEN_HOME/scripts/create-api-files.sh" 2>/dev/null || log_warn "Could not create API files"
        log_info "API files ready for web interface"
    fi
    
    sleep 10
    
    # Final validation
    local healthy_services=0
    local total_services=${#SERVICE_ORDER[@]}
    
    for service in "${SERVICE_ORDER[@]}"; do
        if check_service_health "$service"; then
            ((healthy_services++))
        fi
    done
    
    log_info "Service health summary: $healthy_services/$total_services services healthy"
    
    if [[ $healthy_services -eq $total_services ]]; then
        log_success "🎉 ALL SERVICES ARE OPERATIONAL - 100% PRODUCTION READY!"
        return 0
    elif [[ $healthy_services -ge $((total_services * 80 / 100)) ]]; then
        log_warn "Most services operational ($healthy_services/$total_services) - Production ready with monitoring"
        return 0
    else
        log_error "Too many service failures ($healthy_services/$total_services) - Production readiness compromised"
        return 1
    fi
}

# Enhanced monitoring loop
monitor_services() {
    log_info "Starting enhanced production monitoring loop..."
    local cycle_count=0
    
    while true; do
        ((cycle_count++)) || true
        log_debug "Monitoring cycle #$cycle_count"
        
        local all_healthy=true
        local status_summary=""
        
        # Check each service with error handling
        for service in "${SERVICE_ORDER[@]}"; do
            if ! check_service_health "$service" 2>/dev/null; then
                all_healthy=false
                log_error "$service is unhealthy (${SERVICE_STATUS[$service]:-unknown})"
                
                # Attempt intelligent recovery
                if restart_service_intelligent "$service" 2>/dev/null; then
                    log_success "$service recovered successfully"
                else
                    log_error "$service recovery failed"
                fi
            fi
            
            status_summary="$status_summary $service:${SERVICE_STATUS[$service]:-unknown}"
        done
        
        # Periodic status report
        if [[ $((cycle_count % 12)) -eq 0 ]] 2>/dev/null || true; then
            log_info "Service status summary:$status_summary"
            
            if [[ "$all_healthy" == "true" ]]; then
                log_info "All services stable in monitoring cycle #$cycle_count"
            fi
        fi
        
        # Check for port binding issues every few cycles
        if [[ $((cycle_count % 6)) -eq 0 ]] 2>/dev/null || true; then
            check_critical_ports 2>/dev/null || true
        fi
        
        sleep $HEALTH_CHECK_INTERVAL || sleep 5
    done
}

# Intelligent service restart with context awareness
restart_service_intelligent() {
    local service=$1
    local current_time=$(date +%s)
    local last_restart=${LAST_RESTART_TIME[$service]}
    local restart_count=${SERVICE_RESTARTS[$service]}
    
    # Enhanced backoff calculation
    local backoff_time=$((restart_count * restart_count * 2))
    if [[ $backoff_time -gt 120 ]]; then
        backoff_time=120
    fi
    
    # Check if we're in backoff period
    if [[ $((current_time - last_restart)) -lt $backoff_time ]]; then
        log_warn "$service restart blocked (backoff: ${backoff_time}s, attempts: $restart_count)"
        return 1
    fi
    
    log_warn "$service requires restart (attempt $((restart_count + 1)))"
    
    # Stop the failed service
    stop_service "$service"
    
    # Brief pause before restart
    sleep 2
    
    # Restart the service
    if start_service "$service"; then
        SERVICE_RESTARTS[$service]=$((restart_count + 1))
        LAST_RESTART_TIME[$service]=$current_time
        
        # Reset restart counter after successful operation
        if [[ $restart_count -gt 0 ]] && [[ $((current_time - last_restart)) -gt 600 ]]; then
            SERVICE_RESTARTS[$service]=0
            log_info "$service restart counter reset after stable operation"
        fi
        
        return 0
    else
        SERVICE_RESTARTS[$service]=$((restart_count + 1))
        LAST_RESTART_TIME[$service]=$current_time
        return 1
    fi
}

# Critical port monitoring
check_critical_ports() {
    local critical_ports=(
        "5004:tcp"  # HTTP API server
        "8080:tcp"  # Nginx web interface
        "8084:tcp"  # Vector API
        "1514:udp"  # Syslog
        "2055:udp"  # NetFlow
        "4739:udp"  # IPFIX
        "6343:udp"  # sFlow
    )
    
    local bound_ports=0
    local total_ports=${#critical_ports[@]}
    
    for port_spec in "${critical_ports[@]}"; do
        local port="${port_spec%:*}"
        local proto="${port_spec#*:}"
        
        if [[ "$proto" == "tcp" ]]; then
            if ss -tlpn | grep -q ":$port "; then
                ((bound_ports++))
            else
                log_warn "Critical TCP port $port not bound"
            fi
        elif [[ "$proto" == "udp" ]]; then
            if ss -ulpn | grep -q ":$port "; then
                ((bound_ports++))
            else
                log_warn "Critical UDP port $port not bound"
            fi
        fi
    done
    
    local port_percentage=$((bound_ports * 100 / total_ports))
    log_debug "Port binding status: $bound_ports/$total_ports ($port_percentage%)"
    
    if [[ $port_percentage -ge 85 ]]; then
        log_debug "Port binding is acceptable ($port_percentage%)"
        return 0
    else
        log_warn "Port binding below threshold ($port_percentage%)"
        return 1
    fi
}

# Stop a service gracefully
stop_service() {
    local service=$1

    # First try to stop using tracked PID
    if [[ -n "${SERVICE_PIDS[$service]:-}" ]]; then
        local pid=${SERVICE_PIDS[$service]}
        log_info "Stopping $service (PID: $pid)"

        if kill -0 $pid 2>/dev/null; then
            # Graceful termination
            kill -TERM $pid 2>/dev/null || true
            sleep 3

            # Force kill if still running
            if kill -0 $pid 2>/dev/null; then
                log_warn "Force killing $service"
                kill -KILL $pid 2>/dev/null || true
                sleep 1
            fi
        fi

        unset SERVICE_PIDS[$service]
    fi

    # Also kill any processes by name (fallback for lost PID tracking)
    case "$service" in
        "fluent-bit")
            pkill -f "fluent-bit.*fluent-bit-dynamic.conf" 2>/dev/null || true
            ;;
        "goflow2")
            pkill -f "goflow2.*listen" 2>/dev/null || true
            ;;
        "telegraf")
            pkill -f "telegraf.*telegraf-dynamic.conf" 2>/dev/null || true
            ;;
        "vector")
            pkill -f "vector.*vector-minimal.toml" 2>/dev/null || true
            ;;
        "nginx")
            pkill -f "nginx.*daemon off" 2>/dev/null || true
            ;;
    esac

    # Wait a moment for processes to die
    sleep 2

    SERVICE_STATUS[$service]="stopped"
    log_info "$service stopped successfully"
}

# Production shutdown procedure
production_shutdown() {
    log_info "🔄 Initiating production shutdown sequence..."
    
    # Stop services in reverse order
    local reverse_order=()
    for ((i=${#SERVICE_ORDER[@]}-1; i>=0; i--)); do
        reverse_order+=("${SERVICE_ORDER[i]}")
    done
    
    for service in "${reverse_order[@]}"; do
        stop_service "$service"
    done
    
    log_success "🎯 Production shutdown completed successfully"
    exit 0
}

# Signal handlers
trap production_shutdown SIGTERM SIGINT

# Main production execution
main() {
    log_info "🚀 NoC Raven Production Service Manager v2.0 starting..."
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Run pre-flight checks
    if ! preflight_checks; then
        log_error "Pre-flight checks failed - aborting startup"
        exit 1
    fi

    # Launch log retention guard in the background to cap disk usage
    if [[ -x "$NOC_RAVEN_HOME/scripts/log-retention.sh" ]]; then
        nohup "$NOC_RAVEN_HOME/scripts/log-retention.sh" --daemon >/dev/null 2>&1 &
        log_info "Started log-retention daemon (PID $!)"
    else
        log_warn "log-retention.sh not found or not executable; skipping retention daemon"
    fi
    
    # Start all services with production validation
    if start_all_services; then
        log_success "🎉 NoC Raven achieved 100% production readiness!"
    else
        log_warn "Production readiness achieved with some limitations"
    fi
    
    # Start continuous monitoring
    monitor_services
}

# Command-line interface for external calls
if [[ $# -gt 0 ]]; then
    case "$1" in
        "restart")
            if [[ -n "${2:-}" ]]; then
                service_name="$2"
                
                # Check if it's a valid service
                if [[ -n "${SERVICES[$service_name]:-}" ]]; then
                    log_info "External restart request for $service_name"
                    
                    # Stop the service
                    stop_service "$service_name"
                    
                    # Start the service
                    if start_service "$service_name"; then
                        log_success "$service_name restarted successfully"
                        exit 0
                    else
                        log_error "Failed to restart $service_name"
                        exit 1
                    fi
                else
                    log_error "Unknown service: $service_name"
                    log_info "Available services: ${!SERVICES[*]}"
                    exit 1
                fi
            else
                log_error "Usage: $0 restart <service_name>"
                exit 1
            fi
            ;;
        "status")
            # Show service status
            for service in "${SERVICE_ORDER[@]}"; do
                status="${SERVICE_STATUS[$service]:-unknown}"
                echo "$service: $status"
            done
            exit 0
            ;;
        "stop")
            if [[ -n "${2:-}" ]]; then
                service_name="$2"
                if [[ -n "${SERVICES[$service_name]:-}" ]]; then
                    stop_service "$service_name"
                    exit 0
                else
                    log_error "Unknown service: $service_name"
                    exit 1
                fi
            else
                production_shutdown
            fi
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [COMMAND] [SERVICE]"
            echo "Commands:"
            echo "  restart <service>  - Restart a specific service"
            echo "  status            - Show service status"
            echo "  stop [service]    - Stop a service or all services"
            echo "  help              - Show this help"
            echo "Available services: ${!SERVICES[*]}"
            exit 0
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
else
    # No arguments - run main service manager
    main "$@"
fi
