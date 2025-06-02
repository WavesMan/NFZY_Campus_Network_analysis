#!/bin/sh /etc/rc.common
# Script Name: auto_login.bash
# Description: Auto login to campus network on boot
# Author: WaveYo
# Version: 1.1

START=99
STOP=10

logger -t auto_login.bash "Script initializing"

# Load config file (must be created first)
CONFIG_FILE="/etc/config/auto_login"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    logger -t auto_login.bash "Error: Config file $CONFIG_FILE missing!"
    exit 1
fi

curl_request() {
    curl -X POST \
    "http://192.1.1.55:801/eportal/?c=ACSetting&a=Login&protocol=http:&hostname=192.1.1.55&iTermType=1&wlanuserip=10.14.88.96&wlanacip=null&wlanacname=null&mac=${MAC_ADDRESS}&ip=0.0.0.0&enAdvert=0&queryACIP=0&jsVersion=2.4.3&loginMethod=1" \
    -H "User-Agent: Mozilla/5.0" \
    --data-raw "DDDDD=%2C0%2C${USERNAME}&upass=${PASSWORD}&R1=0&R2=0&R3=0&R6=0&para=00&0MKKey=123456&buttonClicked=&redirect_url=&err_flag=&username=&password=&user=&cmd=&Login=&v6ip="

    if [ $? -eq 0 ]; then
        logger -t auto_login.bash "Login successful!"
        return 0
    else
        logger -t auto_login.bash "Login failed!"
        return 1
    fi
}

start() {
    # Wait for network connectivity
    logger -t auto_login.bash "Checking network..."
    until ping -c1 192.1.1.55 >/dev/null 2>&1; do
        sleep 3
    done

    # Retry up to 3 times
    local max_retries=3
    local retry_delay=5
    local attempt=1

    while [ $attempt -le $max_retries ]; do
        logger -t auto_login.bash "Attempting login (try $attempt)..."
        if curl_request; then
            break
        fi
        attempt=$((attempt+1))
        sleep $retry_delay
    done
}

stop() {
    logger -t auto_login.bash "Service stopped"
}
