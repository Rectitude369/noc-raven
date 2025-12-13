#!/bin/bash
# 🦅 NoC Raven Terminal Menu Interface
# Interactive ASCII terminal interface for network configuration when DHCP is not available
# Features fancy ASCII banner, colorful UI, and technology-themed graphics

set -euo pipefail

# Colors and styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
BLINK='\033[5m'

# Terminal control
CLEAR='\033[2J'
HOME='\033[H'
SAVE_CURSOR='\033[s'
RESTORE_CURSOR='\033[u'
HIDE_CURSOR='\033[?25l'
SHOW_CURSOR='\033[?25h'

# Configuration paths
CONFIG_DIR="/config"
NETWORK_CONFIG="$CONFIG_DIR/network.yml"
SYSTEM_CONFIG="$CONFIG_DIR/system.yml"

# Global variables
INTERFACE="eth0"
USE_DHCP="true"
STATIC_IP=""
NETMASK="255.255.255.0"
GATEWAY=""
DNS_SERVERS="8.8.8.8,8.8.4.4"
HOSTNAME="noc-raven-001"
TIMEZONE="UTC"

# Capability detection (NET_ADMIN required for ip/route)
has_cap_net_admin() {
    # CAP_NET_ADMIN is bit 12
    local cap_hex=$(awk '/CapEff/{print $2}' /proc/self/status 2>/dev/null || echo "")
    if [[ -z "$cap_hex" ]]; then return 1; fi
    local cap_dec=$((16#$cap_hex))
    local bit=$((1<<12))
    if (( (cap_dec & bit) != 0 )); then return 0; else return 1; fi
}

# Load existing configuration if available
load_config() {
    # Reset to defaults first (only if unset) to avoid stale values
    INTERFACE=${INTERFACE:-eth0}
    USE_DHCP=${USE_DHCP:-true}
    STATIC_IP=${STATIC_IP:-}
    NETMASK=${NETMASK:-255.255.255.0}
    GATEWAY=${GATEWAY:-}
    DNS_SERVERS=${DNS_SERVERS:-8.8.8.8,8.8.4.4}
    HOSTNAME=${HOSTNAME:-noc-raven-001}
    TIMEZONE=${TIMEZONE:-UTC}

    if [[ -f "$NETWORK_CONFIG" ]]; then
        # Robust, indentation-agnostic parsing of common keys under 'network:'
        while IFS= read -r line; do
            case "$line" in
                *"interface:"*)
                    INTERFACE=$(echo "$line" | sed -E 's/.*interface:[[:space:]]*//')
                    ;;
                *"dhcp:"*)
                    USE_DHCP=$(echo "$line" | sed -E 's/.*dhcp:[[:space:]]*//')
                    ;;
                *"static_ip:"*)
                    STATIC_IP=$(echo "$line" | sed -E 's/.*static_ip:[[:space:]]*//')
                    ;;
                *"netmask:"*)
                    NETMASK=$(echo "$line" | sed -E 's/.*netmask:[[:space:]]*//')
                    ;;
                *"gateway:"*)
                    GATEWAY=$(echo "$line" | sed -E 's/.*gateway:[[:space:]]*//')
                    ;;
                *"dns:"*)
                    # Extract inside brackets if present, remove spaces
                    DNS_SERVERS=$(echo "$line" | sed -E 's/.*dns:[[:space:]]*\[?([^\]]*)\]?/\1/' | tr -d ' ')
                    ;;
                *"hostname:"*)
                    HOSTNAME=$(echo "$line" | sed -E 's/.*hostname:[[:space:]]*//')
                    ;;
            esac
        done < "$NETWORK_CONFIG"
    fi
    
    if [[ -f "$SYSTEM_CONFIG" ]]; then
        while IFS= read -r line; do
            case "$line" in
                *"timezone:"*)
                    TIMEZONE=$(echo "$line" | sed -E 's/.*timezone:[[:space:]]*//')
                    ;;
            esac
        done < "$SYSTEM_CONFIG"
    fi
}

# Save configuration to files
save_config() {
    mkdir -p "$CONFIG_DIR"
    
    cat > "$NETWORK_CONFIG" << EOF
# NoC Raven Network Configuration
network:
  interface: $INTERFACE
  dhcp: $USE_DHCP
  static_ip: $STATIC_IP
  netmask: $NETMASK
  gateway: $GATEWAY
  dns: [$DNS_SERVERS]
  hostname: $HOSTNAME
EOF

    cat > "$SYSTEM_CONFIG" << EOF
# NoC Raven System Configuration
system:
  timezone: $TIMEZONE
  configured: true
  config_date: $(date -Iseconds)
EOF
}

# Clear screen and hide cursor
init_display() {
    printf "${CLEAR}${HOME}${HIDE_CURSOR}"
    trap 'printf "${SHOW_CURSOR}"; exit' INT TERM EXIT
}

# Restore cursor on exit
cleanup() {
    printf "${SHOW_CURSOR}${RESET}\n"
}

# ASCII art banner for NoC Raven with colors and effects
show_banner() {
    # Set TERM if not set to avoid tput errors
    export TERM=${TERM:-xterm}
    local width=$(tput cols 2>/dev/null || echo 80)
    local banner_width=80
    local padding=$(( (width - banner_width) / 2 ))
    local pad_str=$(printf "%*s" $padding "")
    
    printf "${HOME}${CYAN}${BOLD}\n"
    printf "${pad_str}╔═══════════════════════════════════════════════════════════════════════════════╗\n"
    printf "${pad_str}║${WHITE}                                                                               ${CYAN}║\n"
    printf "${pad_str}║${RED}${BOLD}    ███╗   ██╗ ██████╗  ██████╗    ██████╗  █████╗ ██╗   ██╗███████╗███╗   ██╗${CYAN}║\n"
    printf "${pad_str}║${RED}${BOLD}    ████╗  ██║██╔═══██╗██╔════╝    ██╔══██╗██╔══██╗██║   ██║██╔════╝████╗  ██║${CYAN}║\n"
    printf "${pad_str}║${YELLOW}${BOLD}    ██╔██╗ ██║██║   ██║██║         ██████╔╝███████║██║   ██║█████╗  ██╔██╗ ██║${CYAN}║\n"
    printf "${pad_str}║${GREEN}${BOLD}    ██║╚██╗██║██║   ██║██║         ██╔══██╗██╔══██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║${CYAN}║\n"
    printf "${pad_str}║${BLUE}${BOLD}    ██║ ╚████║╚██████╔╝╚██████╗    ██║  ██║██║  ██║ ╚████╔╝ ███████╗██║ ╚████║${CYAN}║\n"
    printf "${pad_str}║${MAGENTA}${BOLD}    ╚═╝  ╚═══╝ ╚═════╝  ╚═════╝    ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝${CYAN}║\n"
    printf "${pad_str}║${WHITE}                                                                               ${CYAN}║\n"
    printf "${pad_str}║${WHITE}${BOLD}              🦅 Telemetry Collection & Forwarding Appliance 🦅              ${CYAN}║\n"
    printf "${pad_str}║${GRAY}${DIM}                    High-Performance Venue Network Monitoring                  ${CYAN}║\n"
    printf "${pad_str}║${WHITE}                                                                               ${CYAN}║\n"
    printf "${pad_str}╚═══════════════════════════════════════════════════════════════════════════════╝${RESET}\n"
    printf "\n"
    
    # Network-themed decorative elements
    printf "${pad_str}${BLUE}${DIM}        ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐\n"
    printf "${pad_str}        │ Syslog  │════▶│NetFlow  │════▶│  SNMP   │════▶│Metrics  │\n"
    printf "${pad_str}        │UDP:514  │     │UDP:2055 │     │UDP:162  │     │TCP:9090 │\n"
    printf "${pad_str}        └─────────┘     └─────────┘     └─────────┘     └─────────┘\n"
    printf "${pad_str}              ║               ║               ║               ║\n"
    printf "${pad_str}              ╚═══════════════╩═══════════════╩═══════════════╝\n"
    printf "${pad_str}                                    ┃\n"
    printf "${pad_str}                            ${GREEN}${BOLD}🔒 VPN Tunnel 🔒\n"
    printf "${pad_str}                                    ┃\n"
    printf "${pad_str}                          ${WHITE}${BOLD}obs.rectitude.net${RESET}\n\n"
}

# Show system status with animated elements
show_status() {
    printf "${WHITE}${BOLD}┌──────────────── System Status ────────────────┐${RESET}\n"
    
    # Network interface status  
    local ip_addr=$(ip addr show "$INTERFACE" 2>/dev/null | grep 'inet ' | grep -v 'inet6' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    local link_status=$(ip link show "$INTERFACE" 2>/dev/null | grep 'state' | awk '{for(i=1;i<=NF;i++){if($i=="state"){print $(i+1); break}}}')
    
    if [[ -n "$ip_addr" ]]; then
        printf "${GREEN}├─ Interface: $INTERFACE ($ip_addr) [${link_status:-DOWN}]${RESET}\n"
    else
        printf "${RED}├─ Interface: $INTERFACE [NO IP ASSIGNED]${RESET}\n"
    fi
    
    # DHCP status
    if systemctl is-active --quiet dhcpcd 2>/dev/null || pgrep -f dhcp >/dev/null 2>&1; then
        printf "${GREEN}├─ DHCP: Active${RESET}\n"
    else
        printf "${YELLOW}├─ DHCP: Inactive${RESET}\n"
    fi
    
    # VPN status
    if pgrep -f openvpn >/dev/null 2>&1; then
        printf "${GREEN}├─ VPN: Connected${RESET}\n"
    else
        printf "${RED}├─ VPN: Disconnected${RESET}\n"
    fi
    
    # Services status
    local services=("fluent-bit" "goflow2" "telegraf" "vector" "nginx")
    for service in "${services[@]}"; do
        if pgrep -f "$service" >/dev/null 2>&1; then
            printf "${GREEN}├─ $service: Running${RESET}\n"
        else
            printf "${RED}├─ $service: Stopped${RESET}\n"
        fi
    done
    
    printf "${WHITE}${BOLD}└──────────────────────────────────────────────┘${RESET}\n\n"
}

# Display current configuration
show_config() {
    printf "${WHITE}${BOLD}┌────────── Current Configuration ──────────┐${RESET}\n"
    printf "${CYAN}├─ Interface:${WHITE} $INTERFACE${RESET}\n"
    printf "${CYAN}├─ DHCP:${WHITE} $USE_DHCP${RESET}\n"
    if [[ "$USE_DHCP" == "false" ]]; then
        printf "${CYAN}├─ Static IP:${WHITE} $STATIC_IP${RESET}\n"
        printf "${CYAN}├─ Netmask:${WHITE} $NETMASK${RESET}\n"
        printf "${CYAN}├─ Gateway:${WHITE} $GATEWAY${RESET}\n"
    fi
    printf "${CYAN}├─ DNS:${WHITE} $DNS_SERVERS${RESET}\n"
    printf "${CYAN}├─ Hostname:${WHITE} $HOSTNAME${RESET}\n"
    printf "${CYAN}├─ Timezone:${WHITE} $TIMEZONE${RESET}\n"
    printf "${WHITE}${BOLD}└────────────────────────────────────────────┘${RESET}\n\n"
}

# Main menu with animated elements
show_menu() {
    local menu_items=(
        "1. Network Configuration"
        "2. Hostname Settings"
        "3. Timezone Configuration" 
        "4. View System Status"
        "5. Test Network Connectivity"
        "6. Apply Configuration & Continue"
        "7. Exit to Shell"
        "8. Reset Saved Configuration (Factory Defaults)"
    )
    
    printf "${WHITE}${BOLD}┌─────────── NoC Raven Configuration Menu ───────────┐${RESET}\n"
    
    for item in "${menu_items[@]}"; do
        local num="${item:0:1}"
        local text="${item:3}"
        printf "${CYAN}│ ${YELLOW}${BOLD}$num${WHITE}. $text"
        printf "%*s${CYAN}│${RESET}\n" $(( 49 - ${#text} )) ""
    done
    
    printf "${WHITE}${BOLD}└─────────────────────────────────────────────────────┘${RESET}\n"
    printf "\n${CYAN}${BOLD}Select option [1-7]: ${WHITE}"
}

# Network configuration submenu
configure_network() {
    printf "${CLEAR}${HOME}"
    show_banner
    
    printf "${WHITE}${BOLD}╔═════════════════════════════════════════╗\n"
    printf "║         Network Configuration           ║\n"
    printf "╚═════════════════════════════════════════╝${RESET}\n\n"
    
    printf "${CYAN}${BOLD}Network Interface Configuration:${RESET}\n\n"
    
    # Interface selection
    printf "${YELLOW}Available interfaces:${RESET}\n"
    ip link show | grep -E '^[0-9]+:' | while read -r line; do
        local iface=$(echo "$line" | cut -d: -f2 | tr -d ' ')
        local state=$(echo "$line" | grep 'state' | awk '{for(i=1;i<=NF;i++){if($i=="state"){print $(i+1); break}}}' || echo "UNKNOWN")
        printf "${GRAY}  • $iface [$state]${RESET}\n"
    done
    
    printf "\n${CYAN}Current interface: ${WHITE}$INTERFACE${RESET}\n"
    read -p "$(printf "${CYAN}Enter interface name (or press Enter to keep current): ${WHITE}")" new_interface
    [[ -n "$new_interface" ]] && INTERFACE="$new_interface"
    printf "${RESET}"
    
    # DHCP vs Static IP
    printf "\n${CYAN}${BOLD}IP Address Configuration:${RESET}\n"
    printf "${YELLOW}1.${WHITE} Use DHCP (automatic)\n"
    printf "${YELLOW}2.${WHITE} Use static IP address\n"
    
    read -p "$(printf "\n${CYAN}Select option [1-2]: ${WHITE}")" ip_choice
    printf "${RESET}"
    
    case "$ip_choice" in
        1)
            USE_DHCP="true"
            printf "${GREEN}✓ DHCP enabled${RESET}\n"
            ;;
        2)
            USE_DHCP="false"
            printf "\n${CYAN}${BOLD}Static IP Configuration:${RESET}\n"
            
            read -p "$(printf "${CYAN}IP Address: ${WHITE}")" new_ip
            [[ -n "$new_ip" ]] && STATIC_IP="$new_ip"
            printf "${RESET}"
            
            read -p "$(printf "${CYAN}Netmask [$NETMASK]: ${WHITE}")" new_netmask
            [[ -n "$new_netmask" ]] && NETMASK="$new_netmask"
            printf "${RESET}"
            
            read -p "$(printf "${CYAN}Gateway: ${WHITE}")" new_gateway
            [[ -n "$new_gateway" ]] && GATEWAY="$new_gateway"
            printf "${RESET}"
            ;;
        *)
            printf "${RED}Invalid option${RESET}\n"
            sleep 2
            return
            ;;
    esac
    
    # DNS configuration
    printf "\n${CYAN}DNS Servers [$DNS_SERVERS]: ${WHITE}"
    read dns_input
    [[ -n "$dns_input" ]] && DNS_SERVERS="$dns_input"
    printf "${RESET}"
    
    printf "\n${GREEN}${BOLD}✓ Network configuration updated${RESET}\n"
    sleep 2
}

# Hostname configuration
configure_hostname() {
    printf "${CLEAR}${HOME}"
    show_banner
    
    printf "${WHITE}${BOLD}╔═════════════════════════════════════════╗\n"
    printf "║          Hostname Configuration         ║\n"
    printf "╚═════════════════════════════════════════╝${RESET}\n\n"
    
    printf "${CYAN}Current hostname: ${WHITE}$HOSTNAME${RESET}\n\n"
    
    printf "${GRAY}Hostname should follow these guidelines:${RESET}\n"
    printf "${GRAY}  • Use lowercase letters, numbers, and hyphens only${RESET}\n"
    printf "${GRAY}  • Start with a letter${RESET}\n"
    printf "${GRAY}  • Maximum 253 characters${RESET}\n"
    printf "${GRAY}  • Example: noc-raven-stadium-01${RESET}\n\n"
    
    read -p "$(printf "${CYAN}Enter new hostname: ${WHITE}")" new_hostname
    printf "${RESET}"
    
    if [[ -n "$new_hostname" ]]; then
        # Validate hostname
        if [[ "$new_hostname" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || [[ "$new_hostname" =~ ^[a-z][a-z0-9]*$ ]]; then
            HOSTNAME="$new_hostname"
            printf "${GREEN}${BOLD}✓ Hostname set to: $HOSTNAME${RESET}\n"
        else
            printf "${RED}${BOLD}✗ Invalid hostname format${RESET}\n"
            sleep 2
            return
        fi
    fi
    
    sleep 2
}

# Timezone configuration
configure_timezone() {
    printf "${CLEAR}${HOME}"
    show_banner
    
    printf "${WHITE}${BOLD}╔═════════════════════════════════════════╗\n"
    printf "║         Timezone Configuration          ║\n"
    printf "╚═════════════════════════════════════════╝${RESET}\n\n"
    
    printf "${CYAN}Current timezone: ${WHITE}$TIMEZONE${RESET}\n\n"
    
    printf "${YELLOW}Common timezones:${RESET}\n"
    local common_zones=(
        "UTC"
        "America/New_York"
        "America/Chicago" 
        "America/Denver"
        "America/Los_Angeles"
        "America/Phoenix"
        "Europe/London"
        "Europe/Paris"
        "Asia/Tokyo"
        "Australia/Sydney"
    )
    
    for i in "${!common_zones[@]}"; do
        printf "${GRAY}  $((i+1)). ${common_zones[i]}${RESET}\n"
    done
    
    printf "\n${CYAN}Select timezone (1-${#common_zones[@]}) or enter custom: ${WHITE}"
    read tz_input
    printf "${RESET}"
    
    if [[ "$tz_input" =~ ^[0-9]+$ ]] && [[ "$tz_input" -ge 1 ]] && [[ "$tz_input" -le "${#common_zones[@]}" ]]; then
        TIMEZONE="${common_zones[$((tz_input-1))]}"
        printf "${GREEN}${BOLD}✓ Timezone set to: $TIMEZONE${RESET}\n"
    elif [[ -n "$tz_input" ]] && [[ -f "/usr/share/zoneinfo/$tz_input" ]]; then
        TIMEZONE="$tz_input"
        printf "${GREEN}${BOLD}✓ Timezone set to: $TIMEZONE${RESET}\n"
    elif [[ -n "$tz_input" ]]; then
        printf "${RED}${BOLD}✗ Invalid timezone: $tz_input${RESET}\n"
        sleep 2
        return
    fi
    
    sleep 2
}

# Test network connectivity
test_connectivity() {
    printf "${CLEAR}${HOME}"
    show_banner
    
    printf "${WHITE}${BOLD}╔═════════════════════════════════════════╗\n"
    printf "║         Network Connectivity Test       ║\n"
    printf "╚═════════════════════════════════════════╝${RESET}\n\n"

    # First: local listener checks (inside container)
    echo -e "${CYAN}Local listener checks:${RESET}"
    declare -a listeners=(
        "UDP 514|ss -uln | grep -q ':514 '")
    listeners+=("UDP 2055|ss -uln | grep -q ':2055 '")
    listeners+=("UDP 4739|ss -uln | grep -q ':4739 '")
    listeners+=("UDP 6343|ss -uln | grep -q ':6343 '")
    listeners+=("UDP 162|ss -uln | grep -q ':162 '")
    listeners+=("TCP 8080|ss -tln | grep -q ':8080 '")
    listeners+=("TCP 8084|ss -tln | grep -q ':8084 '")

    for t in "${listeners[@]}"; do
        local lname="${t%|*}"
        local lcmd="${t#*|}"
        printf "${CYAN}Listening ${lname}...${RESET} "
        if bash -c "$lcmd" >/dev/null 2>&1; then
            printf "${GREEN}${BOLD}✓ LISTENING${RESET}\n"
        else
            printf "${RED}${BOLD}✗ NOT LISTENING${RESET}\n"
        fi
        sleep 0.3
    done

    echo
    # Second: remote reachability via VPN (skip if VPN not up)
    local have_vpn=false
    if pgrep -f openvpn >/dev/null 2>&1 || ip link show tun0 >/dev/null 2>&1; then
        have_vpn=true
    fi
    if [[ "$have_vpn" != "true" ]]; then
        echo -e "${YELLOW}VPN not connected; skipping remote reachability tests.${RESET}\n"
        printf "${YELLOW}Press Enter to continue...${RESET}"
        read
        return
    fi

    local tests=(
        "DNS Resolution|nslookup obs.rectitude.net"
        "Ping Test|ping -c 3 obs.rectitude.net"
        "Port 1514 (Syslog)|nc -zv obs.rectitude.net 1514"
        "Port 2055 (NetFlow)|nc -zv obs.rectitude.net 2055"
        "Port 6343 (sFlow)|nc -zv obs.rectitude.net 6343"
        "Port 162 (SNMP)|nc -zv obs.rectitude.net 162"
        "Port 8084 (HTTP)|nc -zv obs.rectitude.net 8084"
    )
    
    for test in "${tests[@]}"; do
        local name="${test%|*}"
        local cmd="${test#*|}"
        
        printf "${CYAN}Testing $name...${RESET} "
        
        if timeout 10s bash -c "$cmd" &>/dev/null; then
            printf "${GREEN}${BOLD}✓ PASS${RESET}\n"
        else
            printf "${RED}${BOLD}✗ FAIL${RESET}\n"
        fi
        
        sleep 1
    done
    
    printf "\n${YELLOW}Press Enter to continue...${RESET}"
    read
}

# Apply configuration and continue
apply_configuration() {
    printf "${CLEAR}${HOME}"
    show_banner
    
    printf "${WHITE}${BOLD}╔═════════════════════════════════════════╗\n"
    printf "║      Applying Configuration...          ║\n"
    printf "╚═════════════════════════════════════════╝${RESET}\n\n"
    
    # Save configuration
    save_config
    printf "${GREEN}✓ Configuration saved${RESET}\n"
    sleep 1
    
    # Set hostname
    if command -v hostname >/dev/null 2>&1; then
        if [[ $EUID -eq 0 ]]; then
            hostname "$HOSTNAME" 2>/dev/null || printf "${YELLOW}⚠ Could not set hostname${RESET}\n"
            printf "${GREEN}✓ Hostname set to $HOSTNAME${RESET}\n"
        else
            printf "${YELLOW}⚠ Hostname change skipped (not running as root)${RESET}\n"
        fi
        sleep 1
    fi
    
    # Set timezone (handle permissions gracefully)
    if [[ -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
        if [[ $EUID -eq 0 ]]; then
            ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime 2>/dev/null || printf "${YELLOW}⚠ Could not set system timezone${RESET}\n"
            echo "$TIMEZONE" > /etc/timezone 2>/dev/null || printf "${YELLOW}⚠ Could not write timezone file${RESET}\n"
            printf "${GREEN}✓ Timezone set to $TIMEZONE${RESET}\n"
        else
            printf "${YELLOW}⚠ Timezone change skipped (not running as root)${RESET}\n"
        fi
        sleep 1
    fi
    
    # Configure network
    if [[ "$USE_DHCP" == "true" ]]; then
        printf "${CYAN}Enabling DHCP on $INTERFACE...${RESET}\n"
        if command -v dhcpcd >/dev/null 2>&1; then
            if has_cap_net_admin; then
                dhcpcd "$INTERFACE" 2>/dev/null || true
            else
                printf "${YELLOW}⚠ Skipping DHCP apply (missing CAP_NET_ADMIN). Settings saved.${RESET}\n"
            fi
        fi
    else
        printf "${CYAN}Configuring static IP $STATIC_IP on $INTERFACE...${RESET}\n"
        
        # Convert netmask to CIDR if needed
        local cidr="24"  # Default to /24
        case "$NETMASK" in
            "255.255.255.0") cidr="24" ;;
            "255.255.0.0") cidr="16" ;;
            "255.0.0.0") cidr="8" ;;
            "255.255.255.128") cidr="25" ;;
            "255.255.255.192") cidr="26" ;;
            "255.255.255.224") cidr="27" ;;
            "255.255.255.240") cidr="28" ;;
            "255.255.255.248") cidr="29" ;;
            "255.255.255.252") cidr="30" ;;
        esac
        
        if has_cap_net_admin; then
            # Apply network configuration
            ip addr flush dev "$INTERFACE" 2>/dev/null || true
            ip addr add "$STATIC_IP/$cidr" dev "$INTERFACE" 2>/dev/null || printf "${YELLOW}⚠ Could not set IP${RESET}\n"
            ip link set dev "$INTERFACE" up 2>/dev/null || true
            
            if [[ -n "$GATEWAY" ]]; then
                ip route del default 2>/dev/null || true
                ip route add default via "$GATEWAY" 2>/dev/null || printf "${YELLOW}⚠ Could not set gateway${RESET}\n"
            fi
            
            # Update DNS if we have access
            if [[ -w /etc/resolv.conf ]]; then
                echo "# Generated by NoC Raven" > /etc/resolv.conf
                for dns in ${DNS_SERVERS//,/ }; do
                    echo "nameserver $dns" >> /etc/resolv.conf
                done
            fi
            printf "${GREEN}✓ Network configuration applied${RESET}\n"
        else
            printf "${YELLOW}⚠ Skipping IP/gateway apply (missing CAP_NET_ADMIN). Settings saved and will apply on next run when container has --cap-add NET_ADMIN.${RESET}\n"
        fi
    fi
    sleep 1
    
    printf "\n${GREEN}${BOLD}🎉 Configuration completed successfully!${RESET}\n"
    printf "${WHITE}NoC Raven is now ready to start collecting telemetry data.${RESET}\n\n"
    
    printf "${CYAN}${BOLD}Starting telemetry services...${RESET}\n"
    sleep 3
    
    # Signal to continue with service startup
    touch /tmp/config-complete
    exit 0
}

# Main program loop
main() {
    init_display
    trap cleanup EXIT
    
    # Load existing configuration
    load_config
    
    while true; do
        # Re-load on each loop so the UI reflects the latest saved values
        load_config
        printf "${CLEAR}${HOME}"
        show_banner
        printf "\n"  # Extra spacing
        show_status
        printf "\n"  # Extra spacing
        show_config
        printf "\n"  # Extra spacing
        show_menu
        
        # Simple input handling that works in all environments
        read choice
        
        case "$choice" in
            1) configure_network ;;
            2) configure_hostname ;;
            3) configure_timezone ;;
            4) 
                printf "${CLEAR}${HOME}"
                show_banner
                show_status
                printf "\n${YELLOW}Press Enter to continue...${RESET}"
                read
                ;;
            5) test_connectivity ;;
            6) apply_configuration ;;
            7) 
                printf "${GREEN}Exiting to shell...${RESET}\n"
                exit 0
                ;;
            8)
                printf "${YELLOW}${BOLD}Resetting saved configuration to factory defaults...${RESET}\n"
                rm -f "$NETWORK_CONFIG" "$SYSTEM_CONFIG" 2>/dev/null || true
                sleep 1
                printf "${GREEN}✓ Saved configuration cleared. Defaults will be used until you save new values.${RESET}\n"
                sleep 1
                ;;
            *)
                printf "${RED}Invalid option. Please try again.${RESET}\n"
                sleep 1
                ;;
        esac
    done
}

# Check if running as root for network operations (container-aware)
if [[ $EUID -ne 0 ]]; then
    # Check if we're in a container - if so, proceed with warning
    if [[ -f /.dockerenv ]] || [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]; then
        printf "${YELLOW}${BOLD}Warning: Running as non-root user in container environment.${RESET}\n"
        printf "${YELLOW}Some network operations may not be available.${RESET}\n"
        sleep 2
    else
        printf "${RED}${BOLD}Error: This script requires root privileges for network configuration.${RESET}\n"
        printf "${YELLOW}Please run with sudo or as root user.${RESET}\n"
        exit 1
    fi
fi

# Start the main program
main "$@"
