#!/bin/sh /etc/rc.common
# Script Name: auto_login.sh
# Description: Auto login to campus network on boot
# Author: WaveYo
# Version: 2.0

START=99
STOP=10

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
    log_info "Starting login request"
    
    # Create temp file for response
    RESPONSE_FILE=$(mktemp)
    
    # Make request and capture full response (silent mode with -s)
    curl -s -X POST \
    "http://192.1.1.55:801/eportal/?c=ACSetting&a=Login&protocol=http:&hostname=192.1.1.55&iTermType=1&wlanuserip=10.14.88.96&wlanacip=null&wlanacname=null&mac=${MAC_ADDRESS}&ip=0.0.0.0&enAdvert=0&queryACIP=0&jsVersion=2.4.3&loginMethod=1" \
    -H "User-Agent: Mozilla/5.0" \
    --data-raw "DDDDD=%2C0%2C${USERNAME}&upass=${PASSWORD}&R1=0&R2=0&R3=0&R6=0&para=00&0MKKey=123456&buttonClicked=&redirect_url=&err_flag=&username=&password=&user=&cmd=&Login=&v6ip=" \
    -o "$RESPONSE_FILE" \
    -D "${RESPONSE_FILE}.headers"
    
    local status=$?
    local http_code=$(grep -Eo 'HTTP/[0-9]\.[0-9] [0-9]{3}' "${RESPONSE_FILE}.headers" | awk '{print $2}' | tail -1)
    local response_content=$(cat "$RESPONSE_FILE")
    
    log_info "HTTP Status: $http_code"
    # Only log full response in debug mode
    if [ "$LOG_LEVEL" = "debug" ]; then
        log_debug "Full response: $response_content"
    else
        log_info "Response length: ${#response_content} chars"
    fi
    
    if [ $status -eq 0 ] && [ "$http_code" -eq 200 ]; then
        log_info "Login successful! Response: $response_content"
        rm -f "$RESPONSE_FILE" "${RESPONSE_FILE}.headers"
        return 0
    else
        log_error "Login failed! Status: $status, HTTP: $http_code, Response: $response_content"
        rm -f "$RESPONSE_FILE" "${RESPONSE_FILE}.headers"
        return 1
    fi
}

start() {
    # Wait for network connectivity
    log_info "Checking network connectivity..."
    until ping -c1 192.1.1.55 >/dev/null 2>&1; do
        log_info "Network not ready, retrying in 3 seconds..."
        sleep 3
    done

    # Retry up to 3 times
    local max_retries=3
    local retry_delay=5
    local attempt=1

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
