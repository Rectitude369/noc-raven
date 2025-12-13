#!/bin/bash
# 🦅 NoC Raven - API Endpoint Testing Script
# Tests all API endpoints to verify they're working correctly

set -euo pipefail

# Configuration
readonly API_BASE="http://localhost:9080/api"
readonly TIMEOUT=10

# Colors for output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to test an endpoint
test_endpoint() {
    local endpoint="$1"
    local description="$2"
    local expected_status="${3:-200}"
    
    echo -n "Testing $description... "
    
    local response
    local status_code
    
    if response=$(curl -s -w "%{http_code}" --connect-timeout $TIMEOUT "$API_BASE$endpoint" 2>/dev/null); then
        status_code="${response: -3}"
        response_body="${response%???}"
        
        if [[ "$status_code" == "$expected_status" ]]; then
            echo -e "${GREEN}✅ PASS${NC} (HTTP $status_code)"
            ((TESTS_PASSED++))
            
            # Validate JSON response
            if echo "$response_body" | jq . >/dev/null 2>&1; then
                echo "   📄 Valid JSON response"
            else
                echo -e "   ${YELLOW}⚠️  Warning: Invalid JSON response${NC}"
            fi
        else
            echo -e "${RED}❌ FAIL${NC} (HTTP $status_code, expected $expected_status)"
            ((TESTS_FAILED++))
            echo "   Response: ${response_body:0:100}..."
        fi
    else
        echo -e "${RED}❌ FAIL${NC} (Connection failed)"
        ((TESTS_FAILED++))
    fi
}

# Test service restart endpoint
test_service_restart() {
    local service="$1"
    local description="$2"
    
    echo -n "Testing $description restart... "
    
    local response
    local status_code
    
    if response=$(curl -s -w "%{http_code}" --connect-timeout $TIMEOUT -X POST "$API_BASE/services/$service/restart" 2>/dev/null); then
        status_code="${response: -3}"
        response_body="${response%???}"
        
        if [[ "$status_code" == "200" ]]; then
            echo -e "${GREEN}✅ PASS${NC} (HTTP $status_code)"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}❌ FAIL${NC} (HTTP $status_code)"
            ((TESTS_FAILED++))
            echo "   Response: ${response_body:0:100}..."
        fi
    else
        echo -e "${RED}❌ FAIL${NC} (Connection failed)"
        ((TESTS_FAILED++))
    fi
}

echo "🦅 NoC Raven API Endpoint Testing"
echo "=================================="
echo "Testing API endpoints at: $API_BASE"
echo ""

# Test core endpoints
echo "📋 Core API Endpoints:"
test_endpoint "/config" "Configuration endpoint"
test_endpoint "/system/status" "System status endpoint"
test_endpoint "/services" "Services list endpoint"

echo ""
echo "📊 Telemetry Data Endpoints:"
test_endpoint "/flows" "NetFlow data endpoint"
test_endpoint "/syslog" "Syslog data endpoint"
test_endpoint "/snmp" "SNMP data endpoint"
test_endpoint "/windows" "Windows Events endpoint"
test_endpoint "/metrics" "System metrics endpoint"
test_endpoint "/buffer" "Buffer status endpoint"

echo ""
echo "🔧 Service Management Endpoints:"
test_service_restart "fluent-bit" "Syslog service"
test_service_restart "goflow2" "NetFlow service"
test_service_restart "telegraf" "SNMP service"
test_service_restart "vector" "Windows Events service"

echo ""
echo "📈 Test Results Summary:"
echo "========================"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo -e "Total Tests:  $((TESTS_PASSED + TESTS_FAILED))"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}🎉 All tests passed! API endpoints are working correctly.${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}❌ Some tests failed. Check the API endpoints and container logs.${NC}"
    echo ""
    echo "Troubleshooting tips:"
    echo "1. Ensure the container is running: docker ps"
    echo "2. Check container logs: docker logs noc-raven"
    echo "3. Verify port mapping: curl http://localhost:9080"
    echo "4. Check config service: curl http://localhost:9080/api/config"
    exit 1
fi
