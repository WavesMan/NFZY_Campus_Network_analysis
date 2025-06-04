#!/bin/sh /etc/rc.common
# Script Name: auto_login.sh
# Description: Auto login to campus network on boot with system initialization
# Author: WaveYo
# Version: 3.0

START=99
STOP=10

# System initialization functions
configure_opkg_sources() {
    log_info "Checking opkg sources configuration"
    
    # Backup current sources
    cp /etc/opkg/distfeeds.conf /etc/opkg/distfeeds.conf.bak
    
    # Replace with Tsinghua mirror
    sed -i 's|downloads.openwrt.org|mirrors.tuna.tsinghua.edu.cn/openwrt|g' /etc/opkg/distfeeds.conf
    
    # Verify replacement
    if grep -q "mirrors.tuna.tsinghua.edu.cn" /etc/opkg/distfeeds.conf; then
        log_info "Successfully configured Tsinghua mirror"
        return 0
    else
        log_error "Failed to configure Tsinghua mirror"
        return 1
    fi
}

update_packages() {
    log_info "Starting package updates"
    opkg update >/dev/null 2>&1
    log_info "Package lists updated"
    
    log_info "Starting package upgrades"
    upgradable_pkgs=$(opkg list-upgradable | awk '{print $1}')
    if [ -n "$upgradable_pkgs" ]; then
        opkg upgrade $upgradable_pkgs --force-overwrite --force-downgrade >/dev/null 2>&1
        log_info "Packages upgraded: $upgradable_pkgs"
    else
        log_info "No packages to upgrade"
    fi
}

install_required_packages() {
    # Define packages with alternatives
    PKG_MAP="
    curl:curl
    wget:wget-ssl:wget-nossl:uclient-fetch
    git:git
    bash:bash
    net-tools:busybox:iproute2
    "
    
    for pkg_line in $PKG_MAP; do
        pkg_name=$(echo $pkg_line | cut -d: -f1)
        alternatives=$(echo $pkg_line | cut -d: -f2-)
        
        # Check if any variant is already installed
        installed=false
        for alt in $(echo $alternatives | tr ":" " "); do
            if opkg list-installed | grep -q "^$alt "; then
                log_info "$pkg_name functionality provided by $alt (already installed)"
                installed=true
                break
            fi
        done
        
        if [ "$installed" = "false" ]; then
            # Try installing alternatives in order
            for alt in $(echo $alternatives | tr ":" " "); do
                log_info "Attempting to install $pkg_name using $alt"
                opkg install $alt --force-overwrite >/dev/null 2>&1
                if opkg list-installed | grep -q "^$alt "; then
                    log_info "Successfully installed $alt for $pkg_name functionality"
                    installed=true
                    break
                else
                    log_info "Failed to install $alt"
                fi
            done
            
            if [ "$installed" = "false" ]; then
                log_error "Could not install any package providing $pkg_name functionality"
            fi
        fi
    done
}

initialize_system() {
    log_info "Starting system initialization"
    
    # Step 1: Configure opkg sources
    if ! configure_opkg_sources; then
        log_error "Aborting initialization due to source configuration failure"
        return 1
    fi
    
    # Step 2: Update packages
    update_packages
    
    # Step 3: Install required packages
    install_required_packages
    
    log_info "System initialization completed"
    
    # Detect network information
    log_info "Detecting network information..."
    if [ -f "/etc/config/auto_login" ]; then
        . "/etc/config/auto_login"
        
        # Run net-ip.sh to get network info
        if [ -f "./net-ip.sh" ]; then
            network_info=$("${INSTALL_DIR}/net-ip.sh")
            DETECTED_IP=$(echo "$network_info" | grep -oE 'IP=[^ ]+' | cut -d= -f2)
            DETECTED_MAC=$(echo "$network_info" | grep -oE 'MAC=[^ ]+' | cut -d= -f2)
            NETWORK_GATEWAY=$(echo "$network_info" | grep -oE 'GATEWAY=[^ ]+' | cut -d= -f2)
            NETWORK_INTERFACE=$(echo "$network_info" | grep -oE 'INTERFACE=[^ ]+' | cut -d= -f2)
            
            # Update config file if values are detected
            if [ -n "$DETECTED_IP" ] && [ -n "$DETECTED_MAC" ]; then
                sed -i "/^DETECTED_IP=/c\DETECTED_IP=\"$DETECTED_IP\"" "/etc/config/auto_login"
                sed -i "/^DETECTED_MAC=/c\DETECTED_MAC=\"$DETECTED_MAC\"" "/etc/config/auto_login"
                [ -n "$NETWORK_GATEWAY" ] && sed -i "/^NETWORK_GATEWAY=/c\NETWORK_GATEWAY=\"$NETWORK_GATEWAY\"" "/etc/config/auto_login"
                [ -n "$NETWORK_INTERFACE" ] && sed -i "/^NETWORK_INTERFACE=/c\NETWORK_INTERFACE=\"$NETWORK_INTERFACE\"" "/etc/config/auto_login"
                log_info "Updated network info: IP=$DETECTED_IP MAC=$DETECTED_MAC Gateway=$NETWORK_GATEWAY Interface=$NETWORK_INTERFACE"
            else
                log_error "Failed to detect network information"
            fi
        else
            log_error "net-ip.sh not found, using configured values"
        fi
    fi
    
    return 0
}

# Logging functions
log_info() {
    logger -t auto_login.sh -p info "[INFO] $1"
}

log_error() {
    logger -t auto_login.sh -p error "[ERROR] $1"
}

log_debug() {
    logger -t auto_login.sh -p debug "[DEBUG] $1"
}

log_info "Script initializing (v2.0)"

# Load config file (must be created first)
CONFIG_FILE="/etc/config/auto_login"
if [ -f "$CONFIG_FILE" ]; then
    log_info "Loading config from $CONFIG_FILE"
    . "$CONFIG_FILE"
else
    log_error "Config file $CONFIG_FILE missing!"
    exit 1
fi

curl_request() {
    log_info "Starting campus network login"
    echo "Logging in to campus network..."
    
    # Create temp file for response
    RESPONSE_FILE="/tmp/auto_login_response_$$"
    
    # Make request and capture full response
    curl -X POST \
    "http://192.1.1.55:801/eportal/?c=ACSetting&a=Login&protocol=http:&hostname=192.1.1.55&iTermType=1&wlanuserip=${DETECTED_IP:-0.0.0.0}&wlanacip=null&wlanacname=null&mac=${DETECTED_MAC:-$MAC_ADDRESS}&ip=0.0.0.0&enAdvert=0&queryACIP=0&jsVersion=2.4.3&loginMethod=1" \
    -H "User-Agent: Mozilla/5.0" \
    --data-raw "DDDDD=%2C0%2C${USERNAME}&upass=${PASSWORD}&R1=0&R2=0&R3=0&R6=0&para=00&0MKKey=123456&buttonClicked=&redirect_url=&err_flag=&username=&password=&user=&cmd=&Login=&v6ip=" \
    -o "$RESPONSE_FILE" \
    -D "${RESPONSE_FILE}.headers" \
    -s -S -L  # Silent but show errors, follow redirects
    
    status=$?
    http_code=$(grep 'HTTP/[0-9]\.[0-9] [0-9]\{3\}' "${RESPONSE_FILE}.headers" | awk '{print $2}' | tail -1)
    response_content=$(cat "$RESPONSE_FILE")
    
    log_info "HTTP Status: $http_code"
    redirect_url=$(grep -i '^Location:' "${RESPONSE_FILE}.headers" | cut -d' ' -f2- | tr -d '\r')
    
    if [ -n "$redirect_url" ]; then
        log_info "Redirect URL: $redirect_url"
    fi
    
    # Always log response content for error analysis
    log_info "Response content (${#response_content} chars): $response_content"
    
    if [ $status -eq 0 ] && [ "$http_code" -eq 200 ]; then
        log_info "Login successful!"
        rm -f "$RESPONSE_FILE" "${RESPONSE_FILE}.headers"
        return 0
    elif [ "$http_code" -eq 302 ]; then
        log_error "Login redirected (302)! Status: $status, Location: $redirect_url, Response: $response_content"
        rm -f "$RESPONSE_FILE" "${RESPONSE_FILE}.headers"
        return 1
    else
        log_error "Login failed! Status: $status, HTTP: $http_code, Response: $response_content"
        rm -f "$RESPONSE_FILE" "${RESPONSE_FILE}.headers"
        return 1
    fi
}

start() {
    # Initialize system first
    if ! initialize_system; then
        log_error "System initialization failed"
        exit 1
    fi

    # Wait for network connectivity
    log_info "Checking network connectivity..."
    until ping -c1 192.1.1.55 >/dev/null 2>&1; do
        log_info "Network not ready, retrying in 3 seconds..."
        sleep 3
    done

    # Retry up to 3 times
    max_retries=3
    retry_delay=5
    attempt=1

    while [ $attempt -le $max_retries ]; do
        log_info "Attempting login (try $attempt of $max_retries)..."
        if curl_request; then
            log_info "Login completed successfully"
            break
        fi
        attempt=$((attempt+1))
        if [ $attempt -le $max_retries ]; then
            log_info "Waiting $retry_delay seconds before next attempt..."
            sleep $retry_delay
        fi
    done

    if [ $attempt -gt $max_retries ]; then
        log_error "All login attempts failed"
    fi
}

stop() {
    log_info "Service stopped"
}

# Direct run mode for testing
if [ "$1" = "run" ]; then
    log_info "Running in direct mode"
    start
    exit $?
fi
