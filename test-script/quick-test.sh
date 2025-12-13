#!/bin/bash
#############################################################################
# Quick Telemetry Tester - CLI Version
# Description: Fast command-line testing for syslog, NetFlow, and SNMP
# Usage: ./quick-test.sh <host> <protocol> [count]
#############################################################################

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

show_usage() {
    cat <<EOF
Usage: $0 <host> <protocol> [count] [options]

Protocols:
  syslog    - Send syslog messages (port 1514)
  netflow   - Send NetFlow v5 packets (port 2055)
  snmp      - Send SNMP traps (port 162)
  all       - Test all protocols

Options:
  count     - Number of messages/flows/traps to send (default: 10)

Examples:
  $0 localhost syslog 20
  $0 192.168.1.100 netflow 100
  $0 10.0.0.1 snmp 5
  $0 localhost all

EOF
    exit 1
}

# Check arguments
if [ $# -lt 2 ]; then
    show_usage
fi

readonly HOST="$1"
readonly PROTOCOL="$2"
readonly COUNT="${3:-10}"

echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Quick Telemetry Tester${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "  Host: ${YELLOW}$HOST${NC}"
echo -e "  Protocol: ${YELLOW}$PROTOCOL${NC}"
echo -e "  Count: ${YELLOW}$COUNT${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

# Test Syslog
test_syslog() {
    local host="$1"
    local count="$2"
    local port=1514
    
    echo -e "${CYAN}Testing Syslog...${NC}"
    local sent=0
    local failed=0
    
    for i in $(seq 1 "$count"); do
        local timestamp=$(date '+%b %d %H:%M:%S')
        local priority=134  # local0.info
        local hostname=$(hostname)
        local message="<$priority>$timestamp $hostname quick-test[$$]: Test syslog message $i/$count"
        
        if echo -n "$message" | nc -u -w1 "$host" "$port" 2>/dev/null; then
            ((sent++))
        else
            ((failed++))
        fi
        
        echo -ne "\r  ${GREEN}✓${NC} Sent: $sent/${count} ${RED}✗${NC} Failed: $failed"
    done
    
    echo ""
    echo -e "  ${GREEN}Syslog test complete: $sent/$count sent${NC}"
    echo ""
}

# Test NetFlow
test_netflow() {
    local host="$1"
    local count="$2"
    local port=2055
    
    echo -e "${CYAN}Testing NetFlow v5...${NC}"
    local sent=0
    local failed=0
    local batch_size=10
    
    for i in $(seq 1 $batch_size $count); do
        local remaining=$((count - i + 1))
        local current_batch=$((remaining < batch_size ? remaining : batch_size))
        
        # Generate NetFlow v5 packet
        local packet=$(generate_netflow_v5 "$i" "$current_batch")
        
        if echo -n "$packet" | xxd -r -p | nc -u -w1 "$host" "$port" 2>/dev/null; then
            sent=$((sent + current_batch))
        else
            failed=$((failed + current_batch))
        fi
        
        echo -ne "\r  ${GREEN}✓${NC} Sent: $sent/${count} flows"
        sleep 0.1
    done
    
    echo ""
    echo -e "  ${GREEN}NetFlow test complete: $sent/$count flows sent${NC}"
    echo ""
}

# Test SNMP
test_snmp() {
    local host="$1"
    local count="$2"
    local port=162
    
    echo -e "${CYAN}Testing SNMP Traps...${NC}"
    
    if command -v snmptrap &> /dev/null; then
        echo "  Using snmptrap command..."
        test_snmp_native "$host" "$port" "$count"
    else
        echo "  Using synthetic traps (snmptrap not found)..."
        test_snmp_synthetic "$host" "$port" "$count"
    fi
}

test_snmp_native() {
    local host="$1"
    local port="$2"
    local count="$3"
    local sent=0
    local failed=0
    
    for i in $(seq 1 "$count"); do
        if snmptrap -v 2c -c public "$host:$port" '' .1.3.6.1.6.3.1.1.5.1 \
            .1.3.6.1.4.1.99999.1.1 s "Test trap $i/$count" 2>/dev/null; then
            ((sent++))
        else
            ((failed++))
        fi
        echo -ne "\r  ${GREEN}✓${NC} Sent: $sent/${count} ${RED}✗${NC} Failed: $failed"
    done
    
    echo ""
    echo -e "  ${GREEN}SNMP test complete: $sent/$count traps sent${NC}"
    echo ""
}

test_snmp_synthetic() {
    local host="$1"
    local port="$2"
    local count="$3"
    local sent=0
    
    for i in $(seq 1 "$count"); do
        # Simple SNMP v2c trap packet (hex)
        local packet="3040020101040670756271696361730202000"
        
        if echo -n "$packet" | xxd -r -p | nc -u -w1 "$host" "$port" 2>/dev/null; then
            ((sent++))
        fi
        echo -ne "\r  ${GREEN}✓${NC} Sent: $sent/${count} traps"
    done
    
    echo ""
    echo -e "  ${YELLOW}SNMP synthetic test complete: $sent/$count traps sent${NC}"
    echo -e "  ${YELLOW}Note: Synthetic traps may not be fully compatible${NC}"
    echo ""
}

# Generate NetFlow v5 packet
generate_netflow_v5() {
    local seq="$1"
    local count="$2"
    
    # Source/Dest IPs (10.0.0.1 -> 10.0.0.2)
    local src_hex="0a000001"
    local dst_hex="0a000002"
    
    # NetFlow v5 header
    local header=""
    header="${header}0005"  # Version
    header="${header}$(printf '%04x' $count)"  # Count
    header="${header}$(printf '%08x' $(date +%s))"  # SysUptime
    header="${header}$(printf '%08x' $(date +%s))"  # Unix Seconds
    header="${header}00000000"  # Unix Nanoseconds
    header="${header}$(printf '%08x' $seq)"  # Sequence
    header="${header}00"  # Engine Type
    header="${header}01"  # Engine ID
    header="${header}000a"  # Sample Rate (1:10)
    
    # Generate flow records
    local flows=""
    for i in $(seq 1 $count); do
        local sport=$((1024 + RANDOM % 64000))
        local dport=$((80 + RANDOM % 10))
        local packets=$((10 + RANDOM % 1000))
        local bytes=$((packets * (40 + RANDOM % 1460)))
        
        flows="${flows}${src_hex}"  # Source IP
        flows="${flows}${dst_hex}"  # Dest IP
        flows="${flows}00000000"  # Next Hop
        flows="${flows}0001"  # Input Interface
        flows="${flows}0002"  # Output Interface
        flows="${flows}$(printf '%08x' $packets)"  # Packets
        flows="${flows}$(printf '%08x' $bytes)"  # Bytes
        flows="${flows}$(printf '%08x' $(($(date +%s) - 60)))"  # Start Time
        flows="${flows}$(printf '%08x' $(date +%s))"  # End Time
        flows="${flows}$(printf '%04x' $sport)"  # Source Port
        flows="${flows}$(printf '%04x' $dport)"  # Dest Port
        flows="${flows}00"  # Pad
        flows="${flows}06"  # TCP Protocol
        flows="${flows}00"  # TOS
        flows="${flows}00"  # TCP Flags
        flows="${flows}0000"  # Pad
    done
    
    echo "${header}${flows}"
}

# Main execution
case "$PROTOCOL" in
    syslog)
        test_syslog "$HOST" "$COUNT"
        ;;
    netflow)
        test_netflow "$HOST" "$COUNT"
        ;;
    snmp)
        test_snmp "$HOST" "$COUNT"
        ;;
    all)
        echo -e "${YELLOW}Testing all protocols...${NC}"
        echo ""
        test_syslog "$HOST" "$COUNT"
        test_netflow "$HOST" "$COUNT"
        test_snmp "$HOST" "$COUNT"
        ;;
    *)
        echo -e "${RED}Unknown protocol: $PROTOCOL${NC}"
        show_usage
        ;;
esac

echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  All tests completed!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
