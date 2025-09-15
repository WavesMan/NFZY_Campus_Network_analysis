# OpenWrt 校园网认证和多播脚本

基于长沙南方职业学院校园网API分析，实现OpenWrt环境下的自动认证和带宽聚合功能。

## 功能特性

- ✅ 校园网自动认证（POST API）
- ✅ 多接口带宽聚合（phy1-sta0 + phy1-sta1）
- ✅ 定时检测网络状态
- ✅ 自动重连失效接口
- ✅ 详细运行日志记录
- ✅ 内网设备连通性保障
- ✅ mwan3负载均衡支持
- ✅ OpenWrt服务集成

## 系统要求

- OpenWrt 21.02 或更高版本
- curl、jq、mwan3 软件包
- 两个或以上无线接口（phy1-sta0, phy1-sta1）**[你的多播接口取决于校园网允许在线的最大设备与你路由器的参数]**

## 安装部署

如果执行本脚本后，出现内网设备无法连通外网、校园网网关、OpenWrt路由器等情况，运行脚本 `firewall_reset.sh` 重置防火墙规则，然后重新运行本脚本。 
```bash
chmod +x firewall_reset.sh
./firewall_reset.sh
```

### 自动安装

```bash
# 上传所有文件到OpenWrt路由器
scp -O campus_net.sh campus_net.json campus_net_init install.sh root@路由器IP:/tmp/

# 登录路由器并执行安装
ssh root@路由器IP
cd /tmp
chmod +x install.sh
./install.sh

# 如果终端显示“sh: ./xxx.sh: not found”，说明你的OpenWrt系统使用的是BusyBox，缺少一些标准工具。请执行以下命令：
opkg update
opkg install bash
```

### 手动安装

1. 复制文件到系统目录：
```bash
cp campus_net.sh /usr/bin/
cp campus_net.json /etc/config/
cp campus_net_init /etc/init.d/campus_net
chmod +x /usr/bin/campus_net.sh /etc/init.d/campus_net
```

2. 安装依赖：
```bash
opkg update
opkg install curl jq mwan3
```

3. 启用服务：
```bash
/etc/init.d/campus_net enable
/etc/init.d/campus_net start
```

## 配置文件说明

`/etc/config/campus_net.json`:
```json
{
  "username": "<your-phone>@unicom",
  "password": "<your-password>",
  // 校园网认证服务器
  "auth_server": "192.1.1.55",
  // 认证端口
  "auth_port": "801",
  "check_interval": 300,
  // OpenWrt 接入校园网接口名
  "interfaces": ["phy1-sta0", "phy1-sta1"], 
  "log_level": "INFO",
  "enable_multicast": true,
  "multicast_mode": "bandwidth_aggregation"
}
```

## 使用方法

### 服务管理
```bash
# 启动服务
/etc/init.d/campus_net start

# 停止服务
/etc/init.d/campus_net stop

# 查看状态
/etc/init.d/campus_net status

# 重启服务
/etc/init.d/campus_net restart
```

### 手动运行
```bash
# 启动脚本
campus_net.sh start

# 停止脚本
campus_net.sh stop

# 查看状态
campus_net.sh status

# 查看日志
campus_net.sh log
tail -f /var/log/campus_net.log
```

## 网络架构

### 接口配置
- `phy1-sta0` → `nfdx_wan` (WAN接口1)
- `phy1-sta1` → `nfdx_wan2` (WAN接口2)
- `br-lan` → 192.168.1.1/24 (LAN接口)

### 负载均衡
- 使用mwan3进行流量分配
- 50%流量走nfdx_wan，50%走nfdx_wan2
- 内网设备可通过任意WAN接口访问认证服务器

### 认证机制
- 每5分钟检测网络连通性
- 自动对两个接口进行校园网认证
- 支持认证失败重试

## 故障排除

### 查看日志
```bash
logread | grep campus_net
tail -f /var/log/campus_net.log
```

### 测试认证
```bash
# 手动测试单个接口认证
campus_net.sh start
```

### 网络诊断
```bash
# 检查接口状态
ip addr show phy1-sta0
ip addr show phy1-sta1

# 测试连通性
ping 8.8.8.8
```

## 注意事项

1. **账号安全**：配置文件包含明文密码，确保文件权限为600
2. **接口名称**：根据实际接口名称修改配置文件
3. **防火墙**：确保防火墙允许内网访问认证服务器
4. **日志轮转**：建议配置logrotate防止日志文件过大

## 技术支持

如遇问题请检查：
1. 网络接口是否正确配置
2. curl和jq是否安装
3. 防火墙规则是否允许认证流量
4. 查看详细日志获取错误信息

## 许可证

[MIT License](../LICENSE) - 详见LICENSE文件
