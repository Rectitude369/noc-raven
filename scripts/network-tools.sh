#!/bin/bash

###################################################################################
# 🦅 NoC Raven - Network Tools Script
# Network diagnostic and management utilities
###################################################################################

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   echo "Please use sudo or run as the root user."
   exit 1
fi

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly NOC_RAVEN_HOME="${NOC_RAVEN_HOME:-/opt/noc-raven}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Display help
show_help() {
    cat << 'EOF'
🦅 NoC Raven - Network Tools

USAGE:
    network-tools.sh [COMMAND] [OPTIONS]

COMMANDS:
    interface-status    Show network interface status
    port-scan          Scan for open telemetry ports
    flow-test          Test NetFlow reception
    syslog-test        Test Syslog reception
    snmp-test          Test SNMP trap reception
    bandwidth          Monitor interface bandwidth
    connectivity       Test connectivity to targets
    packet-capture     Capture packets on interface
    help               Show this help message

OPTIONS:
    -i, --interface    Network interface (default: auto-detect)
    -p, --port         Port number for testing
    -t, --target       Target host or IP
    -c, --count        Number of packets/tests
    -d, --duration     Duration for monitoring (seconds)

EXAMPLES:
    network-tools.sh interface-status
    network-tools.sh port-scan -p 2055
    network-tools.sh connectivity -t 192.168.1.1
    network-tools.sh bandwidth -i eth0 -d 30

EOF
}

# Log with timestamp
log() {
    echo -e "$(date '+%H:%M:%S') $*"
}

# Get primary network interface
get_primary_interface() {
    ip route show default | grep -oP '(?<=dev )\w+' | head -1
}

# Show network interface status
interface_status() {
    log "${BLUE}=== Network Interface Status ===${NC}"
    
    # Show all interfaces
    echo -e "\n${CYAN}Active Interfaces:${NC}"
    ip -br addr show | grep UP | while read -r line; do
        interface=$(echo "$line" | awk '{print $1}')
        ip_addr=$(echo "$line" | awk '{print $3}' | cut -d'/' -f1)
        status=$(echo "$line" | awk '{print $2}')
        
        echo -e "  ${GREEN}${interface}${NC}: ${ip_addr} (${status})"
    done
    
    # Show interface statistics
    echo -e "\n${CYAN}Interface Statistics:${NC}"
    for interface in $(ip -br link show | awk '{print $1}' | grep -v lo); do
        if [[ -d "/sys/class/net/$interface/statistics" ]]; then
            rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo 0)
            tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo 0)
            rx_packets=$(cat "/sys/class/net/$interface/statistics/rx_packets" 2>/dev/null || echo 0)
            tx_packets=$(cat "/sys/class/net/$interface/statistics/tx_packets" 2>/dev/null || echo 0)
            
            rx_mb=$((rx_bytes / 1024 / 1024))
            tx_mb=$((tx_bytes / 1024 / 1024))
            
            echo -e "  ${GREEN}${interface}${NC}: RX: ${rx_mb}MB (${rx_packets} pkts) TX: ${tx_mb}MB (${tx_packets} pkts)"
        fi
    done
}

# Scan for telemetry ports
port_scan() {
    local target="${1:-localhost}"
    local ports=(1514 2055 4739 6343 162 8084 8080)

    log "${BLUE}=== Telemetry Port Scan: $target ===${NC}"

    for port in "${ports[@]}"; do
        local service=""
        case $port in
            1514) service="Syslog" ;;
            2055) service="NetFlow" ;;
            4739) service="NetFlow/IPFIX" ;;
            6343) service="sFlow" ;;
            162)  service="SNMP Traps" ;;
            8084) service="Vector HTTP" ;;
            8080) service="Web Interface" ;;
        esac
        
        if timeout 3 bash -c "echo >/dev/tcp/$target/$port" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Port $port ($service): ${GREEN}OPEN${NC}"
        else
            echo -e "  ${RED}✗${NC} Port $port ($service): ${RED}CLOSED${NC}"
        fi
    done
}

# Test NetFlow reception
flow_test() {
    local interface="${1:-$(get_primary_interface)}"
    local port="${2:-2055}"
    local duration="${3:-10}"
    
    log "${BLUE}=== NetFlow Reception Test ===${NC}"
    log "Interface: $interface, Port: $port, Duration: ${duration}s"
    
    if command -v tcpdump > /dev/null; then
        echo -e "${CYAN}Monitoring NetFlow traffic...${NC}"
        timeout "$duration" tcpdump -i "$interface" -c 10 "udp port $port" 2>/dev/null || true
    else
        log "${RED}tcpdump not available - using netstat${NC}"
        netstat -an | grep ":$port"
    fi
}

# Test Syslog reception
syslog_test() {
    local port="${1:-514}"
    local duration="${2:-10}"
    
    log "${BLUE}=== Syslog Reception Test ===${NC}"
    log "Port: $port, Duration: ${duration}s"
    
    if command -v tcpdump > /dev/null; then
        echo -e "${CYAN}Monitoring Syslog traffic...${NC}"
        timeout "$duration" tcpdump -i any -A "udp port $port" 2>/dev/null || true
    else
        log "${RED}tcpdump not available - checking process${NC}"
        ps aux | grep -E "(fluent-bit|rsyslog|syslog)"
    fi
}

# Test SNMP trap reception
snmp_test() {
    local port="${1:-162}"
    local duration="${2:-10}"
    
    log "${BLUE}=== SNMP Trap Reception Test ===${NC}"
    log "Port: $port, Duration: ${duration}s"
    
    if command -v tcpdump > /dev/null; then
        echo -e "${CYAN}Monitoring SNMP trap traffic...${NC}"
        timeout "$duration" tcpdump -i any "udp port $port" 2>/dev/null || true
    else
        log "${RED}tcpdump not available - checking listeners${NC}"
        netstat -an | grep ":$port"
    fi
}

# Monitor bandwidth
monitor_bandwidth() {
    local interface="${1:-$(get_primary_interface)}"
    local duration="${2:-30}"
    
    log "${BLUE}=== Bandwidth Monitor: $interface ===${NC}"
    log "Duration: ${duration}s"
    
    if [[ ! -d "/sys/class/net/$interface" ]]; then
        log "${RED}Interface $interface not found${NC}"
        return 1
    fi
    
    local start_rx=$(cat "/sys/class/net/$interface/statistics/rx_bytes")
    local start_tx=$(cat "/sys/class/net/$interface/statistics/tx_bytes")
    local start_time=$(date +%s)
    
    echo -e "${CYAN}Monitoring... (Press Ctrl+C to stop)${NC}"
    
    for ((i=0; i<duration; i++)); do
        sleep 1
        local current_rx=$(cat "/sys/class/net/$interface/statistics/rx_bytes")
        local current_tx=$(cat "/sys/class/net/$interface/statistics/tx_bytes")
        local current_time=$(date +%s)
        
        local rx_diff=$((current_rx - start_rx))
        local tx_diff=$((current_tx - start_tx))
        local time_diff=$((current_time - start_time))
        
        if [[ $time_diff -gt 0 ]]; then
            local rx_rate=$((rx_diff / time_diff / 1024))
            local tx_rate=$((tx_diff / time_diff / 1024))
            
            printf "\r${GREEN}RX: %6d KB/s  TX: %6d KB/s${NC}" "$rx_rate" "$tx_rate"
        fi
    done
    echo
}

# Test connectivity
test_connectivity() {
    local targets=("8.8.8.8" "1.1.1.1" "google.com")
    
    if [[ $# -gt 0 ]]; then
        targets=("$@")
    fi
    
    log "${BLUE}=== Connectivity Test ===${NC}"
    
    for target in "${targets[@]}"; do
        if ping -c 3 -W 3 "$target" > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} $target: ${GREEN}REACHABLE${NC}"
        else
            echo -e "  ${RED}✗${NC} $target: ${RED}UNREACHABLE${NC}"
        fi
    done
}

# Capture packets
packet_capture() {
    local interface="${1:-$(get_primary_interface)}"
    local port="${2:-2055}"
    local count="${3:-50}"
    local output_file="${4:-/tmp/noc-raven-capture.pcap}"
    
    log "${BLUE}=== Packet Capture ===${NC}"
    log "Interface: $interface, Port: $port, Count: $count"
    log "Output: $output_file"
    
    if ! command -v tcpdump > /dev/null; then
        log "${RED}tcpdump not available${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Capturing packets...${NC}"
    tcpdump -i "$interface" -c "$count" -w "$output_file" "udp port $port" 2>/dev/null
    
    if [[ -f "$output_file" ]]; then
        local file_size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null || echo "unknown")
        log "${GREEN}Capture complete: $output_file (${file_size} bytes)${NC}"
    fi
}

# Main function
main() {
    local command="${1:-help}"
    
    case "$command" in
        "interface-status"|"if")
            interface_status
            ;;
        "port-scan"|"ports")
            shift
            port_scan "$@"
            ;;
        "flow-test"|"netflow")
            shift
            flow_test "$@"
            ;;
        "syslog-test"|"syslog")
            shift
            syslog_test "$@"
            ;;
        "snmp-test"|"snmp")
            shift
            snmp_test "$@"
            ;;
        "bandwidth"|"bw")
            shift
            monitor_bandwidth "$@"
            ;;
        "connectivity"|"ping")
            shift
            test_connectivity "$@"
            ;;
        "packet-capture"|"pcap")
            shift
            packet_capture "$@"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            echo "Use 'network-tools.sh help' for usage information"
            exit 1
            ;;
    esac
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
