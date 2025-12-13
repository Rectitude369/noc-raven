#!/bin/bash

# NOC-Raven Comprehensive Fix Script
# Fixes syslog ingestion, SNMP trap processing, and Web UI data display issues

set -e

echo "🦅 NOC-Raven Telemetry Fix Script"
echo "=================================="
echo ""

# Configuration
REPO_PATH="/Users/cnelson/Desktop/Dev/noc-raven"
REMOTE_HOST="100.124.172.111"
REMOTE_USER="techops"
REMOTE_PASS='$w33t@55T3a!'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Step 1: Fix Syslog Parser Configuration
fix_syslog_parser() {
    log_info "Fixing syslog parser configuration..."
    
    cat > "$REPO_PATH/config/parsers-fixed.conf" << 'EOF'
# NoC Raven - Enhanced Fluent Bit Parsers Configuration
# Supports multiple syslog formats from various vendors

# Standard RFC3164 parser - more lenient
[PARSER]
    Name                   syslog-rfc3164-custom
    Format                 regex
    Regex                  ^<(?<pri>[0-9]{1,5})>(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[^ ]*)(?:\[(?<pid>[0-9]+)\])?[:]? *(?<message>.*)$
    Time_Key               time
    Time_Format            %b %d %H:%M:%S
    Time_Keep              On

# Alternative RFC3164 format without PRI
[PARSER]
    Name                   syslog-rfc3164-notime
    Format                 regex
    Regex                  ^<(?<pri>[0-9]{1,5})>(?<host>[^ ]*) (?<ident>[^ ]*)(?:\[(?<pid>[0-9]+)\])?[:]? *(?<message>.*)$

# Standard RFC5424 parser - more lenient
[PARSER]
    Name                   syslog-rfc5424-custom
    Format                 regex
    Regex                  ^<(?<pri>[0-9]{1,5})>(?<version>[0-9]+)? ?(?<time>[^ ]*) (?<host>[^ ]*) (?<app>[^ ]*) (?<procid>[^ ]*) (?<msgid>[^ ]*) ?(?<sd>[\-\[].*?[\]]) ?(?<message>.*)$
    Time_Key               time
    Time_Format            %Y-%m-%dT%H:%M:%S.%L%z
    Time_Keep              On

# Cisco IOS/ASA format
[PARSER]
    Name                   cisco-ios
    Format                 regex
    Regex                  ^<(?<pri>[0-9]+)>(?<seq>[0-9]+): (?<time>.+): %(?<facility>[A-Z0-9_]+)-(?<severity>[0-9])-(?<mnemonic>[A-Z0-9_]+): (?<message>.*)$

# Very lenient catch-all parser
[PARSER]
    Name                   syslog-catchall
    Format                 regex
    Regex                  ^(?<message>.*)$

# JSON format (for structured logs)
[PARSER]
    Name                   json
    Format                 json
    Time_Key               timestamp
    Time_Format            %Y-%m-%dT%H:%M:%S.%L%z
    Time_Keep              On
EOF
    
    log_info "Created enhanced parser configuration"
}

# Step 2: Fix Fluent Bit Configuration
fix_fluentbit_config() {
    log_info "Fixing Fluent Bit configuration..."
    
    cat > "$REPO_PATH/config/fluent-bit-fixed.conf" << 'EOF'
# NoC Raven - Enhanced Fluent Bit Configuration
# Fixed for proper syslog ingestion from external sources

[SERVICE]
    Flush                   1
    Daemon                  Off
    Log_Level               info
    HTTP_Server             On
    HTTP_Listen             0.0.0.0
    HTTP_Port               2020
    Parsers_File            /opt/noc-raven/config/parsers-fixed.conf
    Storage.path            /data/fluent-bit/
    Storage.sync            normal
    Storage.checksum        off
    Storage.backlog.mem_limit 100MB
    Storage.metrics         on

# Syslog UDP Input - Listen on all interfaces
[INPUT]
    Name                    syslog
    Mode                    udp
    Listen                  0.0.0.0
    Port                    1514
    Parser                  syslog-rfc3164-custom
    Buffer_Chunk_Size       32KB
    Buffer_Max_Size         2MB
    Tag                     syslog.udp
    Mem_Buf_Limit          100MB

# Alternative UDP input using raw socket (more compatible)
[INPUT]
    Name                    udp
    Listen                  0.0.0.0
    Port                    1515
    Tag                     syslog.raw
    Format                  none
    Separator               "\n"

# Syslog TCP Input
[INPUT]
    Name                    tcp
    Listen                  0.0.0.0
    Port                    1514
    Tag                     syslog.tcp
    Format                  none
    Separator               "\n"

# Try multiple parsers for better compatibility
[FILTER]
    Name                    parser
    Match                   syslog.*
    Key_Name                log
    Parser                  syslog-rfc3164-custom
    Parser                  syslog-rfc5424-custom
    Parser                  cisco-ios
    Parser                  syslog-catchall
    Reserve_Data            On
    Preserve_Key            On

# Add metadata
[FILTER]
    Name                    modify
    Match                   *
    Add                     collector noc-raven
    Add                     timestamp ${FLB_NOW}

# Primary output - store locally with JSON format
[OUTPUT]
    Name                    file
    Match                   syslog.*
    Path                    /data/syslog
    File                    production-syslog.json
    Format                  json_lines

# Secondary output - store in readable format
[OUTPUT]
    Name                    file
    Match                   syslog.*
    Path                    /data/syslog
    File                    production-syslog.log
    Format                  plain

# Debug output to stdout (for testing)
[OUTPUT]
    Name                    stdout
    Match                   syslog.*
    Format                  json_lines
EOF
    
    log_info "Created enhanced Fluent Bit configuration"
}

# Step 3: Fix Telegraf SNMP Trap Configuration
fix_telegraf_snmp() {
    log_info "Fixing Telegraf SNMP configuration..."
    
    cat > "$REPO_PATH/config/telegraf-snmp-fixed.conf" << 'EOF'
# NoC Raven - Enhanced Telegraf Configuration for SNMP Traps

[global_tags]
  collector = "noc-raven"
  
[agent]
  interval = "10s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  hostname = "noc-raven"
  omit_hostname = false
  debug = true
  quiet = false

# SNMP Trap receiver - Primary
[[inputs.snmp_trap]]
  service_address = "udp://:162"
  timeout = "5s"
  version = "2c"
  community = "n0crav3n"
  
  # Path to MIB files
  path = ["/usr/share/snmp/mibs", "/opt/noc-raven/mibs"]
  
  # Translate OIDs to names
  translate_oids = true

# Alternative SNMP Trap listener using socket
[[inputs.socket_listener]]
  service_address = "udp://:1162"
  data_format = "value"
  data_type = "string"
  name_override = "snmp_trap_raw"

# JSON file output for SNMP traps
[[outputs.file]]
  files = ["/data/snmp/traps.json"]
  data_format = "json"
  namepass = ["snmp_trap*"]

# Plain text output for debugging
[[outputs.file]]
  files = ["/data/snmp/traps.log"]
  data_format = "influx"
  namepass = ["snmp_trap*"]

# HTTP output to local API
[[outputs.http]]
  url = "http://127.0.0.1:5004/api/telemetry/snmp"
  method = "POST"
  data_format = "json"
  namepass = ["snmp_trap*"]
  [outputs.http.headers]
    Content-Type = "application/json"
EOF
    
    log_info "Created enhanced Telegraf configuration"
}

# Step 4: Create enhanced API endpoints for real data
create_enhanced_api() {
    log_info "Creating enhanced API endpoints..."
    
    cat > "$REPO_PATH/config-service/telemetry-handler.go" << 'EOF'
package main

import (
    "encoding/json"
    "io"
    "net/http"
    "os"
    "path/filepath"
    "strings"
    "time"
    "bufio"
    "fmt"
    "sort"
)

// TelemetryData represents parsed telemetry data
type TelemetryData struct {
    Timestamp   time.Time              `json:"timestamp"`
    Host        string                 `json:"host"`
    Message     string                 `json:"message"`
    Severity    string                 `json:"severity,omitempty"`
    Facility    string                 `json:"facility,omitempty"`
    Application string                 `json:"application,omitempty"`
    Raw         map[string]interface{} `json:"raw,omitempty"`
}

// FlowData represents network flow data
type FlowData struct {
    SrcIP       string    `json:"src_ip"`
    DstIP       string    `json:"dst_ip"`
    SrcPort     int       `json:"src_port"`
    DstPort     int       `json:"dst_port"`
    Protocol    string    `json:"protocol"`
    Bytes       int64     `json:"bytes"`
    Packets     int64     `json:"packets"`
    Timestamp   time.Time `json:"timestamp"`
}

// ParseSyslogFile reads and parses syslog data
func ParseSyslogFile(filename string, limit int) ([]TelemetryData, error) {
    file, err := os.Open(filename)
    if err != nil {
        return nil, err
    }
    defer file.Close()

    var logs []TelemetryData
    scanner := bufio.NewScanner(file)
    
    for scanner.Scan() && len(logs) < limit {
        line := scanner.Text()
        if line == "" {
            continue
        }

        // Try to parse as JSON first
        var jsonData map[string]interface{}
        if err := json.Unmarshal([]byte(line), &jsonData); err == nil {
            log := TelemetryData{
                Timestamp: time.Now(),
                Raw:      jsonData,
            }
            
            if host, ok := jsonData["host"].(string); ok {
                log.Host = host
            }
            if msg, ok := jsonData["message"].(string); ok {
                log.Message = msg
            }
            if msg, ok := jsonData["ident"].(string); ok {
                log.Application = msg
            }
            
            logs = append(logs, log)
        } else {
            // Fallback to simple text parsing
            log := TelemetryData{
                Timestamp: time.Now(),
                Message:   line,
                Host:      "unknown",
            }
            logs = append(logs, log)
        }
    }

    // Reverse to show most recent first
    for i := len(logs)/2-1; i >= 0; i-- {
        opp := len(logs)-1-i
        logs[i], logs[opp] = logs[opp], logs[i]
    }

    return logs, scanner.Err()
}

// ParseFlowFile reads and parses flow data
func ParseFlowFile(filename string, limit int) ([]FlowData, error) {
    file, err := os.Open(filename)
    if err != nil {
        return nil, err
    }
    defer file.Close()

    var flows []FlowData
    scanner := bufio.NewScanner(file)
    
    for scanner.Scan() && len(flows) < limit {
        line := scanner.Text()
        if line == "" {
            continue
        }

        var jsonData map[string]interface{}
        if err := json.Unmarshal([]byte(line), &jsonData); err == nil {
            flow := FlowData{
                Timestamp: time.Now(),
            }
            
            if srcIP, ok := jsonData["SrcAddr"].(string); ok {
                flow.SrcIP = srcIP
            }
            if dstIP, ok := jsonData["DstAddr"].(string); ok {
                flow.DstIP = dstIP
            }
            if srcPort, ok := jsonData["SrcPort"].(float64); ok {
                flow.SrcPort = int(srcPort)
            }
            if dstPort, ok := jsonData["DstPort"].(float64); ok {
                flow.DstPort = int(dstPort)
            }
            if proto, ok := jsonData["Proto"].(float64); ok {
                switch int(proto) {
                case 6:
                    flow.Protocol = "TCP"
                case 17:
                    flow.Protocol = "UDP"
                case 1:
                    flow.Protocol = "ICMP"
                default:
                    flow.Protocol = fmt.Sprintf("Proto-%d", int(proto))
                }
            }
            if bytes, ok := jsonData["Bytes"].(float64); ok {
                flow.Bytes = int64(bytes)
            }
            if packets, ok := jsonData["Packets"].(float64); ok {
                flow.Packets = int64(packets)
            }
            
            flows = append(flows, flow)
        }
    }

    return flows, scanner.Err()
}

// GetTopTalkers analyzes flows for top talkers
func GetTopTalkers(flows []FlowData, limit int) []map[string]interface{} {
    talkers := make(map[string]int64)
    
    for _, flow := range flows {
        talkers[flow.SrcIP] += flow.Bytes
        talkers[flow.DstIP] += flow.Bytes
    }
    
    type kv struct {
        Key   string
        Value int64
    }
    
    var ss []kv
    for k, v := range talkers {
        ss = append(ss, kv{k, v})
    }
    
    sort.Slice(ss, func(i, j int) bool {
        return ss[i].Value > ss[j].Value
    })
    
    var result []map[string]interface{}
    for i, kv := range ss {
        if i >= limit {
            break
        }
        result = append(result, map[string]interface{}{
            "ip":    kv.Key,
            "bytes": kv.Value,
            "rank":  i + 1,
        })
    }
    
    return result
}

// HandleEnhancedFlows provides detailed flow data
func HandleEnhancedFlows(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    
    // Parse actual flow data
    flowFiles, _ := filepath.Glob("/data/flows/production-flows-*.log")
    var allFlows []FlowData
    
    for _, file := range flowFiles {
        flows, _ := ParseFlowFile(file, 1000)
        allFlows = append(allFlows, flows...)
    }
    
    // Calculate statistics
    protocolDist := make(map[string]int)
    portDist := make(map[int]int)
    
    for _, flow := range allFlows {
        protocolDist[flow.Protocol]++
        if flow.DstPort > 0 {
            portDist[flow.DstPort]++
        }
    }
    
    // Get top talkers
    topTalkers := GetTopTalkers(allFlows, 10)
    
    // Create response
    response := map[string]interface{}{
        "total_flows":        len(allFlows),
        "flows_per_second":   len(allFlows) / 3600,
        "top_talkers":        topTalkers,
        "protocol_distribution": protocolDist,
        "port_distribution": portDist,
        "recent_flows": allFlows,
    }
    
    json.NewEncoder(w).Encode(response)
}

// HandleEnhancedSyslog provides detailed syslog data
func HandleEnhancedSyslog(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    
    // Parse actual syslog data
    logs, _ := ParseSyslogFile("/data/syslog/production-syslog.json", 100)
    if len(logs) == 0 {
        logs, _ = ParseSyslogFile("/data/syslog/production-syslog.log", 100)
    }
    
    // Calculate statistics
    hostDist := make(map[string]int)
    severityDist := make(map[string]int)
    
    for _, log := range logs {
        hostDist[log.Host]++
        if log.Severity != "" {
            severityDist[log.Severity]++
        }
    }
    
    response := map[string]interface{}{
        "total_logs": len(logs),
        "recent_logs": logs,
        "top_hosts": hostDist,
        "severity_distribution": severityDist,
    }
    
    json.NewEncoder(w).Encode(response)
}
EOF
    
    log_info "Created enhanced API handlers"
}

# Step 5: Deploy fixes to production
deploy_to_production() {
    log_info "Deploying fixes to production container..."
    
    # Copy fixed configurations to production
    sshpass -p "$REMOTE_PASS" scp -q "$REPO_PATH/config/parsers-fixed.conf" "$REMOTE_USER@$REMOTE_HOST:/tmp/"
    sshpass -p "$REMOTE_PASS" scp -q "$REPO_PATH/config/fluent-bit-fixed.conf" "$REMOTE_USER@$REMOTE_HOST:/tmp/"
    sshpass -p "$REMOTE_PASS" scp -q "$REPO_PATH/config/telegraf-snmp-fixed.conf" "$REMOTE_USER@$REMOTE_HOST:/tmp/"
    
    # Apply configurations in container
    sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_HOST" << 'REMOTE_COMMANDS'
docker cp /tmp/parsers-fixed.conf noc-raven:/opt/noc-raven/config/
docker cp /tmp/fluent-bit-fixed.conf noc-raven:/opt/noc-raven/config/
docker cp /tmp/telegraf-snmp-fixed.conf noc-raven:/opt/noc-raven/config/

# Restart services
docker exec noc-raven bash -c "pkill -f fluent-bit; sleep 2; fluent-bit -c /opt/noc-raven/config/fluent-bit-fixed.conf &"
docker exec noc-raven bash -c "pkill -f telegraf; sleep 2; telegraf --config /opt/noc-raven/config/telegraf-snmp-fixed.conf &"
REMOTE_COMMANDS
    
    log_info "Configurations deployed and services restarted"
}

# Step 6: Test telemetry ingestion
test_telemetry() {
    log_info "Testing telemetry ingestion..."
    
    # Test syslog
    echo '<14>Test from fix script' | nc -u "$REMOTE_HOST" 1514
    sleep 2
    
    # Check if received
    result=$(sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_HOST" "docker exec noc-raven tail -1 /data/syslog/production-syslog.log")
    if [[ "$result" == *"Test from fix script"* ]]; then
        log_info "✓ Syslog ingestion working"
    else
        log_warn "✗ Syslog ingestion may not be working"
    fi
    
    # Test SNMP trap (simple test)
    # Note: This requires snmptrap tool to be installed
    if command -v snmptrap &> /dev/null; then
        snmptrap -v 2c -c n0crav3n "$REMOTE_HOST":162 '' 1.3.6.1.4.1.8072.2.3.0.1 1.3.6.1.4.1.8072.2.3.2.1 s "Test trap from fix script"
        sleep 2
        log_info "SNMP trap test sent"
    else
        log_warn "snmptrap command not found, skipping SNMP test"
    fi
}

# Main execution
main() {
    echo "Starting NOC-Raven telemetry fixes..."
    echo ""
    
    # Create fixes directory
    mkdir -p "$REPO_PATH/fixes"
    mkdir -p "$REPO_PATH/config"
    
    # Apply fixes
    fix_syslog_parser
    fix_fluentbit_config
    fix_telegraf_snmp
    create_enhanced_api
    
    # Deploy to production
    read -p "Deploy fixes to production container? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        deploy_to_production
        test_telemetry
    fi
    
    log_info "Fix script completed!"
    log_info "Next steps:"
    echo "  1. Rebuild the Docker image with fixed configurations"
    echo "  2. Test syslog ingestion from actual network devices"
    echo "  3. Configure SNMP devices to send traps to port 162"
    echo "  4. Update the web UI to use enhanced API endpoints"
}

# Run main function
main