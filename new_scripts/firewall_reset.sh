#!/bin/bash
# 防火墙重置和重建脚本
# 用于完全重置OpenWrt防火墙并重新构建校园网多播环境

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 备份目录
BACKUP_DIR="/etc/backup"
LOG_FILE="/var/log/firewall_reset.log"

# 日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    echo -e "[$timestamp] [$level] $message"
}

# 创建备份目录
create_backup_dir() {
    log "INFO" "创建备份目录: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
}

# 备份当前防火墙配置
backup_firewall() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    log "INFO" "开始备份当前防火墙配置..."
    
    # 备份iptables规则
    iptables-save > "$BACKUP_DIR/iptables-backup-$timestamp.rules" 2>/dev/null || true
    ip6tables-save > "$BACKUP_DIR/ip6tables-backup-$timestamp.rules" 2>/dev/null || true
    # 忽略IPv6备份错误
    
    # 备份mwan3配置
    if [ -f "/etc/config/mwan3" ]; then
        cp "/etc/config/mwan3" "$BACKUP_DIR/mwan3-backup-$timestamp" 2>/dev/null || true
    fi
    
    # 备份网络配置
    uci export network > "$BACKUP_DIR/network-backup-$timestamp" 2>/dev/null || true
    uci export firewall > "$BACKUP_DIR/firewall-backup-$timestamp" 2>/dev/null || true
    
    log "INFO" "防火墙配置备份完成"
}

# 完全清除防火墙规则
clear_firewall() {
    log "WARNING" "开始完全清除防火墙规则..."
    
    # 清除所有iptables规则（filter表）
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    
    # 清除ip6tables规则（忽略错误，因为可能不支持IPv6 NAT）
    ip6tables -F 2>/dev/null || true
    ip6tables -X 2>/dev/null || true
    ip6tables -t mangle -F 2>/dev/null || true
    ip6tables -t mangle -X 2>/dev/null || true
    
    # 设置默认策略
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    ip6tables -P INPUT ACCEPT 2>/dev/null || true
    ip6tables -P FORWARD ACCEPT 2>/dev/null || true
    ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
    
    log "INFO" "防火墙规则清除完成"
}

# 重建基础防火墙规则
rebuild_firewall() {
    log "INFO" "开始重建防火墙规则..."
    
    # 设置基本策略
    iptables -P INPUT DROP
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # 允许本地回环
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # 允许已建立的连接（使用conntrack替代state）
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # 允许内网(192.168.1.0/24)无限制访问路由器
    iptables -A INPUT -s 192.168.1.0/24 -j ACCEPT
    log "INFO" "内网(192.168.1.0/24)无限制访问规则已添加"
    
    # 允许ICMP (ping)
    iptables -A INPUT -p icmp -j ACCEPT
    
    # 允许SSH访问（从任何地方）
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    log "INFO" "基础防火墙规则重建完成"
}

# 重建NAT规则
rebuild_nat() {
    log "INFO" "开始重建NAT规则..."
    
    # 为两个WAN接口添加MASQUERADE规则
    iptables -t nat -A POSTROUTING -o nfdx_wan -j MASQUERADE 2>/dev/null || true
    iptables -t nat -A POSTROUTING -o nfdx_wan2 -j MASQUERADE 2>/dev/null || true
    
    # 如果特定接口不存在，使用通用规则
    if ! iptables -t nat -C POSTROUTING -o nfdx_wan -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -o phy1-sta0 -j MASQUERADE
    fi
    
    if ! iptables -t nat -C POSTROUTING -o nfdx_wan2 -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -o phy1-sta1 -j MASQUERADE
    fi
    
    log "INFO" "NAT规则重建完成"
}

# 配置内网转发
setup_forwarding() {
    log "INFO" "配置内网转发规则..."
    
    # 允许内网到外网的转发
    iptables -A FORWARD -s 192.168.1.0/24 -j ACCEPT
    iptables -A FORWARD -d 192.168.1.0/24 -j ACCEPT
    
    # 允许跨WAN接口的转发（用于负载均衡，使用conntrack）
    iptables -A FORWARD -i nfdx_wan -o nfdx_wan2 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -i nfdx_wan2 -o nfdx_wan -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    
    log "INFO" "内网转发规则配置完成"
}

# 重启网络服务
restart_network() {
    log "INFO" "重启网络服务..."
    /etc/init.d/network restart
    /etc/init.d/firewall restart
    sleep 3
    log "INFO" "网络服务重启完成"
}

# 测试网络连通性
test_connectivity() {
    log "INFO" "测试网络连通性..."
    
    # 测试内网连通性
    if ping -c 3 -W 2 192.168.1.1 > /dev/null 2>&1; then
        log "INFO" "✅ 路由器内网IP(192.168.1.1)可达"
    else
        log "ERROR" "❌ 路由器内网IP不可达"
    fi
    
    # 测试外网连通性
    if ping -c 3 -W 2 8.8.8.8 > /dev/null 2>&1; then
        log "INFO" "✅ 外网(8.8.8.8)可达"
    else
        log "WARNING" "⚠️  外网暂时不可达，可能需要校园网认证"
    fi
    
    # 显示当前防火墙状态
    log "INFO" "当前防火墙规则:"
    iptables -L -n -v | head -20 >> "$LOG_FILE"
    iptables -L -n -v | head -20
}

# 显示使用说明
show_usage() {
    echo -e "${GREEN}防火墙重置完成！${NC}"
    echo ""
    echo -e "${YELLOW}当前配置:${NC}"
    echo "- 路由器内网IP: 192.168.1.1"
    echo "- 内网网段: 192.168.1.0/24 (完全开放)"
    echo "- 双WAN负载均衡: nfdx_wan + nfdx_wan2"
    echo "- NAT MASQUERADE: 已启用"
    echo ""
    echo -e "${YELLOW}查看详细日志:${NC}"
    echo "tail -f /var/log/firewall_reset.log"
    echo ""
    echo -e "${YELLOW}查看防火墙规则:${NC}"
    echo "iptables -L -n -v"
    echo "iptables -t nat -L -n -v"
}

# 主函数
main() {
    echo -e "${GREEN}开始防火墙重置和重建...${NC}"
    
    create_backup_dir
    backup_firewall
    clear_firewall
    rebuild_firewall
    rebuild_nat
    setup_forwarding
    restart_network
    test_connectivity
    show_usage
    
    echo -e "${GREEN}防火墙重置完成！建议重启校园网认证脚本${NC}"
    echo -e "${YELLOW}重启认证: /etc/init.d/campus_net restart${NC}"
}

# 执行主函数
main "$@"
