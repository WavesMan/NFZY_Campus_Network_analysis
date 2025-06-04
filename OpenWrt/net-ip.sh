#!/bin/sh

# Enhanced network detection script with multiple fallback methods

# Load config file (if exists)
CONFIG_FILE="/etc/config/auto_login"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# Configuration (use values from config or fallback to defaults)
GATEWAY_FILTER="${NETWORK_GATEWAY:-10.14.127.255}"  # Gateway IP to filter
INTERFACE_PATTERN="${NETWORK_INTERFACE:-phy0-sta0}" # Interface name pattern

# Method 1: Get default gateway
get_gateway() {
    ip route show default | awk '/default/ {print $3}' | head -n1
}

# Method 2: Get IP by matching gateway subnet
get_ip_by_gateway() {
    local gateway=$1
    [ -z "$gateway" ] && return
    
    ip addr show | grep -w inet | grep -v "$GATEWAY_FILTER" | awk -v gw="$gateway" '{
        split($2, ip, "/");
        split(ip[1], ip_parts, ".");
        split(gw, gw_parts, ".");
        if(ip_parts[1]==gw_parts[1] && ip_parts[2]==gw_parts[2] && ip_parts[3]==gw_parts[3]) {
            print ip[1]
            exit
        }
    }'
}

# Method 3: Get IP by interface pattern
get_ip_by_ifname() {
    for ifname in $(ip link show | awk -F: '/^[0-9]+:/ {print $2}' | tr -d ' ' | grep -v lo); do
        if echo "$ifname" | grep -qE "$INTERFACE_PATTERN"; then
            ip addr show $ifname | grep -w inet | awk '{print $2}' | cut -d'/' -f1 | head -n1
            return
        fi
    done
}

# Method 4: Get first non-loopback, non-link-local IP
get_first_valid_ip() {
    ip addr show | grep -w inet | grep -v '127\.' | grep -v '169\.254\.' | \
    awk '{print $2}' | cut -d'/' -f1 | head -n1
}

# Main detection logic
detect_network_info() {
    # Try multiple methods to get IP
    local gateway=$(get_gateway)
    local ip=""
    
    # Method 1: By gateway subnet
    [ -z "$ip" ] && ip=$(get_ip_by_gateway "$gateway")
    
    # Method 2: By interface name pattern
    [ -z "$ip" ] && ip=$(get_ip_by_ifname)
    
    # Method 3: First valid IP
    [ -z "$ip" ] && ip=$(get_first_valid_ip)
    
    # Get MAC address
    local mac=""
    if [ -n "$ip" ]; then
        local iface=$(ip -o addr show | grep "$ip" | awk '{print $2}' | head -n1)
        [ -n "$iface" ] && mac=$(ip link show $iface | awk '/link\/ether/ {print $2}' | head -n1)
    fi
    
    # Output results
    echo "GATEWAY=$gateway"
    echo "INTERFACE=$iface"
    echo "IP=$ip"
    echo "MAC=$mac"
}

# Execute detection
detect_network_info
