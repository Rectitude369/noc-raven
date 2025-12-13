#!/bin/bash

# 🦅 NoC Raven - Comprehensive Telemetry Test Suite
# Tests all telemetry collection endpoints with real data

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APPLIANCE_HOST="${1:-localhost}"
APPLIANCE_PORT="${2:-9080}"
TEST_TIMEOUT=10

echo -e "${BLUE}🦅 NoC Raven Telemetry Test Suite${NC}"
echo -e "${BLUE}====================================${NC}"
echo "Testing appliance at: ${APPLIANCE_HOST}:${APPLIANCE_PORT}"
echo ""

# Function to print test results
print_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✅ $test_name: PASS${NC}"
    elif [ "$result" = "FAIL" ]; then
        echo -e "${RED}❌ $test_name: FAIL${NC}"
        [ -n "$details" ] && echo -e "${RED}   Details: $details${NC}"
    elif [ "$result" = "WARN" ]; then
        echo -e "${YELLOW}⚠️  $test_name: WARNING${NC}"
        [ -n "$details" ] && echo -e "${YELLOW}   Details: $details${NC}"
    fi
}

# Test 1: Web Interface Connectivity
echo -e "${BLUE}🌐 Testing Web Interface...${NC}"
if curl -s -f "http://${APPLIANCE_HOST}:${APPLIANCE_PORT}/health" > /dev/null; then
    print_result "Web Interface Health Check" "PASS"
else
    print_result "Web Interface Health Check" "FAIL" "Cannot reach appliance web interface"
    exit 1
fi

# Test 2: API Connectivity
echo -e "${BLUE}📡 Testing API Endpoints...${NC}"
if curl -s -f "http://${APPLIANCE_HOST}:${APPLIANCE_PORT}/api/config" > /dev/null; then
    print_result "API Config Endpoint" "PASS"
else
    print_result "API Config Endpoint" "FAIL" "Config API not responding"
fi

# Test 3: Syslog Collection (Port 1514/UDP)
echo -e "${BLUE}📝 Testing Syslog Collection...${NC}"
TEST_SYSLOG_MSG="<134>$(date '+%b %d %H:%M:%S') test-host noc-raven-test: This is a test syslog message from telemetry test suite"

# Send test syslog message
if echo "$TEST_SYSLOG_MSG" | nc -u -w1 "$APPLIANCE_HOST" 1514; then
    print_result "Syslog Message Send" "PASS" "Sent to port 1514/UDP"
    
    # Wait a moment for processing
    sleep 2
    
    # Check if data appears in metrics
    SYSLOG_COUNT=$(curl -s "http://${APPLIANCE_HOST}:${APPLIANCE_PORT}/api/metrics" | jq -r '.syslog_messages_received // 0' 2>/dev/null || echo "0")
    if [ "$SYSLOG_COUNT" -gt 0 ]; then
        print_result "Syslog Data Processing" "PASS" "$SYSLOG_COUNT messages received"
    else
        print_result "Syslog Data Processing" "FAIL" "No syslog messages in metrics"
    fi
else
    print_result "Syslog Message Send" "FAIL" "Cannot send to port 1514/UDP"
fi

# Test 4: NetFlow Collection (Port 2055/UDP)
echo -e "${BLUE}🌊 Testing NetFlow Collection...${NC}"

# Create a simple NetFlow v5 test packet (simplified)
if command -v nfcapd >/dev/null 2>&1; then
    print_result "NetFlow Test Tools" "PASS" "nfcapd available"
    # Note: Real NetFlow testing requires specialized tools
    print_result "NetFlow Collection Test" "WARN" "Requires NetFlow generator tool"
else
    print_result "NetFlow Collection Test" "WARN" "NetFlow test tools not available (install nfcapd)"
fi

# Test 5: SNMP Trap Collection (Port 162/UDP)
echo -e "${BLUE}🔔 Testing SNMP Trap Collection...${NC}"

if command -v snmptrap >/dev/null 2>&1; then
    # Send a test SNMP trap
    if snmptrap -v2c -c public "$APPLIANCE_HOST":162 '' 1.3.6.1.4.1.8072.2.3.0.1 1.3.6.1.4.1.8072.2.3.2.1 i 123456 2>/dev/null; then
        print_result "SNMP Trap Send" "PASS" "Sent to port 162/UDP"
        
        # Wait for processing
        sleep 2
        
        # Check metrics
        SNMP_COUNT=$(curl -s "http://${APPLIANCE_HOST}:${APPLIANCE_PORT}/api/metrics" | jq -r '.snmp_traps_received // 0' 2>/dev/null || echo "0")
        if [ "$SNMP_COUNT" -gt 0 ]; then
            print_result "SNMP Trap Processing" "PASS" "$SNMP_COUNT traps received"
        else
            print_result "SNMP Trap Processing" "FAIL" "No SNMP traps in metrics"
        fi
    else
        print_result "SNMP Trap Send" "FAIL" "Cannot send SNMP trap"
    fi
else
    print_result "SNMP Trap Test" "WARN" "SNMP tools not available (install net-snmp-utils)"
fi

# Test 6: Windows Events Collection (Port 8084/TCP)
echo -e "${BLUE}🪟 Testing Windows Events Collection...${NC}"

# Test HTTP endpoint
TEST_WINDOWS_EVENT='{"TimeCreated": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'", "EventID": 4624, "Level": "Information", "Source": "Microsoft-Windows-Security-Auditing", "Message": "Test logon event from NoC Raven test suite"}'

if curl -s -X POST -H "Content-Type: application/json" -d "$TEST_WINDOWS_EVENT" "http://${APPLIANCE_HOST}:8084/events" --max-time 5; then
    print_result "Windows Events HTTP Send" "PASS" "Sent to port 8084/TCP"
    
    # Wait for processing
    sleep 2
    
    # Check metrics
    WINDOWS_COUNT=$(curl -s "http://${APPLIANCE_HOST}:${APPLIANCE_PORT}/api/metrics" | jq -r '.windows_events_received // 0' 2>/dev/null || echo "0")
    if [ "$WINDOWS_COUNT" -gt 0 ]; then
        print_result "Windows Events Processing" "PASS" "$WINDOWS_COUNT events received"
    else
        print_result "Windows Events Processing" "FAIL" "No Windows events in metrics"
    fi
else
    print_result "Windows Events HTTP Send" "FAIL" "Cannot send to port 8084/TCP"
fi

# Test 7: Service Status Check
echo -e "${BLUE}⚙️  Testing Service Status...${NC}"

SERVICES=("fluent-bit" "goflow2" "telegraf" "vector" "nginx" "config-service")
for service in "${SERVICES[@]}"; do
    # Check if service is running in container (if we can access it)
    if curl -s "http://${APPLIANCE_HOST}:${APPLIANCE_PORT}/api/system/status" | jq -r ".services.\"$service\".status" 2>/dev/null | grep -q "running"; then
        print_result "Service: $service" "PASS" "Running"
    else
        print_result "Service: $service" "WARN" "Status unknown or not running"
    fi
done

# Test 8: Port Connectivity Check
echo -e "${BLUE}🔌 Testing Port Connectivity...${NC}"

PORTS=(
    "1514:UDP:Syslog"
    "2055:UDP:NetFlow"
    "4739:UDP:IPFIX" 
    "6343:UDP:sFlow"
    "162:UDP:SNMP Traps"
    "8084:TCP:Windows Events"
    "${APPLIANCE_PORT}:TCP:Web Interface"
)

for port_info in "${PORTS[@]}"; do
    IFS=':' read -r port protocol service <<< "$port_info"
    
    if [ "$protocol" = "TCP" ]; then
        if nc -z -w3 "$APPLIANCE_HOST" "$port" 2>/dev/null; then
            print_result "Port $port ($service)" "PASS" "$protocol port open"
        else
            print_result "Port $port ($service)" "FAIL" "$protocol port closed or filtered"
        fi
    else
        # UDP port testing is more complex, just report as testable
        print_result "Port $port ($service)" "WARN" "$protocol port (requires data test)"
    fi
done

# Test 9: Data Flow Verification
echo -e "${BLUE}📊 Testing Data Flow Metrics...${NC}"

METRICS_RESPONSE=$(curl -s "http://${APPLIANCE_HOST}:${APPLIANCE_PORT}/api/metrics" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$METRICS_RESPONSE" ]; then
    print_result "Metrics API Response" "PASS" "Metrics endpoint responding"
    
    # Check for key metrics
    CPU_USAGE=$(echo "$METRICS_RESPONSE" | jq -r '.cpu_usage // "unknown"' 2>/dev/null)
    MEMORY_USAGE=$(echo "$METRICS_RESPONSE" | jq -r '.memory_usage // "unknown"' 2>/dev/null)
    UPTIME=$(echo "$METRICS_RESPONSE" | jq -r '.uptime // "unknown"' 2>/dev/null)
    
    echo -e "${BLUE}   System Metrics:${NC}"
    echo -e "   CPU Usage: $CPU_USAGE"
    echo -e "   Memory Usage: $MEMORY_USAGE"  
    echo -e "   Uptime: $UPTIME"
else
    print_result "Metrics API Response" "FAIL" "Cannot retrieve metrics"
fi

echo ""
echo -e "${BLUE}🎯 Test Summary${NC}"
echo -e "${BLUE}===============${NC}"
echo "Test completed for appliance: ${APPLIANCE_HOST}:${APPLIANCE_PORT}"
echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "1. Review any FAIL results above"
echo "2. Check appliance logs: docker logs <container-name>"
echo "3. Verify firewall/network connectivity for failed ports"
echo "4. For production deployment, use real telemetry sources"
echo ""
echo -e "${GREEN}✅ Telemetry test suite completed!${NC}"
