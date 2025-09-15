#!/bin/bash
# 校园网认证和多播脚本安装程序

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/config"
BIN_DIR="/usr/bin"
INIT_DIR="/etc/init.d"
LOG_DIR="/var/log"

# 检查是否在OpenWrt环境
check_openwrt() {
    if [ ! -f "/etc/openwrt_release" ]; then
        echo -e "${RED}错误：这不是OpenWrt系统${NC}"
        exit 1
    fi
    echo -e "${GREEN}检测到OpenWrt系统${NC}"
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}安装必要依赖...${NC}"
    
    # # 更新软件包列表（静默模式）
    # opkg update >/dev/null 2>&1 || true
    
    # 安装curl（如果未安装）
    if ! opkg list-installed | grep -q "curl"; then
        echo -e "${YELLOW}安装curl...${NC}"
        opkg install curl 2>/dev/null || true
    fi
    
    # 安装jq（如果未安装）
    if ! opkg list-installed | grep -q "jq"; then
        echo -e "${YELLOW}安装jq...${NC}"
        opkg install jq 2>/dev/null || true
    fi
    
    # 安装mwan3（多播负载均衡）
    if ! opkg list-installed | grep -q "mwan3"; then
        echo -e "${YELLOW}安装mwan3用于多播负载均衡...${NC}"
        opkg install mwan3 2>/dev/null || true
    fi
    
    echo -e "${GREEN}依赖安装完成${NC}"
}

# 复制文件到系统目录
install_files() {
    echo -e "${YELLOW}安装脚本文件...${NC}"
    
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    
    # 复制主脚本
    cp "$SCRIPT_DIR/campus_net.sh" "$BIN_DIR/"
    chmod +x "$BIN_DIR/campus_net.sh"
    
    # 复制配置文件
    cp "$SCRIPT_DIR/campus_net.json" "$CONFIG_DIR/"
    
    # 复制init脚本
    cp "$SCRIPT_DIR/campus_net_init" "$INIT_DIR/campus_net"
    chmod +x "$INIT_DIR/campus_net"
    
    echo -e "${GREEN}文件安装完成${NC}"
}

# 配置服务
configure_service() {
    echo -e "${YELLOW}配置服务...${NC}"
    
    # 启用开机启动
    "$INIT_DIR/campus_net" enable
    
    echo -e "${GREEN}服务配置完成${NC}"
}

# 显示使用说明
show_usage() {
    echo -e "${GREEN}安装完成！${NC}"
    echo ""
    echo -e "${YELLOW}使用方法：${NC}"
    echo "启动服务:   /etc/init.d/campus_net start"
    echo "停止服务:   /etc/init.d/campus_net stop"
    echo "查看状态:   /etc/init.d/campus_net status"
    echo "查看日志:   tail -f /var/log/campus_net.log"
    echo ""
    echo -e "${YELLOW}手动运行：${NC}"
    echo "campus_net.sh start   # 启动脚本"
    echo "campus_net.sh stop    # 停止脚本"
    echo "campus_net.sh status  # 查看状态"
    echo "campus_net.sh log     # 查看日志"
    echo ""
    echo -e "${YELLOW}配置文件：${NC}"
    echo "编辑 /etc/config/campus_net.json 修改账号和设置"
}

# 主安装函数
main() {
    echo -e "${GREEN}开始安装校园网认证和多播脚本...${NC}"
    
    check_openwrt
    install_dependencies
    install_files
    configure_service
    show_usage
    
    echo -e "${GREEN}安装完成！建议重启路由器使配置生效${NC}"
}

# 执行安装
main "$@"
