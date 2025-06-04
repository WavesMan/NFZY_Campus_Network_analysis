## OpenWrt校园网自动登录脚本使用指南

### 一、自动安装方式

```bash
# 下载并运行安装脚本
wget https://raw.githubusercontent.com/WavesMan/NFZY_Campus_Network_analysis/main/OpenWrt/install_openwrt.sh
sh install_openwrt.sh
```

安装过程会提示：
1. 选择下载源(GitHub/Gitee/GitCode)
2. 输入校园网手机号
3. 输入校园网密码
4. 选择网络配置方式(默认/手动/自动检测)

### 二、手动安装方式（适用于自动安装失败）

1. 下载必要文件：
```bash
wget https://raw.githubusercontent.com/WavesMan/NFZY_Campus_Network_analysis/main/OpenWrt/auto_login.sh -O /etc/init.d/auto_login.sh
wget https://raw.githubusercontent.com/WavesMan/NFZY_Campus_Network_analysis/main/OpenWrt/net-ip.sh -O /etc/init.d/net-ip.sh
wget https://raw.githubusercontent.com/WavesMan/NFZY_Campus_Network_analysis/main/OpenWrt/auto_login.sample -O /etc/config/auto_login
chmod +x /etc/init.d/auto_login.sh /etc/init.d/net-ip.sh
```

2. 手动编辑配置文件：
```bash
vi /etc/config/auto_login
```
修改以下参数：
- USERNAME="手机号@unicom"
- PASSWORD="你的密码"
- NETWORK_GATEWAY="网关IP"
- NETWORK_INTERFACE="网络接口"

### 三、配置修改方法

如果配置项写入错误，可使用sed命令手动修改：

1. 修改手机号：
```bash
sed -i 's|USERNAME=".*"|USERNAME="新手机号@unicom"|' /etc/config/auto_login
```

2. 修改密码：
```bash
sed -i 's|PASSWORD=".*"|PASSWORD="新密码"|' /etc/config/auto_login
```

3. 修改网络设置：
```bash
sed -i 's|NETWORK_GATEWAY=".*"|NETWORK_GATEWAY="新网关IP"|' /etc/config/auto_login
sed -i 's|NETWORK_INTERFACE=".*"|NETWORK_INTERFACE="新网络接口"|' /etc/config/auto_login
```

### 四、常见问题排查

1. 配置未生效：
- 检查文件权限：`ls -l /etc/config/auto_login`
- 检查服务状态：`/etc/init.d/auto_login.sh status`

2. 登录失败：
- 查看日志：`logread | grep auto_login`
- 测试网络连接：`ping 192.1.1.55`

3. 手动测试登录：
```bash
/etc/init.d/auto_login.sh start
```

### 五、卸载方法
```bash
/etc/init.d/auto_login.sh stop
/etc/init.d/auto_login.sh disable
rm /etc/init.d/auto_login.sh /etc/init.d/net-ip.sh /etc/config/auto_login
```

更多帮助请参考项目仓库：
https://github.com/WavesMan/NFZY_Campus_Network_analysis
