#!/bin/bash
# 🦅 NoC Raven - Dynamic Port Management Service
# Handles port allocation, conflict detection, and service restart coordination

set -e

# Configuration
NOC_RAVEN_HOME="${NOC_RAVEN_HOME:-/opt/noc-raven}"
CONFIG_PATH="${CONFIG_PATH:-/config}"
DATA_PATH="${DATA_PATH:-/data}"
LOG_FILE="/var/log/noc-raven/port-manager.log"

# Port mapping configuration
declare -A SERVICE_PORTS=(
    ["fluent-bit"]="1514"
    ["goflow2-netflow"]="2055"
    ["goflow2-ipfix"]="4739"
    ["goflow2-sflow"]="6343"
    ["telegraf-snmp"]="162"
    ["vector-http"]="8084"
    ["nginx-web"]="8080"
    ["config-service"]="5004"
    ["buffer-manager"]="5005"
)

declare -A PORT_PROTOCOLS=(
    ["1514"]="udp"
    ["2055"]="udp"
    ["4739"]="udp"
    ["6343"]="udp"
    ["162"]="udp"
    ["8084"]="tcp"
    ["8080"]="tcp"
    ["5004"]="tcp"
    ["5005"]="tcp"
)

# Logging function
log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] [port-manager] $*" | tee -a "$LOG_FILE"
}

# Check if port is available
is_port_available() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    if [[ "$protocol" == "udp" ]]; then
        ! netstat -uln 2>/dev/null | grep -q ":$port "
    else
        ! netstat -tln 2>/dev/null | grep -q ":$port "
    fi
}

# Get next available port in range
get_next_available_port() {
    local base_port="$1"
    local protocol="${2:-tcp}"
    local max_attempts="${3:-100}"
    
    for ((i=0; i<max_attempts; i++)); do
        local test_port=$((base_port + i))
        if is_port_available "$test_port" "$protocol"; then
            echo "$test_port"
            return 0
        fi
    done
    
    log "ERROR" "No available port found starting from $base_port"
    return 1
}

# Validate port configuration
validate_port_config() {
    local config_file="${1:-$CONFIG_PATH/config.json}"
    
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check JSON validity
    if ! jq empty "$config_file" 2>/dev/null; then
        log "ERROR" "Invalid JSON configuration file: $config_file"
        return 1
    fi
    
    # Extract ports and check for conflicts
    local ports=()
    local conflicts=()
    
    # Get syslog port
    if syslog_port=$(jq -r '.collection.syslog.port // empty' "$config_file" 2>/dev/null) && [[ -n "$syslog_port" ]]; then
        ports+=("$syslog_port:udp:fluent-bit")
    fi
    
    # Get NetFlow ports
    if netflow_port=$(jq -r '.collection.netflow.port // empty' "$config_file" 2>/dev/null) && [[ -n "$netflow_port" ]]; then
        ports+=("$netflow_port:udp:goflow2-netflow")
    fi
    
    # Get SNMP trap port
    if snmp_port=$(jq -r '.collection.snmp.trap_port // empty' "$config_file" 2>/dev/null) && [[ -n "$snmp_port" ]]; then
        ports+=("$snmp_port:udp:telegraf-snmp")
    fi
    
    # Get Windows Events port
    if windows_port=$(jq -r '.collection.windows.port // empty' "$config_file" 2>/dev/null) && [[ -n "$windows_port" ]]; then
        ports+=("$windows_port:tcp:vector-http")
    fi
    
    # Check for port conflicts
    local used_ports=()
    for port_spec in "${ports[@]}"; do
        IFS=':' read -r port protocol service <<< "$port_spec"
        
        if [[ " ${used_ports[@]} " =~ " ${port} " ]]; then
            conflicts+=("Port $port is used by multiple services")
        else
            used_ports+=("$port")
        fi
        
        # Check if port is available on system
        if ! is_port_available "$port" "$protocol"; then
            conflicts+=("Port $port ($protocol) is already in use by another process")
        fi
    done
    
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log "ERROR" "Port configuration conflicts detected:"
        for conflict in "${conflicts[@]}"; do
            log "ERROR" "  - $conflict"
        done
        return 1
    fi
    
    log "INFO" "Port configuration validation successful"
    return 0
}

# Apply port configuration changes
apply_port_changes() {
    local config_file="${1:-$CONFIG_PATH/config.json}"
    local restart_services=()
    
    log "INFO" "Applying port configuration changes from $config_file"
    
    # Extract current ports from configuration
    local syslog_port netflow_port snmp_port windows_port
    syslog_port=$(jq -r '.collection.syslog.port // empty' "$config_file" 2>/dev/null)
    netflow_port=$(jq -r '.collection.netflow.port // empty' "$config_file" 2>/dev/null)
    snmp_port=$(jq -r '.collection.snmp.trap_port // empty' "$config_file" 2>/dev/null)
    windows_port=$(jq -r '.collection.windows.port // empty' "$config_file" 2>/dev/null)
    
    # Update service configurations
    if [[ -n "$syslog_port" ]] && [[ "$syslog_port" != "${SERVICE_PORTS[fluent-bit]}" ]]; then
        log "INFO" "Updating Fluent Bit syslog port to $syslog_port"
        update_fluent_bit_config "$syslog_port"
        restart_services+=("fluent-bit")
        SERVICE_PORTS["fluent-bit"]="$syslog_port"
    fi
    
    if [[ -n "$netflow_port" ]] && [[ "$netflow_port" != "${SERVICE_PORTS[goflow2-netflow]}" ]]; then
        log "INFO" "Updating GoFlow2 NetFlow port to $netflow_port"
        update_goflow2_config "$netflow_port"
        restart_services+=("goflow2")
        SERVICE_PORTS["goflow2-netflow"]="$netflow_port"
    fi
    
    if [[ -n "$snmp_port" ]] && [[ "$snmp_port" != "${SERVICE_PORTS[telegraf-snmp]}" ]]; then
        log "INFO" "Updating Telegraf SNMP trap port to $snmp_port"
        update_telegraf_config "$snmp_port"
        restart_services+=("telegraf")
        SERVICE_PORTS["telegraf-snmp"]="$snmp_port"
    fi
    
    if [[ -n "$windows_port" ]] && [[ "$windows_port" != "${SERVICE_PORTS[vector-http]}" ]]; then
        log "INFO" "Updating Vector Windows Events port to $windows_port"
        update_vector_config "$windows_port"
        restart_services+=("vector")
        SERVICE_PORTS["vector-http"]="$windows_port"
    fi
    
    # Restart affected services
    for service in "${restart_services[@]}"; do
        log "INFO" "Restarting service: $service"
        restart_service "$service"
    done
    
    # Update port status monitoring
    update_port_monitoring
    
    log "INFO" "Port configuration changes applied successfully"
}

# Update Fluent Bit configuration
update_fluent_bit_config() {
    local port="$1"
    local config_file="$NOC_RAVEN_HOME/config/fluent-bit.conf"
    
    if [[ -f "$config_file" ]]; then
        # Update syslog input port
        sed -i "s/Listen[[:space:]]*[0-9]*/Listen    $port/" "$config_file"
        log "INFO" "Updated Fluent Bit configuration: syslog port = $port"
    fi
}

# Update GoFlow2 configuration
update_goflow2_config() {
    local port="$1"
    local config_file="$NOC_RAVEN_HOME/config/goflow2.yml"
    
    if [[ -f "$config_file" ]]; then
        # Update NetFlow port in YAML configuration
        sed -i "s/bind: \".*:2055\"/bind: \"0.0.0.0:$port\"/" "$config_file"
        log "INFO" "Updated GoFlow2 configuration: NetFlow port = $port"
    fi
}

# Update Telegraf configuration  
update_telegraf_config() {
    local port="$1"
    local config_file="$NOC_RAVEN_HOME/config/telegraf-production.conf"
    
    if [[ -f "$config_file" ]]; then
        # Update SNMP trap service address
        sed -i "s/service_address = \"udp:\/\/:[0-9]*\"/service_address = \"udp:\/\/:$port\"/" "$config_file"
        log "INFO" "Updated Telegraf configuration: SNMP trap port = $port"
    fi
}

# Update Vector configuration
update_vector_config() {
    local port="$1"
    local config_file="$NOC_RAVEN_HOME/config/vector-production.toml"
    
    if [[ -f "$config_file" ]]; then
        # Update Windows Events HTTP source port
        sed -i "s/address = \"0\.0\.0\.0:[0-9]*\"/address = \"0.0.0.0:$port\"/" "$config_file"
        log "INFO" "Updated Vector configuration: Windows Events port = $port"
    fi
}

# Restart service using supervisor or service manager
restart_service() {
    local service="$1"
    local success=false
    
    # Try supervisor first
    if command -v supervisorctl >/dev/null 2>&1; then
        if supervisorctl restart "$service" 2>/dev/null; then
            success=true
            log "INFO" "Service $service restarted via supervisor"
        fi
    fi
    
    # Try production service manager
    if [[ "$success" != "true" ]] && [[ -f "$NOC_RAVEN_HOME/scripts/production-service-manager.sh" ]]; then
        if "$NOC_RAVEN_HOME/scripts/production-service-manager.sh" restart "$service" 2>/dev/null; then
            success=true
            log "INFO" "Service $service restarted via production service manager"
        fi
    fi
    
    # Try systemctl (if available)
    if [[ "$success" != "true" ]] && command -v systemctl >/dev/null 2>&1; then
        if systemctl restart "$service" 2>/dev/null; then
            success=true
            log "INFO" "Service $service restarted via systemctl"
        fi
    fi
    
    if [[ "$success" != "true" ]]; then
        log "ERROR" "Failed to restart service: $service"
        return 1
    fi
}

# Update port monitoring configuration
update_port_monitoring() {
    local monitoring_config="/tmp/noc-raven-port-status.json"
    
    # Generate port status for monitoring
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"ports\": ["
        
        local first=true
        for service in "${!SERVICE_PORTS[@]}"; do
            local port="${SERVICE_PORTS[$service]}"
            local protocol="${PORT_PROTOCOLS[$port]:-tcp}"
            local available
            
            if is_port_available "$port" "$protocol"; then
                available="false"
            else
                available="true"
            fi
            
            if [[ "$first" != "true" ]]; then
                echo ","
            fi
            first=false
            
            echo "    {"
            echo "      \"service\": \"$service\","
            echo "      \"port\": $port,"
            echo "      \"protocol\": \"$protocol\","
            echo "      \"status\": \"$available\""
            echo "    }"
        done
        
        echo "  ]"
        echo "}"
    } > "$monitoring_config"
    
    log "INFO" "Updated port monitoring configuration"
}

# Port status monitoring
monitor_ports() {
    log "INFO" "Starting port status monitoring"
    
    while true; do
        local conflicts=()
        
        for service in "${!SERVICE_PORTS[@]}"; do
            local port="${SERVICE_PORTS[$service]}"
            local protocol="${PORT_PROTOCOLS[$port]:-tcp}"
            
            # Check if service port is actually bound
            if ! netstat -${protocol:0:1}ln 2>/dev/null | grep -q ":$port "; then
                conflicts+=("Service $service not listening on port $port ($protocol)")
            fi
        done
        
        if [[ ${#conflicts[@]} -gt 0 ]]; then
            log "WARNING" "Port monitoring detected issues:"
            for conflict in "${conflicts[@]}"; do
                log "WARNING" "  - $conflict"
            done
        fi
        
        # Update monitoring status
        update_port_monitoring
        
        # Sleep for monitoring interval
        sleep 30
    done
}

# Initialize port manager
initialize() {
    log "INFO" "Initializing NoC Raven Port Manager"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Validate initial configuration
    if ! validate_port_config; then
        log "ERROR" "Initial port configuration validation failed"
        return 1
    fi
    
    # Apply current configuration
    apply_port_changes
    
    log "INFO" "Port Manager initialization completed"
}

# Main function
main() {
    case "${1:-help}" in
        "validate")
            validate_port_config "${2:-}"
            ;;
        "apply")
            apply_port_changes "${2:-}"
            ;;
        "monitor")
            monitor_ports
            ;;
        "init")
            initialize
            ;;
        "restart")
            shift
            for service in "$@"; do
                restart_service "$service"
            done
            ;;
        "status")
            update_port_monitoring
            cat /tmp/noc-raven-port-status.json 2>/dev/null || echo '{"error": "Status not available"}'
            ;;
        "help"|*)
            echo "Usage: $0 {validate|apply|monitor|init|restart|status} [options]"
            echo ""
            echo "Commands:"
            echo "  validate [config_file]    - Validate port configuration"
            echo "  apply [config_file]       - Apply port configuration changes"
            echo "  monitor                   - Start port status monitoring"
            echo "  init                      - Initialize port manager"
            echo "  restart <service>...      - Restart specified services"
            echo "  status                    - Show current port status"
            echo "  help                      - Show this help message"
            ;;
    esac
}

# Handle script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi