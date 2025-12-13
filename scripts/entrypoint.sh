#!/bin/bash
# 🦅 NoC Raven - Main Entry Point Script
# Handles DHCP detection, terminal menu vs web panel decision, and service orchestration
# This is the primary entry point for the Docker container

set -euo pipefail

# Colors for output (defined early to avoid unbound variable errors)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# Check for root privileges (conditional for container environments)
if [[ "$(id -u)" -ne 0 ]]; then
    # Check if we're in a container - if so, proceed with warning
    if [[ -f /.dockerenv ]] || [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]; then
        echo -e "${YELLOW}Warning: Running as non-root user in container environment.${RESET}" >&2
        echo -e "${YELLOW}Some network optimizations may not be available.${RESET}" >&2
    else
        echo -e "${RED}Error: This script requires root privileges for network configuration.${RESET}" >&2
        echo -e "${RED}Please run with sudo or as root user.${RESET}" >&2
        exit 1
    fi
fi

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

# Paths and directories
readonly NOC_RAVEN_HOME="/opt/noc-raven"
readonly CONFIG_DIR="/config" 
readonly DATA_DIR="/data"
readonly LOG_DIR="/var/log/noc-raven"

# Configuration files
readonly NETWORK_CONFIG="$CONFIG_DIR/network.yml"
readonly SYSTEM_CONFIG="$CONFIG_DIR/system.yml"
readonly VPN_CONFIG="$CONFIG_DIR/vpn/client.ovpn"

# Lock and state files
readonly DHCP_CHECK_FILE="/tmp/dhcp-status"
readonly CONFIG_COMPLETE_FILE="/tmp/config-complete"
readonly SERVICE_READY_FILE="/tmp/services-ready"

# Network interface (auto-detect primary interface)
detect_primary_interface() {
    # Try to find the primary network interface with an IP address
    local interface
    interface=$(ip route show default | awk '/default/ { print $5 }' | head -n1)

    if [[ -n "$interface" ]]; then
        echo "$interface"
        return 0
    fi

    # Fallback: find first interface with IP that's not loopback
    interface=$(ip addr show | awk '/^[0-9]+:/ && !/lo:/ { gsub(/:/, "", $2); iface=$2 } /inet.*scope global/ && iface { print iface; exit }')

    if [[ -n "$interface" ]]; then
        echo "$interface"
        return 0
    fi

    # Final fallback
    echo "eth0"
}

NETWORK_INTERFACE="${NETWORK_INTERFACE:-$(detect_primary_interface)}"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Ensure log directory exists before any logging
ensure_log_dir() {
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || true
        # If we can't create it, fall back to /tmp
        if [[ ! -d "$LOG_DIR" ]]; then
            LOG_DIR="/tmp/noc-raven-logs"
            mkdir -p "$LOG_DIR" 2>/dev/null || true
        fi
    fi
    # Ensure we can write to the log directory
    if [[ ! -w "$LOG_DIR" ]]; then
        LOG_DIR="/tmp/noc-raven-logs"
        mkdir -p "$LOG_DIR" 2>/dev/null || true
    fi
}

# Logging function with timestamp
log() {
    local level="$1"
    shift
    ensure_log_dir
    echo -e "[$(date -Iseconds)] [${level}] $*" | tee -a "$LOG_DIR/entrypoint.log" 2>/dev/null || echo -e "[$(date -Iseconds)] [${level}] $*"
}

# Colored logging functions
log_info() { log "INFO" "${CYAN}$*${RESET}"; }
log_warn() { log "WARN" "${YELLOW}$*${RESET}"; }
log_error() { log "ERROR" "${RED}$*${RESET}"; }
log_success() { log "SUCCESS" "${GREEN}$*${RESET}"; }

# Display NoC Raven banner
show_banner() {
    cat << 'EOF'

  ███╗   ██╗ ██████╗  ██████╗    ██████╗  █████╗ ██╗   ██╗███████╗███╗   ██╗
  ████╗  ██║██╔═══██╗██╔════╝    ██╔══██╗██╔══██╗██║   ██║██╔════╝████╗  ██║
  ██╔██╗ ██║██║   ██║██║         ██████╔╝███████║██║   ██║█████╗  ██╔██╗ ██║
  ██║╚██╗██║██║   ██║██║         ██╔══██╗██╔══██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║
  ██║ ╚████║╚██████╔╝╚██████╗    ██║  ██║██║  ██║ ╚████╔╝ ███████╗██║ ╚████║
  ╚═╝  ╚═══╝ ╚═════╝  ╚═════╝    ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝
                                                                            
         🦅 Telemetry Collection & Forwarding Appliance 🦅
           High-Performance Venue Network Monitoring

EOF
    log_info "NoC Raven v1.0.0 - Starting initialization..."
}

# Check if running in container
is_container() {
    [[ -f /.dockerenv ]] || [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]
}

# Wait for network interface to be available
wait_for_interface() {
    local interface="$1"
    local max_wait=30
    local count=0
    
    log_info "Waiting for network interface $interface..."
    
    while [[ $count -lt $max_wait ]]; do
        if ip link show "$interface" &>/dev/null; then
            log_success "Network interface $interface is available"
            return 0
        fi
        
        ((count++))
        sleep 1
    done
    
    log_error "Network interface $interface not available after ${max_wait}s"
    return 1
}

# =============================================================================
# DHCP DETECTION LOGIC
# =============================================================================

# Check if DHCP is active on interface
check_dhcp_status() {
    local interface="$1"
    local dhcp_active=false
    local has_ip=false
    
    log_info "Checking DHCP status for interface $interface..."

    # Debug: Show interface details
    log_info "Interface details:"
    ip addr show "$interface" 2>/dev/null | head -5 | while read line; do
        log_info "  $line"
    done
    
    # Check if interface has IP address
    if ip addr show "$interface" 2>/dev/null | grep -q "inet.*scope global"; then
        has_ip=true
        log_info "Interface $interface has IP address"

        # In container environments, assume DHCP if interface has IP
        if is_container; then
            dhcp_active=true
            log_info "Container environment detected - assuming DHCP active for interface with IP"
        fi

        # Also check for explicit dynamic flag
        if ip addr show "$interface" 2>/dev/null | grep -q "inet.*dynamic"; then
            dhcp_active=true
            log_info "Interface $interface has DHCP-assigned IP address (dynamic flag detected)"
        fi
    fi
    
    # Check for DHCP client processes
    if pgrep -f "dhcp.*$interface" >/dev/null 2>&1 || \
       pgrep -f "dhclient.*$interface" >/dev/null 2>&1 || \
       pgrep -f "dhcpcd.*$interface" >/dev/null 2>&1; then
        dhcp_active=true
        log_info "DHCP client process detected for $interface"
    fi
    
    # Check DHCP lease files
    for lease_file in "/var/lib/dhcp/dhclient.leases" "/var/lib/dhcpcd5/dhcpcd.leases" "/var/lib/dhcp/dhclient.${interface}.leases"; do
        if [[ -f "$lease_file" ]] && grep -q "$interface" "$lease_file" 2>/dev/null; then
            local lease_time=$(stat -c %Y "$lease_file" 2>/dev/null || echo 0)
            local current_time=$(date +%s)
            
            # Check if lease is recent (within last 5 minutes)
            if [[ $((current_time - lease_time)) -lt 300 ]]; then
                dhcp_active=true
                log_info "Recent DHCP lease found for $interface"
                break
            fi
        fi
    done
    
    # Save status for other processes
    cat > "$DHCP_CHECK_FILE" << EOF
interface=$interface
dhcp_active=$dhcp_active
has_ip=$has_ip
check_time=$(date -Iseconds)
EOF
    
    if [[ "$dhcp_active" == "true" ]]; then
        log_success "DHCP is active - will start web control panel"
        return 0
    else
        log_warn "DHCP is not active - will show terminal menu"
        return 1
    fi
}

# =============================================================================
# INITIALIZATION FUNCTIONS
# =============================================================================

# Initialize directories and permissions
init_directories() {
    log_info "Initializing directories..."
    
    # Create necessary directories
    local dirs=(
        "$LOG_DIR"
        "$DATA_DIR/syslog"
        "$DATA_DIR/flows"
        "$DATA_DIR/snmp"
        "$DATA_DIR/metrics"
        "$DATA_DIR/buffer"
        "$DATA_DIR/vector"
        "$DATA_DIR/logs"
        "$CONFIG_DIR/vpn"
        "$CONFIG_DIR/collectors"
        "$CONFIG_DIR/network"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" 2>/dev/null || {
                log_warn "Failed to create directory: $dir"
                continue
            }
            log_info "Created directory: $dir"
        fi
    done
    
    # Set proper ownership if running as root
    if [[ "$(id -u)" == "0" ]]; then
        chown -R nocraven:nocraven "$DATA_DIR" "$CONFIG_DIR" "$LOG_DIR" 2>/dev/null || true
    else
        # If running as non-root, try to fix permissions for log directory
        chmod 755 "$LOG_DIR" 2>/dev/null || true
    fi
    
    log_success "Directory initialization complete"
}

# Load environment configuration
load_environment() {
    log_info "Loading environment configuration..."
    
    # Set defaults
    export HOSTNAME="${HOSTNAME:-noc-raven-001}"
    export SITE_ID="${SITE_ID:-venue-001}"
    export PERFORMANCE_PROFILE="${PERFORMANCE_PROFILE:-balanced}"
    export BUFFER_SIZE="${BUFFER_SIZE:-100GB}"
    export WEB_PORT="${WEB_PORT:-8080}"
    
    # Load InfluxDB password if available
    if [[ -f "/run/secrets/influxdb_password" ]]; then
        export INFLUXDB_PASSWORD="$(cat /run/secrets/influxdb_password)"
    else
        export INFLUXDB_PASSWORD="${INFLUXDB_PASSWORD:-\$w33t@55T3a!}"
    fi
    
    # Set performance profile specific settings
    case "$PERFORMANCE_PROFILE" in
        "high_volume"|"stadium")
            export FLUENT_BIT_WORKERS=8
            export GOFLOW2_WORKERS=16
            export TELEGRAF_WORKERS=4
            ;;
        "convention_center")
            export FLUENT_BIT_WORKERS=6
            export GOFLOW2_WORKERS=12
            export TELEGRAF_WORKERS=3
            ;;
        "arena")
            export FLUENT_BIT_WORKERS=4
            export GOFLOW2_WORKERS=10
            export TELEGRAF_WORKERS=2
            ;;
        *)  # balanced
            export FLUENT_BIT_WORKERS=4
            export GOFLOW2_WORKERS=8
            export TELEGRAF_WORKERS=2
            ;;
    esac
    
    log_success "Environment configuration loaded (Profile: $PERFORMANCE_PROFILE)"
}

# System optimization for high performance
optimize_system() {
    log_info "Applying system optimizations..."
    
    # Network buffer optimizations (if running as root)
    if [[ "$(id -u)" == "0" ]]; then
        # Increase UDP buffer sizes
        echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf 2>/dev/null || true
        echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf 2>/dev/null || true
        echo 'net.core.rmem_default = 8388608' >> /etc/sysctl.conf 2>/dev/null || true
        echo 'net.core.wmem_default = 8388608' >> /etc/sysctl.conf 2>/dev/null || true
        echo 'net.core.netdev_max_backlog = 10000' >> /etc/sysctl.conf 2>/dev/null || true
        
        # Apply sysctl settings
        sysctl -p 2>/dev/null || log_warn "Could not apply sysctl settings"
        
        log_success "System network optimizations applied"
    else
        log_warn "Running as non-root, skipping system optimizations"
    fi
}

# =============================================================================
# VPN CONFIGURATION
# =============================================================================

# Configure OpenVPN if profile is available
setup_vpn() {
    # Skip VPN setup in web mode or if skip marker exists
    if [[ "${1:-}" == "web" ]] || [[ -f /config/vpn/SKIP_VPN ]]; then
        log_warn "VPN setup skipped in web mode"
        return 0
    fi

    # Skip VPN setup in container environments for web panel deployments
    if is_container && [[ "${1:-}" != "terminal" ]]; then
        log_warn "VPN setup skipped in container web deployment"
        return 0
    fi
    
    log_info "Setting up VPN configuration..."
    
    # Copy DRT.ovpn to expected location if not already there
    if [[ -f "/opt/noc-raven/DRT.ovpn" ]] && [[ ! -f "$VPN_CONFIG" ]]; then
        mkdir -p "$(dirname "$VPN_CONFIG")"
        cp "/opt/noc-raven/DRT.ovpn" "$VPN_CONFIG"
        log_success "Copied DRT.ovpn to expected location"
    fi
    
    # Use dedicated VPN setup script
    if [[ -x "$NOC_RAVEN_HOME/scripts/vpn-setup.sh" ]]; then
        "$NOC_RAVEN_HOME/scripts/vpn-setup.sh" start
        return $?
    fi
    
    # Fallback to inline VPN setup
    if [[ -f "$VPN_CONFIG" ]]; then
        log_success "OpenVPN configuration found: $VPN_CONFIG"
        
        # Validate VPN configuration
        if grep -q "client" "$VPN_CONFIG" && grep -q "remote" "$VPN_CONFIG"; then
            log_success "VPN configuration appears valid"
            
            # Start VPN in background with auto-restart
            if command -v supervisorctl >/dev/null 2>&1; then
                supervisorctl start openvpn &
            else
                nohup openvpn --config "$VPN_CONFIG" --daemon --log /var/log/noc-raven/openvpn.log &
            fi
            
            log_info "OpenVPN started in background"
        else
            log_error "Invalid OpenVPN configuration file"
            return 1
        fi
    else
        log_warn "No VPN configuration found at $VPN_CONFIG"
        log_warn "Telemetry will be forwarded without VPN tunnel"
    fi
}

# Wait for VPN connection (with timeout)
wait_for_vpn() {
    local max_wait=60
    local count=0

    # Skip VPN wait in web mode or if skip marker exists
    if [[ "${1:-}" == "web" ]] || [[ -f /config/vpn/SKIP_VPN ]]; then
        log_warn "VPN wait skipped in web mode"
        return 0
    fi

    # Skip VPN wait in container environments for web panel deployments
    if is_container && [[ "${1:-}" != "terminal" ]]; then
        log_warn "VPN wait skipped in container web deployment"
        return 0
    fi
    
    if [[ ! -f "$VPN_CONFIG" ]]; then
        log_warn "No VPN configuration - skipping VPN wait"
        return 0
    fi
    
    log_info "Waiting for VPN connection..."
    
    while [[ $count -lt $max_wait ]]; do
        # Check if VPN interface is up
        if ip link show tun0 &>/dev/null || ip link show tap0 &>/dev/null; then
            log_success "VPN connection established"
            
            # Test connectivity to obs.rectitude.net (skip in web mode)
            if [[ "${1:-}" == "web" ]] || [[ -f /config/vpn/SKIP_VPN ]]; then
                log_warn "VPN connectivity test skipped in web mode"
                return 0
            elif ping -c 1 -W 5 obs.rectitude.net >/dev/null 2>&1; then
                log_success "VPN connectivity to obs.rectitude.net confirmed"
                return 0
            else
                log_warn "VPN interface up but connectivity test failed"
            fi
        fi
        
        ((count++))
        sleep 1
    done
    
    log_error "VPN connection not established after ${max_wait}s"
    log_warn "Continuing without VPN - telemetry may not reach destination"
    
    # In web mode, don't fail - just continue
    if [[ "${1:-}" == "web" ]] || [[ -f /config/vpn/SKIP_VPN ]]; then
        log_warn "Web mode: continuing without VPN"
        return 0
    fi
    return 1
}

# =============================================================================
# SERVICE MANAGEMENT
# =============================================================================

# Start telemetry collection services
start_services() {
    log_info "Starting telemetry collection services..."
    
    # Use supervisor only if running as root, otherwise start manually
    if [[ "$(id -u)" == "0" ]] && command -v supervisord >/dev/null 2>&1; then
        log_info "Starting services via Supervisor (background)..."
        nohup supervisord -c /etc/supervisord.conf >> "$LOG_DIR/supervisord.log" 2>&1 &
        
        # Wait for supervisor to start
        sleep 5
        
        # Check service status
        local services=("fluent-bit" "goflow2" "telegraf" "vector" "nginx")
        for service in "${services[@]}"; do
            if supervisorctl status "$service" | grep -q "RUNNING"; then
                log_success "$service started successfully"
            else
                log_error "Failed to start $service"
            fi
        done
    else
        log_info "Starting services with production service manager v2.0 (background)..."
        # Make production service manager executable
        chmod +x "$NOC_RAVEN_HOME/scripts/production-service-manager.sh" 2>/dev/null || true
        chmod +x "$NOC_RAVEN_HOME/scripts/start-goflow2-production.sh" 2>/dev/null || true
        
        # Start the production service manager in background, log to file, and do NOT replace this shell
        local sm_log="$LOG_DIR/service-manager.log"
        nohup "$NOC_RAVEN_HOME/scripts/production-service-manager.sh" >> "$sm_log" 2>&1 &
        local sm_pid=$!
        echo "$sm_pid" > /tmp/service-manager.pid
        log_info "Production service manager started (PID: $sm_pid); logging to $sm_log"
    fi
    
    # Create API files for web interface
    if [[ -x "$NOC_RAVEN_HOME/scripts/create-api-files.sh" ]]; then
        "$NOC_RAVEN_HOME/scripts/create-api-files.sh"
        log_info "API files created for web interface"
    fi
    
    # Create service ready marker
    touch "$SERVICE_READY_FILE"
    log_success "All telemetry services started"
}

# Manual service startup (fallback)
start_services_manual() {
    # Start Fluent Bit with simplified config
    if command -v fluent-bit >/dev/null 2>&1; then
        nohup fluent-bit -c "$NOC_RAVEN_HOME/config/fluent-bit-simple.conf" > "$LOG_DIR/fluent-bit.log" 2>&1 &
        log_info "Fluent Bit started (PID: $!)"  
        sleep 2
    fi
    
    # Start GoFlow2 with proper command line arguments
    if [[ -x "$NOC_RAVEN_HOME/bin/goflow2" ]]; then
        # Make the startup script executable
        chmod +x "$NOC_RAVEN_HOME/scripts/start-goflow2.sh" 2>/dev/null || true
        nohup "$NOC_RAVEN_HOME/scripts/start-goflow2.sh" > "$LOG_DIR/goflow2.log" 2>&1 &
        log_info "GoFlow2 started (PID: $!)"
        sleep 2
    fi
    
    # Start Telegraf
    if command -v telegraf >/dev/null 2>&1; then
        nohup telegraf --config "$NOC_RAVEN_HOME/config/telegraf.conf" > "$LOG_DIR/telegraf.log" 2>&1 &
        log_info "Telegraf started (PID: $!)"
        sleep 2
    fi
    
    # Start Vector with minimal config
    if command -v vector >/dev/null 2>&1; then
        nohup vector --config-toml "$NOC_RAVEN_HOME/config/vector-minimal.toml" > "$LOG_DIR/vector.log" 2>&1 &
        log_info "Vector started (PID: $!)"
        sleep 2
    fi
    
    # Start Nginx (for web panel) - run in background
    if command -v nginx >/dev/null 2>&1; then
        nohup nginx > "$LOG_DIR/nginx.log" 2>&1 &
        log_info "Nginx started (PID: $!)"
        sleep 2
    fi
    
    # Wait a moment for all services to initialize
    sleep 5
}

# Health check for services
check_service_health() {
    log_info "Performing service health check..."
    
    local all_healthy=true
    
    # Check if processes are running
    local services=("fluent-bit" "goflow2" "telegraf" "vector" "nginx")
    for service in "${services[@]}"; do
        if pgrep -f "$service" >/dev/null; then
            log_success "$service is running"
        else
            log_error "$service is not running"
            all_healthy=false
        fi
    done
    
    # Check listening ports
    local ports=("514:udp" "2055:udp" "4739:udp" "6343:udp" "162:udp" "8080:tcp" "8084:tcp")
    for port_info in "${ports[@]}"; do
        local port="${port_info%:*}"
        local proto="${port_info#*:}"
        
        if [[ "$proto" == "udp" ]]; then
            if ss -ulpn | grep -q ":$port "; then
                log_success "UDP port $port is listening"
            else
                log_warn "UDP port $port is not listening"
            fi
        else
            if ss -tlpn | grep -q ":$port "; then
                log_success "TCP port $port is listening"
            else
                log_warn "TCP port $port is not listening"
            fi
        fi
    done
    
    return $([[ "$all_healthy" == "true" ]])
}

# =============================================================================
# MAIN EXECUTION LOGIC
# =============================================================================

# Handle termination signals gracefully
cleanup() {
    log_info "Received termination signal, shutting down gracefully..."
    
    # Stop services
    if command -v supervisorctl >/dev/null 2>&1; then
        supervisorctl shutdown
    else
        pkill -TERM fluent-bit || true
        pkill -TERM goflow2 || true
        pkill -TERM telegraf || true
        pkill -TERM vector || true
        pkill -TERM nginx || true
    fi
    
    # Stop VPN
    pkill -TERM openvpn || true
    
    log_success "NoC Raven shutdown complete"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Parse command line arguments
parse_args() {
    local mode="auto"
    
    for arg in "$@"; do
        case $arg in
            --mode=*)
                mode="${arg#*=}"
                ;;
            -m=*|--mode-*)
                mode="${arg#*=}"
                ;;
            terminal|menu)
                mode="terminal"
                ;;
            web|panel)
                mode="web"
                ;;
            auto)
                mode="auto"
                ;;
        esac
    done
    
    echo "$mode"
}

# Main function
main() {
    local mode="$(parse_args "$@")"

    # Debug logging
    log_info "Entrypoint started with arguments: $*"
    log_info "Parsed mode: $mode"

    # Show banner
    show_banner
    
    # Initialize
    init_directories
    load_environment
    optimize_system
    
    # Wait for network interface
    wait_for_interface "$NETWORK_INTERFACE"
    
    # Determine startup mode
    case "$mode" in
        "terminal"|"menu")
            log_info "Forced terminal menu mode"
            "$NOC_RAVEN_HOME/scripts/terminal-menu.sh"
            
            # After terminal menu completes, start services
            if [[ -f "$CONFIG_COMPLETE_FILE" ]]; then
                log_info "Configuration complete, starting services"
                setup_vpn "$mode"
                wait_for_vpn "$mode"
                start_services
                
            # Start background monitor and return to terminal menu
            (
                while true; do
                    if [[ ! -f "$SERVICE_READY_FILE" ]]; then
                        log_error "Services not ready, attempting restart..."
                        start_services
                    fi
                    check_service_health > /dev/null 2>&1 || true
                    sleep 30
                done
            ) &
            log_info "Services started. Returning to terminal menu..."
            "$NOC_RAVEN_HOME/scripts/terminal-menu.sh" || true
            log_info "Terminal menu exited. Keeping container alive."
            sleep infinity
            else
                log_warn "Configuration was not completed, keeping container alive for debugging"
                sleep infinity
            fi
            ;;
        "web"|"panel")
            log_info "Forced web panel mode"
            setup_vpn "$mode"
            wait_for_vpn "$mode"
            start_services
            
            # Keep container running and monitor services in web mode
            while true; do
                if [[ ! -f "$SERVICE_READY_FILE" ]]; then
                    log_error "Services not ready, attempting restart..."
                    start_services
                fi
                
                # Do not let a transient health failure kill the container in web mode
                check_service_health > /dev/null 2>&1 || true
                sleep 30
            done
            ;;
        "auto"|*)
            log_info "Auto-detecting interface mode..."

            # Debug Docker detection
            log_info "Checking Docker environment..."
            if [[ -f /.dockerenv ]]; then
                log_info "Found /.dockerenv file"
            else
                log_info "No /.dockerenv file found"
            fi

            if [[ -f /proc/1/cgroup ]]; then
                log_info "Checking /proc/1/cgroup for docker/lxc patterns..."
                if grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
                    log_info "Found docker/lxc pattern in /proc/1/cgroup"
                else
                    log_info "No docker/lxc pattern found in /proc/1/cgroup"
                fi
            else
                log_info "/proc/1/cgroup does not exist"
            fi

            # Check if running in Docker container
            if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
                log_info "Docker container detected - forcing web mode"
                setup_vpn "web"
                wait_for_vpn "web"
                start_services

                # Start background monitor and keep container running
                log_info "Services started successfully. Web panel available at http://localhost:8080"

                # Keep container running and monitor services in web mode
                while true; do
                    if [[ ! -f "$SERVICE_READY_FILE" ]]; then
                        log_error "Services not ready, attempting restart..."
                        start_services
                    fi

                    # Do not let a transient health failure kill the container in web mode
                    check_service_health > /dev/null 2>&1 || true
                    sleep 30
                done
            elif check_dhcp_status "$NETWORK_INTERFACE"; then
                # DHCP is active - start web panel services, then return to terminal menu
                log_info "DHCP detected - starting services for web panel"
                setup_vpn "web"
                wait_for_vpn "web"
                start_services

                # Start background monitor and keep container running
                log_info "Services started successfully. Web panel available at http://localhost:8080"

                # Keep container running and monitor services in web mode
                while true; do
                    if [[ ! -f "$SERVICE_READY_FILE" ]]; then
                        log_error "Services not ready, attempting restart..."
                        start_services
                    fi

                    # Do not let a transient health failure kill the container in web mode
                    check_service_health > /dev/null 2>&1 || true
                    sleep 30
                done
            else
                # No DHCP - show terminal menu
                log_info "No DHCP detected - starting terminal menu"
                "$NOC_RAVEN_HOME/scripts/terminal-menu.sh"
                
                # After terminal menu completes, start services
                if [[ -f "$CONFIG_COMPLETE_FILE" ]]; then
                    log_info "Configuration complete, starting services"
                    setup_vpn "$mode"
                    wait_for_vpn "$mode"
                    start_services
                    
                    # Start background monitor and return to terminal menu
                    (
                        while true; do
                            if [[ ! -f "$SERVICE_READY_FILE" ]]; then
                                log_error "Services not ready, attempting restart..."
                                start_services
                            fi
                            check_service_health > /dev/null 2>&1 || true
                            sleep 30
                        done
                    ) &
                    log_info "Services started. Returning to terminal menu..."
                    "$NOC_RAVEN_HOME/scripts/terminal-menu.sh" || true
                    log_info "Terminal menu exited. Keeping container alive."
                    sleep infinity
                else
                    log_warn "Configuration was not completed, exiting"
                    exit 1
                fi
            fi
            ;;
    esac
    
    # Final health check and status report
    sleep 10
    check_service_health
    
    log_success "NoC Raven is fully operational! 🦅"
    
    # Keep container running
    tail -f "$LOG_DIR"/*.log 2>/dev/null || sleep infinity
}

# Execute main function with all arguments
main "$@"
