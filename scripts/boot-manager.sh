#!/bin/bash

###################################################################################
# 🦅 NoC Raven - Boot Manager Script
# Manages system initialization and service startup sequences
###################################################################################

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly NOC_RAVEN_HOME="${NOC_RAVEN_HOME:-/opt/noc-raven}"
readonly DATA_PATH="${DATA_PATH:-/data}"
readonly CONFIG_PATH="${CONFIG_PATH:-/config}"
readonly LOG_FILE="/var/log/noc-raven/boot-manager.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Check if running as root (needed for some operations)
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        log_warn "Running as root - some operations will be performed with elevated privileges"
        return 0
    fi
    return 1
}

# Initialize directories and permissions
initialize_directories() {
    log_info "Initializing directory structure..."
    
    # Create required directories
    local dirs=(
        "${DATA_PATH}/syslog"
        "${DATA_PATH}/flows"
        "${DATA_PATH}/snmp"
        "${DATA_PATH}/metrics"
        "${DATA_PATH}/buffer"
        "${CONFIG_PATH}/vpn"
        "${CONFIG_PATH}/collectors"
        "${CONFIG_PATH}/network"
        "/var/log/noc-raven"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "Created directory: $dir"
        fi
    done
    
    # Set permissions
    if check_privileges; then
        chown -R nocraven:nocraven "${DATA_PATH}" "${CONFIG_PATH}" "/var/log/noc-raven"
        chmod -R 755 "${DATA_PATH}" "${CONFIG_PATH}"
        chmod -R 644 "/var/log/noc-raven"
    fi
    
    log_success "Directory initialization complete"
}

# Validate configuration files
validate_configs() {
    log_info "Validating configuration files..."
    
    local configs=(
        "${NOC_RAVEN_HOME}/config/goflow2.yml"
        "/etc/fluent-bit/fluent-bit.conf"
        "/etc/vector/vector.toml"
        "/etc/telegraf/telegraf.conf"
        "/etc/nginx/nginx.conf"
    )
    
    local missing_configs=()
    
    for config in "${configs[@]}"; do
        if [[ ! -f "$config" ]]; then
            missing_configs+=("$config")
        fi
    done
    
    if [[ ${#missing_configs[@]} -gt 0 ]]; then
        log_error "Missing configuration files:"
        for config in "${missing_configs[@]}"; do
            log_error "  - $config"
        done
        return 1
    fi
    
    log_success "All configuration files validated"
    return 0
}

# Check system resources
check_resources() {
    log_info "Checking system resources..."
    
    # Check memory
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_total / 1024 / 1024))
    
    if [[ $mem_gb -lt 2 ]]; then
        log_warn "Low memory detected: ${mem_gb}GB (recommended: 4GB+)"
    else
        log_info "Memory: ${mem_gb}GB available"
    fi
    
    # Check disk space
    local disk_free=$(df -BG "${DATA_PATH}" | tail -1 | awk '{print $4}' | sed 's/G//')
    
    if [[ $disk_free -lt 10 ]]; then
        log_warn "Low disk space: ${disk_free}GB free (recommended: 50GB+)"
    else
        log_info "Disk space: ${disk_free}GB available"
    fi
    
    # Check network interfaces
    local interfaces=$(ip link show | grep -E '^[0-9]+:' | wc -l)
    log_info "Network interfaces: $interfaces detected"
    
    log_success "Resource check complete"
}

# Initialize services
initialize_services() {
    log_info "Initializing services..."
    
    # Check if supervisor is running
    if ! pgrep supervisord > /dev/null; then
        log_info "Starting supervisor daemon..."
        if check_privileges; then
            supervisord -c /etc/supervisord.conf
            sleep 2
        fi
    fi
    
    # Start essential services in order
    local services=("goflow2" "fluent-bit" "vector" "telegraf" "nginx")
    
    for service in "${services[@]}"; do
        log_info "Initializing service: $service"
        if command -v supervisorctl > /dev/null; then
            supervisorctl reread
            supervisorctl update "$service"
            supervisorctl start "$service"
        fi
    done
    
    log_success "Service initialization complete"
}

# Health check
perform_health_check() {
    log_info "Performing initial health check..."
    
    if [[ -x "${NOC_RAVEN_HOME}/bin/health-check.sh" ]]; then
        "${NOC_RAVEN_HOME}/bin/health-check.sh"
    else
        log_warn "Health check script not found or not executable"
    fi
}

# Display system banner
display_banner() {
    cat << 'EOF'

  ███╗   ██╗ ██████╗  ██████╗    ██████╗  █████╗ ██╗   ██╗███████╗███╗   ██╗
  ████╗  ██║██╔═══██╗██╔════╝    ██╔══██╗██╔══██╗██║   ██║██╔════╝████╗  ██║
  ██╔██╗ ██║██║   ██║██║         ██████╔╝███████║██║   ██║█████╗  ██╔██╗ ██║
  ██║╚██╗██║██║   ██║██║         ██╔══██╗██╔══██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║
  ██║ ╚████║╚██████╔╝╚██████╗    ██║  ██║██║  ██║ ╚████╔╝ ███████╗██║ ╚████║
  ╚═╝  ╚═══╝ ╚═════╝  ╚═════╝    ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝

         Telemetry Collection & Forwarding Appliance - Boot Manager

EOF
    
    log_info "NoC Raven Boot Manager v1.0.0"
    log_info "Starting system initialization..."
}

# Main execution
main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    display_banner
    
    # Execute boot sequence
    initialize_directories
    
    if ! validate_configs; then
        log_error "Configuration validation failed - aborting boot sequence"
        exit 1
    fi
    
    check_resources
    initialize_services
    
    # Brief pause to let services start
    sleep 5
    
    perform_health_check
    
    log_success "🦅 NoC Raven boot sequence completed successfully"
    log_info "Web interface available at: http://localhost:8080"
    log_info "Access terminal menu with: ${NOC_RAVEN_HOME}/bin/terminal-menu"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
