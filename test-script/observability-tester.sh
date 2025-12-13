#!/bin/bash

#############################################################################
# Observability Stack Tester - Production Ready
# Description: Send test Syslog and NetFlow data to observability endpoints
# Author: Bytebot
# Version: 1.0.0
# Requirements: gum, nc (netcat), logger, curl, jq
#############################################################################

set -euo pipefail

# Color definitions for terminal output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_NAME="Observability Stack Tester"
readonly VERSION="1.0.0"
readonly LOG_DIR="$HOME/.obs-tester/logs"
readonly LOG_FILE="$LOG_DIR/obs-tester-$(date +%Y%m%d-%H%M%S).log"
readonly TEMP_DIR="/tmp/obs-tester-$$"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
mkdir -p "$TEMP_DIR"

# Cleanup function
cleanup() {
    local exit_code=$?
    rm -rf "$TEMP_DIR"
    if [ $exit_code -eq 0 ]; then
        log "INFO" "Session completed successfully"
    else
        log "ERROR" "Session terminated with errors (exit code: $exit_code)"
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        ERROR)
            echo -e "${RED}✗${NC} $message" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}✓${NC} $message"
            ;;
        INFO)
            echo -e "${BLUE}ℹ${NC} $message"
            ;;
        WARN)
            echo -e "${YELLOW}⚠${NC} $message"
            ;;
    esac
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in gum nc jq curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        echo -e "\n${YELLOW}Install missing dependencies:${NC}"
        echo "  brew install gum netcat jq curl"
        exit 1
    fi
}

# Display banner
show_banner() {
    clear
    gum style \
        --foreground 212 \
        --border double \
        --border-foreground 212 \
        --align center \
        --width 60 \
        --margin "1 2" \
        --padding "1 2" \
        "$SCRIPT_NAME" \
        "Version $VERSION" \
        "" \
        "Professional Observability Testing Tool"
    
    echo ""
}

# Main menu
main_menu() {
    local choice
    choice=$(gum choose \
        "📡 Send Syslog Data" \
        "🌊 Send NetFlow Data" \
        "🔔 Send SNMP Traps" \
        "📊 View Logs" \
        "🧹 Clear Logs" \
        "ℹ️  About" \
        "🚪 Exit")
    
    case "$choice" in
        "📡 Send Syslog Data")
            syslog_menu
            ;;
        "🌊 Send NetFlow Data")
            netflow_menu
            ;;
        "🔔 Send SNMP Traps")
            snmp_menu
            ;;
        "📊 View Logs")
            view_logs
            ;;
        "🧹 Clear Logs")
            clear_logs
            ;;
        "ℹ️  About")
            show_about
            ;;
        "🚪 Exit")
            exit 0
            ;;
    esac
}

# Syslog configuration menu
syslog_menu() {
    show_banner
    gum style --foreground 212 --bold "SYSLOG CONFIGURATION"
    echo ""
    
    # Get target IP
    local target_ip
    target_ip=$(gum input --placeholder "Enter target IP address (e.g., 192.168.1.100)" --value "127.0.0.1")
    
    # Validate IP
    if ! validate_ip "$target_ip"; then
        log "ERROR" "Invalid IP address: $target_ip"
        gum confirm "Return to main menu?" && main_menu
        return
    fi
    
    # Get port
    local port
    port=$(gum input --placeholder "Enter port (default: 514)" --value "514")
    
    # Validate port
    if ! validate_port "$port"; then
        log "ERROR" "Invalid port: $port"
        gum confirm "Return to main menu?" && main_menu
        return
    fi
    
    # Select protocol
    local protocol
    protocol=$(gum choose "UDP" "TCP")
    
    # Select syslog format
    local format
    format=$(gum choose \
        "RFC3164 (Traditional)" \
        "RFC5424 (Structured)" \
        "GELF (Graylog Extended Log Format)" \
        "CEF (Common Event Format)")
    
    # Select severity
    local severity
    severity=$(gum choose \
        "Emergency" "Alert" "Critical" "Error" \
        "Warning" "Notice" "Info" "Debug")
    
    # Select facility
    local facility
    facility=$(gum choose \
        "kern" "user" "mail" "daemon" "auth" \
        "syslog" "lpr" "news" "uucp" "cron" \
        "authpriv" "ftp" "local0" "local1" \
        "local2" "local3" "local4" "local5" \
        "local6" "local7")
    
    # Number of messages
    local count
    count=$(gum input --placeholder "Number of messages to send" --value "10")
    
    # Delay between messages
    local delay
    delay=$(gum input --placeholder "Delay between messages (seconds)" --value "1")
    
    # Custom message or auto-generate
    local message_type
    message_type=$(gum choose "Auto-generate test messages" "Custom message")
    
    local custom_message=""
    if [ "$message_type" = "Custom message" ]; then
        custom_message=$(gum input --placeholder "Enter your custom message")
    fi
    
    # Confirm and send
    echo ""
    gum style --foreground 212 --bold "CONFIGURATION SUMMARY"
    echo "Target: $target_ip:$port ($protocol)"
    echo "Format: $format"
    echo "Severity: $severity"
    echo "Facility: $facility"
    echo "Messages: $count (${delay}s delay)"
    echo ""
    
    if gum confirm "Send syslog messages?"; then
        send_syslog "$target_ip" "$port" "$protocol" "$format" \
                   "$severity" "$facility" "$count" "$delay" "$custom_message"
    else
        main_menu
    fi
}

# NetFlow configuration menu
netflow_menu() {
    show_banner
    gum style --foreground 212 --bold "NETFLOW CONFIGURATION"
    echo ""
    
    # Get target IP
    local target_ip
    target_ip=$(gum input --placeholder "Enter collector IP address" --value "127.0.0.1")
    
    # Validate IP
    if ! validate_ip "$target_ip"; then
        log "ERROR" "Invalid IP address: $target_ip"
        gum confirm "Return to main menu?" && main_menu
        return
    fi
    
    # Get port
    local port
    port=$(gum input --placeholder "Enter port (default: 2055)" --value "2055")
    
    # Validate port
    if ! validate_port "$port"; then
        log "ERROR" "Invalid port: $port"
        gum confirm "Return to main menu?" && main_menu
        return
    fi
    
    # Select NetFlow version
    local version
    version=$(gum choose "NetFlow v5" "NetFlow v9")
    
    # Source IP for flows
    local source_ip
    source_ip=$(gum input --placeholder "Source IP for flows" --value "10.0.0.1")
    
    # Destination IP for flows
    local dest_ip
    dest_ip=$(gum input --placeholder "Destination IP for flows" --value "10.0.0.2")
    
    # Sample rate
    local sample_rate
    sample_rate=$(gum input --placeholder "Sample rate (1:N)" --value "100")
    
    # Number of flows
    local flow_count
    flow_count=$(gum input --placeholder "Number of flows to generate" --value "100")
    
    # Flow rate (flows per second)
    local flow_rate
    flow_rate=$(gum input --placeholder "Flow rate (flows/second)" --value "10")
    
    echo ""
    gum style --foreground 212 --bold "CONFIGURATION SUMMARY"
    echo "Collector: $target_ip:$port"
    echo "Version: $version"
    echo "Source IP: $source_ip"
    echo "Dest IP: $dest_ip"
    echo "Sample Rate: 1:$sample_rate"
    echo "Total Flows: $flow_count"
    echo "Flow Rate: $flow_rate/sec"
    echo ""
    
    if gum confirm "Send NetFlow data?"; then
        send_netflow "$target_ip" "$port" "$version" "$source_ip" \
                    "$dest_ip" "$sample_rate" "$flow_count" "$flow_rate"
    else
        main_menu
    fi
}

# Send syslog messages
send_syslog() {
    local target_ip="$1"
    local port="$2"
    local protocol="$3"
    local format="$4"
    local severity="$5"
    local facility="$6"
    local count="$7"
    local delay="$8"
    local custom_message="$9"
    
    log "INFO" "Starting syslog transmission to $target_ip:$port"
    
    # Map severity to numeric value
    local severity_num
    case "$severity" in
        Emergency) severity_num=0 ;;
        Alert) severity_num=1 ;;
        Critical) severity_num=2 ;;
        Error) severity_num=3 ;;
        Warning) severity_num=4 ;;
        Notice) severity_num=5 ;;
        Info) severity_num=6 ;;
        Debug) severity_num=7 ;;
    esac
    
    # Map facility to numeric value
    local facility_num
    case "$facility" in
        kern) facility_num=0 ;;
        user) facility_num=1 ;;
        mail) facility_num=2 ;;
        daemon) facility_num=3 ;;
        auth) facility_num=4 ;;
        syslog) facility_num=5 ;;
        lpr) facility_num=6 ;;
        news) facility_num=7 ;;
        uucp) facility_num=8 ;;
        cron) facility_num=9 ;;
        authpriv) facility_num=10 ;;
        ftp) facility_num=11 ;;
        local0) facility_num=16 ;;
        local1) facility_num=17 ;;
        local2) facility_num=18 ;;
        local3) facility_num=19 ;;
        local4) facility_num=20 ;;
        local5) facility_num=21 ;;
        local6) facility_num=22 ;;
        local7) facility_num=23 ;;
    esac
    
    # Calculate priority
    local priority=$((facility_num * 8 + severity_num))
    
    echo ""
    gum spin --spinner dot --title "Sending syslog messages..." -- sleep 1
    
    local sent=0
    local failed=0
    
    for i in $(seq 1 "$count"); do
        local timestamp=$(date '+%b %d %H:%M:%S')
        local hostname=$(hostname)
        local tag="obs-tester[$$]"
        
        if [ -n "$custom_message" ]; then
            local message="$custom_message (Message $i/$count)"
        else
            local message="Test syslog message $i/$count from Observability Tester [Severity: $severity, Facility: $facility]"
        fi
        
        local syslog_message=""
        
        case "$format" in
            "RFC3164 (Traditional)")
                syslog_message="<$priority>$timestamp $hostname $tag: $message"
                ;;
            "RFC5424 (Structured)")
                local rfc5424_timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')
                syslog_message="<$priority>1 $rfc5424_timestamp $hostname $tag - ID$i [exampleSDID@32473 test=\"true\" seq=\"$i\"] $message"
                ;;
            "GELF (Graylog Extended Log Format)")
                syslog_message=$(cat <<EOF
{
  "version": "1.1",
  "host": "$hostname",
  "short_message": "$message",
  "timestamp": $(date +%s),
  "level": $((8 - severity_num)),
  "_facility": "$facility",
  "_seq": $i,
  "_total": $count
}
EOF
)
                ;;
            "CEF (Common Event Format)")
                syslog_message="CEF:0|ObservabilityTester|Tester|1.0|100|Test Event|$severity_num|src=$hostname msg=$message cnt=$i"
                ;;
        esac
        
        # Send the message
        if [ "$protocol" = "UDP" ]; then
            echo -n "$syslog_message" | nc -u -w1 "$target_ip" "$port" 2>/dev/null
        else
            echo "$syslog_message" | nc -w1 "$target_ip" "$port" 2>/dev/null
        fi
        
        if [ $? -eq 0 ]; then
            ((sent++))
            log "SUCCESS" "Sent message $i/$count"
            echo -ne "\r${GREEN}✓${NC} Sent: $sent/${count} ${RED}✗${NC} Failed: $failed"
        else
            ((failed++))
            log "ERROR" "Failed to send message $i/$count"
            echo -ne "\r${GREEN}✓${NC} Sent: $sent/${count} ${RED}✗${NC} Failed: $failed"
        fi
        
        if [ "$i" -lt "$count" ]; then
            sleep "$delay"
        fi
    done
    
    echo ""
    echo ""
    log "INFO" "Transmission complete. Sent: $sent, Failed: $failed"
    gum style --foreground 212 --bold "TRANSMISSION COMPLETE"
    echo "Successfully sent: $sent messages"
    echo "Failed: $failed messages"
    echo ""
    
    gum confirm "Return to main menu?" && main_menu
}

# SNMP configuration menu
snmp_menu() {
    show_banner
    gum style --foreground 212 --bold "SNMP TRAP CONFIGURATION"
    echo ""
    
    # Get target IP
    local target_ip
    target_ip=$(gum input --placeholder "Enter trap receiver IP address" --value "127.0.0.1")
    
    # Validate IP
    if ! validate_ip "$target_ip"; then
        log "ERROR" "Invalid IP address: $target_ip"
        gum confirm "Return to main menu?" && main_menu
        return
    fi
    
    # Get port
    local port
    port=$(gum input --placeholder "Enter port (default: 162)" --value "162")
    
    # Validate port
    if ! validate_port "$port"; then
        log "ERROR" "Invalid port: $port"
        gum confirm "Return to main menu?" && main_menu
        return
    fi
    
    # Select SNMP version
    local version
    version=$(gum choose "SNMPv1" "SNMPv2c" "SNMPv3")
    
    # Community string (for v1/v2c)
    local community="public"
    if [ "$version" != "SNMPv3" ]; then
        community=$(gum input --placeholder "Community string" --value "public")
    fi
    
    # Select trap type
    local trap_type
    trap_type=$(gum choose \
        "coldStart" \
        "warmStart" \
        "linkDown" \
        "linkUp" \
        "authenticationFailure" \
        "custom")
    
    # Number of traps
    local count
    count=$(gum input --placeholder "Number of traps to send" --value "10")
    
    # Delay between traps
    local delay
    delay=$(gum input --placeholder "Delay between traps (seconds)" --value "1")
    
    echo ""
    gum style --foreground 212 --bold "CONFIGURATION SUMMARY"
    echo "Receiver: $target_ip:$port"
    echo "Version: $version"
    if [ "$version" != "SNMPv3" ]; then
        echo "Community: $community"
    fi
    echo "Trap Type: $trap_type"
    echo "Count: $count (${delay}s delay)"
    echo ""
    
    if gum confirm "Send SNMP traps?"; then
        send_snmp "$target_ip" "$port" "$version" "$community" "$trap_type" "$count" "$delay"
    else
        main_menu
    fi
}

# Send SNMP traps
send_snmp() {
    local target_ip="$1"
    local port="$2"
    local version="$3"
    local community="$4"
    local trap_type="$5"
    local count="$6"
    local delay="$7"
    
    log "INFO" "Starting SNMP trap transmission to $target_ip:$port"
    
    # Check if snmptrap command is available
    if ! command -v snmptrap &> /dev/null; then
        log "WARN" "snmptrap command not found, using synthetic UDP packets"
        send_snmp_synthetic "$target_ip" "$port" "$version" "$community" "$trap_type" "$count" "$delay"
        return
    fi
    
    echo ""
    gum spin --spinner dot --title "Sending SNMP traps..." -- sleep 1
    
    local sent=0
    local failed=0
    
    # Map trap types to OIDs
    local trap_oid
    case "$trap_type" in
        "coldStart") trap_oid=".1.3.6.1.6.3.1.1.5.1" ;;
        "warmStart") trap_oid=".1.3.6.1.6.3.1.1.5.2" ;;
        "linkDown") trap_oid=".1.3.6.1.6.3.1.1.5.3" ;;
        "linkUp") trap_oid=".1.3.6.1.6.3.1.1.5.4" ;;
        "authenticationFailure") trap_oid=".1.3.6.1.6.3.1.1.5.5" ;;
        "custom") trap_oid=".1.3.6.1.4.1.99999.1" ;;
    esac
    
    for i in $(seq 1 "$count"); do
        local timestamp=$(date +%s)
        
        # Build snmptrap command based on version
        local cmd
        if [ "$version" = "SNMPv1" ]; then
            cmd="snmptrap -v 1 -c '$community' '$target_ip:$port' '$trap_oid' '127.0.0.1' 6 $i $timestamp .1.3.6.1.4.1.99999.1.1 s 'Test trap $i/$count from Observability Tester'"
        elif [ "$version" = "SNMPv2c" ]; then
            cmd="snmptrap -v 2c -c '$community' '$target_ip:$port' '' '$trap_oid' .1.3.6.1.4.1.99999.1.1 s 'Test trap $i/$count from Observability Tester' .1.3.6.1.4.1.99999.1.2 i $i"
        else
            # SNMPv3 would require more complex auth setup
            log "WARN" "SNMPv3 not fully implemented, using v2c"
            cmd="snmptrap -v 2c -c '$community' '$target_ip:$port' '' '$trap_oid' .1.3.6.1.4.1.99999.1.1 s 'Test trap $i/$count from Observability Tester'"
        fi
        
        # Execute command
        if eval "$cmd" 2>/dev/null; then
            ((sent++))
            log "SUCCESS" "Sent trap $i/$count"
            echo -ne "\r${GREEN}✓${NC} Sent: $sent/${count} ${RED}✗${NC} Failed: $failed"
        else
            ((failed++))
            log "ERROR" "Failed to send trap $i/$count"
            echo -ne "\r${GREEN}✓${NC} Sent: $sent/${count} ${RED}✗${NC} Failed: $failed"
        fi
        
        if [ "$i" -lt "$count" ]; then
            sleep "$delay"
        fi
    done
    
    echo ""
    echo ""
    log "INFO" "SNMP trap transmission complete. Sent: $sent, Failed: $failed"
    gum style --foreground 212 --bold "TRANSMISSION COMPLETE"
    echo "Successfully sent: $sent traps"
    echo "Failed: $failed traps"
    echo ""
    
    gum confirm "Return to main menu?" && main_menu
}

# Send synthetic SNMP traps (when snmptrap not available)
send_snmp_synthetic() {
    local target_ip="$1"
    local port="$2"
    local version="$3"
    local community="$4"
    local trap_type="$5"
    local count="$6"
    local delay="$7"
    
    log "INFO" "Using synthetic SNMP trap packets (snmptrap not available)"
    echo ""
    gum spin --spinner dot --title "Generating synthetic SNMP traps..." -- sleep 1
    
    local sent=0
    local failed=0
    
    for i in $(seq 1 "$count"); do
        # Generate a basic SNMPv2c trap PDU (simplified)
        local packet=$(generate_snmp_trap "$community" "$trap_type" "$i")
        
        # Send packet
        echo -n "$packet" | xxd -r -p | nc -u -w1 "$target_ip" "$port" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            ((sent++))
            log "SUCCESS" "Sent synthetic trap $i/$count"
            echo -ne "\r${GREEN}✓${NC} Sent: $sent/${count}"
        else
            ((failed++))
            log "ERROR" "Failed to send trap $i/$count"
            echo -ne "\r${GREEN}✓${NC} Sent: $sent/${count} ${RED}✗${NC} Failed: $failed"
        fi
        
        if [ "$i" -lt "$count" ]; then
            sleep "$delay"
        fi
    done
    
    echo ""
    echo ""
    log "INFO" "Synthetic SNMP trap transmission complete. Sent: $sent, Failed: $failed"
    gum style --foreground 212 --bold "TRANSMISSION COMPLETE"
    echo "Successfully sent: $sent traps"
    echo "Failed: $failed traps"
    echo "Note: Synthetic traps may not be fully compatible with all receivers"
    echo ""
    
    gum confirm "Return to main menu?" && main_menu
}

# Generate synthetic SNMP trap packet (hex)
generate_snmp_trap() {
    local community="$1"
    local trap_type="$2"
    local seq="$3"
    
    # This is a highly simplified SNMPv2c trap
    # Real SNMP encoding is complex (ASN.1 BER encoding)
    # This serves as a basic placeholder for testing
    
    # Convert community to hex
    local comm_hex=$(echo -n "$community" | xxd -p | tr -d '\n')
    local comm_len=$(printf '%02x' ${#community})
    
    # Simplified SNMPv2c trap structure
    local packet=""
    packet="${packet}30"  # SEQUENCE
    packet="${packet}40"  # Length (placeholder, would need calculation)
    packet="${packet}02"  # INTEGER (version)
    packet="${packet}01"  # Length
    packet="${packet}01"  # SNMPv2c = 1
    packet="${packet}04"  # OCTET STRING (community)
    packet="${packet}${comm_len}"  # Community length
    packet="${packet}${comm_hex}"  # Community string
    packet="${packet}a7"  # SNMPv2-Trap-PDU
    packet="${packet}20"  # Length (simplified)
    
    echo "$packet"
}

# Send NetFlow data
send_netflow() {
    local target_ip="$1"
    local port="$2"
    local version="$3"
    local source_ip="$4"
    local dest_ip="$5"
    local sample_rate="$6"
    local flow_count="$7"
    local flow_rate="$8"
    
    log "INFO" "Starting NetFlow transmission to $target_ip:$port"
    
    echo ""
    gum spin --spinner dot --title "Generating NetFlow data..." -- sleep 1
    
    local sent=0
    local failed=0
    local batch_size=10
    local delay=$(echo "scale=3; $batch_size / $flow_rate" | bc)
    
    for i in $(seq 1 $batch_size $flow_count); do
        local remaining=$((flow_count - i + 1))
        local current_batch=$((remaining < batch_size ? remaining : batch_size))
        
        if [ "$version" = "NetFlow v5" ]; then
            # Generate NetFlow v5 packet
            local packet=$(generate_netflow_v5 "$source_ip" "$dest_ip" "$i" "$current_batch" "$sample_rate")
        else
            # Generate NetFlow v9 packet
            local packet=$(generate_netflow_v9 "$source_ip" "$dest_ip" "$i" "$current_batch" "$sample_rate")
        fi
        
        # Send packet
        echo -n "$packet" | xxd -r -p | nc -u -w1 "$target_ip" "$port" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            sent=$((sent + current_batch))
            log "SUCCESS" "Sent batch starting at flow $i (${current_batch} flows)"
            echo -ne "\r${GREEN}✓${NC} Sent: $sent/${flow_count} flows"
        else
            failed=$((failed + current_batch))
            log "ERROR" "Failed to send batch starting at flow $i"
            echo -ne "\r${GREEN}✓${NC} Sent: $sent/${flow_count} ${RED}✗${NC} Failed: $failed"
        fi
        
        if [ "$sent" -lt "$flow_count" ]; then
            sleep "$delay"
        fi
    done
    
    echo ""
    echo ""
    log "INFO" "NetFlow transmission complete. Sent: $sent, Failed: $failed"
    gum style --foreground 212 --bold "TRANSMISSION COMPLETE"
    echo "Successfully sent: $sent flows"
    echo "Failed: $failed flows"
    echo ""
    
    gum confirm "Return to main menu?" && main_menu
}

# Generate NetFlow v5 packet (hex)
generate_netflow_v5() {
    local src_ip="$1"
    local dst_ip="$2"
    local seq="$3"
    local count="$4"
    local sample="$5"
    
    # Convert IP to hex
    local src_hex=$(printf '%02x%02x%02x%02x' $(echo "$src_ip" | tr '.' ' '))
    local dst_hex=$(printf '%02x%02x%02x%02x' $(echo "$dst_ip" | tr '.' ' '))
    
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
    header="${header}$(printf '%04x' $sample)"  # Sample Rate
    
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

# Generate NetFlow v9 packet (hex)
generate_netflow_v9() {
    local src_ip="$1"
    local dst_ip="$2"
    local seq="$3"
    local count="$4"
    local sample="$5"
    
    # This is a simplified NetFlow v9 generator
    # In production, you'd want a more complete implementation
    
    # Convert IP to hex
    local src_hex=$(printf '%02x%02x%02x%02x' $(echo "$src_ip" | tr '.' ' '))
    local dst_hex=$(printf '%02x%02x%02x%02x' $(echo "$dst_ip" | tr '.' ' '))
    
    # NetFlow v9 header
    local header=""
    header="${header}0009"  # Version
    header="${header}0002"  # Count (1 template + 1 data)
    header="${header}$(printf '%08x' $(date +%s))"  # SysUptime
    header="${header}$(printf '%08x' $(date +%s))"  # Unix Seconds
    header="${header}$(printf '%08x' $seq)"  # Sequence
    header="${header}00000001"  # Source ID
    
    # Template FlowSet
    local template=""
    template="${template}0000"  # FlowSet ID (0 = template)
    template="${template}0028"  # Length (40 bytes)
    template="${template}0100"  # Template ID 256
    template="${template}0005"  # Field Count
    template="${template}0008"  # Field: Source IP
    template="${template}0004"  # Length: 4
    template="${template}000c"  # Field: Dest IP
    template="${template}0004"  # Length: 4
    template="${template}0007"  # Field: Source Port
    template="${template}0002"  # Length: 2
    template="${template}000b"  # Field: Dest Port
    template="${template}0002"  # Length: 2
    template="${template}0002"  # Field: Packets
    template="${template}0004"  # Length: 4
    
    # Data FlowSet
    local data=""
    data="${data}0100"  # FlowSet ID (matches template)
    data="${data}$(printf '%04x' $((16 + count * 16)))"  # Length
    
    # Generate flow records
    for i in $(seq 1 $count); do
        local sport=$((1024 + RANDOM % 64000))
        local dport=$((80 + RANDOM % 10))
        local packets=$((10 + RANDOM % 1000))
        
        data="${data}${src_hex}"  # Source IP
        data="${data}${dst_hex}"  # Dest IP
        data="${data}$(printf '%04x' $sport)"  # Source Port
        data="${data}$(printf '%04x' $dport)"  # Dest Port
        data="${data}$(printf '%08x' $packets)"  # Packets
    done
    
    echo "${header}${template}${data}"
}

# Validate IP address
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if ((octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Validate port number
validate_port() {
    local port="$1"
    if [[ $port =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)); then
        return 0
    fi
    return 1
}

# View logs
view_logs() {
    show_banner
    gum style --foreground 212 --bold "LOG VIEWER"
    echo ""
    
    if [ ! -f "$LOG_FILE" ]; then
        log "WARN" "No logs found for current session"
        echo "Current session log: $LOG_FILE (empty)"
    else
        echo "Current session log: $LOG_FILE"
        echo ""
        gum pager < "$LOG_FILE"
    fi
    
    echo ""
    local choice
    choice=$(gum choose "View all logs" "View recent errors" "Return to main menu")
    
    case "$choice" in
        "View all logs")
            if ls -1 "$LOG_DIR"/*.log 2>/dev/null | head -1 > /dev/null; then
                local selected_log
                selected_log=$(ls -1t "$LOG_DIR"/*.log | gum choose)
                gum pager < "$selected_log"
            else
                log "WARN" "No log files found"
            fi
            ;;
        "View recent errors")
            if ls -1 "$LOG_DIR"/*.log 2>/dev/null | head -1 > /dev/null; then
                grep -h ERROR "$LOG_DIR"/*.log | tail -20 | gum pager
            else
                log "WARN" "No errors found in logs"
            fi
            ;;
        "Return to main menu")
            main_menu
            ;;
    esac
    
    gum confirm "Return to main menu?" && main_menu
}

# Clear logs
clear_logs() {
    show_banner
    gum style --foreground 212 --bold "CLEAR LOGS"
    echo ""
    
    local log_count=$(ls -1 "$LOG_DIR"/*.log 2>/dev/null | wc -l)
    
    if [ "$log_count" -eq 0 ]; then
        log "INFO" "No log files to clear"
        gum confirm "Return to main menu?" && main_menu
        return
    fi
    
    local log_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
    echo "Found $log_count log files (Total size: $log_size)"
    echo ""
    
    if gum confirm "Delete all log files?"; then
        rm -f "$LOG_DIR"/*.log
        log "SUCCESS" "Cleared all log files"
        echo ""
        gum confirm "Return to main menu?" && main_menu
    else
        main_menu
    fi
}

# Show about information
show_about() {
    show_banner
    gum style \
        --foreground 212 \
        --border normal \
        --border-foreground 240 \
        --padding "1 2" \
        --margin "1 2" \
        "ABOUT" \
        "" \
        "Observability Stack Tester v$VERSION" \
        "" \
        "A professional tool for testing observability" \
        "stack ingestion endpoints with Syslog and" \
        "NetFlow data generation capabilities." \
        "" \
        "Features:" \
        "• RFC3164/RFC5424 Syslog support" \
        "• GELF and CEF format support" \
        "• NetFlow v5 and v9 generation" \
        "• Comprehensive logging" \
        "• Beautiful terminal UI" \
        "" \
        "Created with ❤️ by Bytebot"
    
    echo ""
    gum confirm "Return to main menu?" && main_menu
}

# Main execution
main() {
    check_dependencies
    log "INFO" "Starting $SCRIPT_NAME v$VERSION"
    
    while true; do
        show_banner
        main_menu
    done
}

# Start the application
main