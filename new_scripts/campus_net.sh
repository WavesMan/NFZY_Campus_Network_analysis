#!/bin/sh

# 简化版校园网认证脚本
# 只保留最基础的双接口50%流量分流功能

# 配置参数
CONFIG_FILE="/etc/config/campus_net.json"
LOG_FILE="/var/log/campus_net.log"
CHECK_INTERVAL=300

# 认证服务器信息
AUTH_SERVER="192.1.1.55"
AUTH_PORT="801"
AUTH_PATH="/eportal/?c=ACSetting&a=Login"

# 网络接口
WAN1="phy1-sta0"
WAN2="phy1-sta1"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" | tee -a "$LOG_FILE"
}

# 获取接口信息
get_interface_info() {
    local interface=$1
    local ip=$(ip addr show dev "$interface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    local mac=$(ip link show dev "$interface" 2>/dev/null | grep 'link/ether' | awk '{print $2}')
    
    [ -z "$ip" ] || [ -z "$mac" ] && return 1
    
    mac=$(echo "$mac" | tr ':' '-')
    echo "$ip $mac"
}

# 校园网认证（正确解析302重定向URL中的RetCode和ACLogOut）
campus_auth() {
    local interface=$1 ip=$2 mac=$3 username=$4 password=$5
    
    log "INFO" "开始认证接口 $interface (IP: $ip, MAC: $mac)"
    
    local query_params="protocol=http:&hostname=$AUTH_SERVER&iTermType=1&wlanuserip=$ip&wlanacip=null&wlanacname=null&mac=$mac&ip=0.0.0.0&enAdvert=0&queryACIP=0&jsVersion=2.4.3&loginMethod=1"
    local encoded_username=$(echo ",0,$username" | sed 's/,/%2C/g; s/@/%40/g')
    local post_data="DDDDD=$encoded_username&upass=$password&R1=0&R2=0&R3=0&R6=0&para=00&0MKKey=123456"
    
    log "DEBUG" "认证请求: wget http://$AUTH_SERVER:$AUTH_PORT$AUTH_PATH&$query_params"
    log "DEBUG" "认证数据: $post_data"
    
    # 使用wget基本功能（BusyBox兼容）
    local response=$(wget -O - --timeout=10 --post-data="$post_data" \
        "http://$AUTH_SERVER:$AUTH_PORT$AUTH_PATH&$query_params" \
        --header="User-Agent: Mozilla/5.0" \
        --header="Content-Type: application/x-www-form-urlencoded" \
        --header="Referer: http://$AUTH_SERVER/" 2>&1)
    
    local exit_code=$?
    
    # 简化认证结果判断（BusyBox wget无法获取响应头）
    if [ $exit_code -eq 0 ]; then
        # 检查响应内容中的成功标识
        if echo "$response" | grep -q "success\|成功\|portal\|2\.htm"; then
            log "INFO" "✅ $interface 认证成功"
            return 0
        else
            log "WARNING" "⚠️  $interface 认证响应异常: $response"
            return 1
        fi
    else
        log "ERROR" "❌ $interface 认证失败 (退出码: $exit_code): $response"
        return 1
    fi
}

# 检查网络连通性（测试外网而不是认证服务器）
check_connectivity() {
    ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1
}

# 设置简单负载均衡
setup_simple_balance() {
    log "INFO" "设置简单负载均衡"
    
    # 清除现有标记规则
    iptables -t mangle -F PREROUTING 2>/dev/null
    
    # 50%流量标记
    iptables -t mangle -A PREROUTING -i br-lan -m statistic --mode random --probability 0.5 -j MARK --set-mark 0x1
    iptables -t mangle -A PREROUTING -i br-lan -m statistic --mode random --probability 0.5 -j MARK --set-mark 0x2
    
    # 清除现有路由规则
    ip rule del from all fwmark 0x1 2>/dev/null
    ip rule del from all fwmark 0x2 2>/dev/null
    
    # 添加路由规则
    ip rule add fwmark 0x1 table 101
    ip rule add fwmark 0x2 table 102
    
    # 获取网关地址
    local gw1=$(ip route show dev $WAN1 | grep 'default via' | awk '{print $3}' | head -1)
    local gw2=$(ip route show dev $WAN2 | grep 'default via' | awk '{print $3}' | head -1)
    
    # 设置路由表
    [ -n "$gw1" ] && ip route replace default via $gw1 dev $WAN1 table 101
    [ -n "$gw2" ] && ip route replace default via $gw2 dev $WAN2 table 102
    
    # 检查并加载nat模块（如果不存在）
    if ! iptables -t nat -L >/dev/null 2>&1; then
        log "WARNING" "nat表不存在，尝试加载模块"
        modprobe iptable_nat 2>/dev/null || true
    fi
    
    # 确保MASQUERADE规则（忽略错误）
    iptables -t nat -C POSTROUTING -o $WAN1 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o $WAN1 -j MASQUERADE 2>/dev/null || true
    iptables -t nat -C POSTROUTING -o $WAN2 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o $WAN2 -j MASQUERADE 2>/dev/null || true
    
    log "INFO" "简单负载均衡设置完成"
}

# 主循环
main_loop() {
    log "INFO" "启动校园网认证脚本"
    
    [ ! -f "$CONFIG_FILE" ] && { log "ERROR" "配置文件不存在"; exit 1; }
    
    local username=$(jq -r '.username' "$CONFIG_FILE" 2>/dev/null)
    local password=$(jq -r '.password' "$CONFIG_FILE" 2>/dev/null)
    
    [ -z "$username" ] || [ -z "$password" ] && { log "ERROR" "无法读取账号密码"; exit 1; }
    
    # 暂时注释掉负载均衡设置，先解决认证问题
    # setup_simple_balance
    
    while true; do
        if check_connectivity; then
            log "INFO" "网络连接正常"
        else
            log "WARNING" "网络异常，开始认证"
            
            for interface in "$WAN1" "$WAN2"; do
                if info=$(get_interface_info "$interface"); then
                    read ip mac <<EOF
$info
EOF
                    campus_auth "$interface" "$ip" "$mac" "$username" "$password" && \
                    log "INFO" "$interface 认证成功" || \
                    log "WARNING" "$interface 认证失败"
                fi
            done
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# 停止函数
stop_script() {
    log "INFO" "停止脚本"
    killall campus_net_simple.sh 2>/dev/null
}

# 脚本入口
case "$1" in
    start)
        main_loop &
        ;;
    stop)
        stop_script
        ;;
    status)
        if pgrep campus_net_simple.sh >/dev/null; then
            echo "运行中"
        else
            echo "未运行"
        fi
        ;;
    log)
        tail -f "$LOG_FILE"
        ;;
    *)
        echo "用法: $0 {start|stop|status|log}"
        exit 1
        ;;
esac
