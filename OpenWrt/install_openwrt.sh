#!/bin/sh

# OpenWrt Auto Install Script
# Purpose: Install campus network auto login scripts

# Check if running on OpenWrt
if [ ! -f "/etc/openwrt_release" ]; then
    echo "Error: This script must run on OpenWrt system!"
    exit 1
fi

# Repository URLs (ash compatible format) - dev branch
REPO_CHOICES="\
GitHub,https://raw.githubusercontent.com/WavesMan/NFZY_Campus_Network_analysis/dev/OpenWrt \
Gitee,https://gitee.com/waves-man/NFZY_Campus_Network_analysis/raw/dev/OpenWrt \
GitCode,https://gitcode.com/api/v5/repos/WavesMan/NFZY_Campus_Network_analysis/raw/OpenWrt?ref=dev"

# Let user select repository
echo "Available download sources:"
count=1
for repo in $REPO_CHOICES; do
    name=${repo%,*}
    echo "$count. $name"
    count=$((count+1))
done

read -p "Select source (1-3): " choice
case $choice in
    1|2|3)
        selected=$(echo "$REPO_CHOICES" | cut -d' ' -f$choice)
        REPO_URL=${selected#*,}
        ;;
    *)
        echo "Invalid selection, using GitHub as default"
        REPO_URL="https://raw.githubusercontent.com/WavesMan/NFZY_Campus_Network_analysis/dev/OpenWrt"
        ;;
esac

# Installation directories
INSTALL_DIR="/etc/init.d"
CONFIG_DIR="/etc/config"

# Download and install script files
install_script() {
    local script_name=$1
    echo "Downloading ${script_name}..."
    
    if curl -s -L -H 'Accept: application/json' "${REPO_URL}/${script_name}" -o "${INSTALL_DIR}/${script_name}"; then
        chmod +x "${INSTALL_DIR}/${script_name}"
        echo "Successfully installed ${script_name}"
    else
        echo "Failed to download ${script_name}!"
        exit 1
    fi
}

# Install configuration file
install_config() {
    echo "Configuring campus network login..."
    
    # Download config template
    if ! curl -s -L -H 'Accept: application/json' "${REPO_URL}/auto_login.sample" -o "${CONFIG_DIR}/auto_login"; then
        echo "Failed to download config template!"
        exit 1
    fi
    
    # Get user input
    read -p "Enter campus network phone number: " phone
    read -s -p "Enter campus network password: " password
    echo ""

    # Network configuration
    echo "Network configuration options:"
    echo "1. Use defaults (Gateway: 10.14.127.255, Interface: phy0-sta0)"
    echo "2. Enter custom values"
    echo "3. Auto-detect (requires net-ip.sh)"
    read -p "Select network config method (1-3): " net_choice

    case $net_choice in
        1)
            gateway="10.14.127.255"
            interface="phy0-sta0"
            ;;
        2)
            read -p "Enter network gateway: " gateway
            read -p "Enter network interface: " interface
            ;;
        3)
            echo "Auto-detecting network info..."
            temp_info=$("${INSTALL_DIR}/net-ip.sh")
            gateway=$(echo "$temp_info" | grep "GATEWAY=" | cut -d= -f2)
            interface=$(echo "$temp_info" | grep "INTERFACE=" | cut -d= -f2)
            echo "Detected - Gateway: $gateway, Interface: $interface"
            read -p "Use these values? [Y/n]: " confirm
            if [[ "$confirm" =~ ^[Nn]$ ]]; then
                read -p "Enter network gateway: " gateway
                read -p "Enter network interface: " interface
            fi
            ;;
        *)
            echo "Invalid choice, using defaults"
            gateway="10.14.127.255"
            interface="phy0-sta0"
            ;;
    esac

    # Update config file
    sed -i "s/<Enter your campus network mobile phone number>/${phone}/g" "${CONFIG_DIR}/auto_login"
    sed -i "s/<Enter your campus network password>/${password}/g" "${CONFIG_DIR}/auto_login"
    sed -i "s/^NETWORK_GATEWAY=.*/NETWORK_GATEWAY=\"${gateway}\"/g" "${CONFIG_DIR}/auto_login"
    sed -i "s/^NETWORK_INTERFACE=.*/NETWORK_INTERFACE=\"${interface}\"/g" "${CONFIG_DIR}/auto_login"
    
    echo "Config file updated with:"
    echo "Phone: ${phone}"
    echo "Gateway: ${gateway}"
    echo "Interface: ${interface}"
}

# Main installation process
echo "Starting campus network auto login installation..."
echo "Using source: $REPO_URL"

# Install script files
install_script "auto_login.sh"
install_script "net-ip.sh"

# Install config file
install_config

# Enable auto-start
echo "Enabling auto-start..."
/etc/init.d/auto_login.sh enable

echo "Installation completed!"
echo "You can test login manually with:"
echo "/etc/init.d/auto_login.sh start"
