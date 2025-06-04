#!/bin/sh

# Load config file (if exists)
CONFIG_FILE="/etc/config/auto_login"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# Configuration (use values from config or fallback to defaults)
GATEWAY_FILTER="${NETWORK_GATEWAY:-10.14.127.255}"  # Gateway IP to filter for method 1
INTERFACE_PATTERN="${NETWORK_INTERFACE:-phy0-sta0}" # Interface name pattern for method 2

# Method 1: Identify by default gateway
get_ip_by_gateway() {
  GATEWAY=$(ip route show default | awk '/default/ {print $3}')
  ip addr show | grep -w inet | grep -v "$GATEWAY_FILTER" | awk -v gw="$GATEWAY" '{
    split($2, ip, "/");
    split(ip[1], ip_parts, ".");
    split(gw, gw_parts, ".");
    if(ip_parts[1]==gw_parts[1] && ip_parts[2]==gw_parts[2] && ip_parts[3]==gw_parts[3]) {
      print ip[1]
    }
  }' | head -n1
}

# Method 2: Identify by interface name pattern
get_ip_by_ifname() {
  for ifname in $(ip link show | awk -F: '/^[0-9]+:/ {print $2}' | tr -d ' ' | grep -v lo); do
    if echo "$ifname" | grep -qE "$INTERFACE_PATTERN"; then
      ip addr show $ifname | grep -w inet | awk '{print $2}' | cut -d'/' -f1 | head -n1
      return
    fi
  done
}

# Give priority to using Method 1; if it fails, use Method 2
CAMPUS_IP=$(get_ip_by_gateway)
[ -z "$CAMPUS_IP" ] && CAMPUS_IP=$(get_ip_by_ifname)

# Get MAC address for the interface
CAMPUS_MAC=""
if [ -n "$CAMPUS_IP" ]; then
    # Find interface with the IP
    IFACE=$(ip -o addr show | grep "$CAMPUS_IP" | awk '{print $2}')
    if [ -n "$IFACE" ]; then
        CAMPUS_MAC=$(ip link show $IFACE | awk '/link\/ether/ {print $2}' | head -n1)
    fi
fi

# Output in format expected by auto_login.sh
echo "IP=$CAMPUS_IP MAC=$CAMPUS_MAC"
