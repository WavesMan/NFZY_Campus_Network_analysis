# 长沙南方职业学院 校园网 分析工程

> **写在前面**
> 本次分析校园网分析工程，仅用于学习交流，未得到学校有关部门与相关人员授权，禁止用于商业用途。若校方联系要求，将会立即删除清档。
---

#### 目录
- [分析报告](#校园网api接口分析报告)
- [自动化登陆脚本](#基于校园网api接口分析构建的校园网自动化登陆脚本)
- [20250602142740分析报告](./2025-06-02_142740.md)

---

## 校园网API接口分析报告

### 1. 认证接口基础信息
#### 接口地址
```http
POST http://192.1.1.55:801/eportal/?c=ACSetting&a=Login
```
- **HTTP版本**：1.1（日志中无HTTP/2痕迹）
- **Keep-Alive**：启用（`Proxy-Connection: keep-alive`）
- **端口**：801（非标准HTTP端口）
  - **风险提示**：801端口常用于校园网临时认证，可能存在中间人攻击风险。


#### 请求方法
- **必需方法**：`POST`
- **兼容性**：不支持 `GET` 请求（返回 `405 Method Not Allowed`）

### 2. `upass`字段
- **日志现象**：明文传输（示例值`<password>`）
- **实际验证**：
  1. 抓包确认无前端加密（未调用`CryptoJS`等库）
  2. 修改密码长度测试（6位数字可登录，特殊字符未验证）

### 3. 请求头（Headers）关键字段

#### 3.1 设备类型逻辑
- **`iTermType` 无效**：无论传 `0`（PC）、`1`（手机）、`2`（平板），后台均返回 `PC` 类型。
- **`User-Agent` 无效**：即使伪造移动端 UA，设备类型仍为 PC。

#### 3.2 认证流程依赖项
| 参数/头域 | 是否必需 | 备注 |
|-----------|----------|------|
| `mac` | 是 | MAC 地址格式需为 `XX-XX-XX-XX-XX-XX` |
| `wlanuserip` | 是 | 内网 IP 需与客户端实际IP一致 |
| `Referer` | 是 | 必须来自认证页面域名 |
| `jsVersion` | 是 | 版本号错误可能导致 `400 Bad Request` |

### 分析结论：
- **明文传输**：密码（`upass`）和 MAC 地址未加密。
- **弱校验**：仅依赖 `Referer` 和 `jsVersion` 做简单防护。
- **设备类型伪造**：无法通过标准参数切换设备类型。
- **风险提示**：建议升级为 HTTPS。
- **无动态 Token**：增加 `CSRF-Token` 防止重放攻击。
- **无参数签名**：对关键参数（如 `mac` + `wlanuserip`）进行 HMAC 签名验证。

### 安全风险与改进建议
#### 1. 风险点
1. **明文传输**：密码（`upass`）和 MAC 地址未加密。
2. **弱校验**：仅依赖 `Referer` 和 `jsVersion` 做简单防护。
3. **设备类型伪造**：无法通过标准参数切换设备类型。

#### 2. 建议
- **加密传输**：建议升级为 HTTPS。
- **动态 Token**：增加 `CSRF-Token` 防止重放攻击。
- **参数签名**：对关键参数（如 `mac` + `wlanuserip`）进行 HMAC 签名验证。

---

## 基于校园网API接口分析构建的校园网自动化登陆脚本
> **基于OpenWrt系统开放软硬路由**

### 1. Windows PowerShell × Bat 脚本
1. 克隆本库 `campus_net_config.ps1.sample` `campus_net_login.ps1` `campus_net_login.bat`
2. 复制 `campus_net_config.ps1.sample` 一份删除末尾拓展名 `.sample` ，命名为 `campus_net_config.ps1`
3. 修改 `campus_net_config.ps1` 中的 `username` 和 `password` 为你的校园网账号和密码
    > 2025年6月2日记录： `username` 中运营商值 `@unicom` 仅中国联通可用，无需修改
4. 三份文件保存在同一目录下，使用时确保已连接校园网并关闭代理，运行 `campus_net_login.bat` 即可自动登录校园网
   | 文件名 | 功能 |
   |--------|------|
   | `campus_net_config.ps1` | 配置校园网账号密码 |
   | `campus_net_login.ps1` | 登录校园网 |
   | `campus_net_login.bat` | 调用 `campus_net_login.ps1` 自动登录校园网 |

### 2. OpenWrt 路由器
1. 克隆本库 `auto_login.sample` `auto_login.sh`
2. 复制 `auto_login.sample` 一份删除末尾拓展名 `.sample` ，命名为 `auto_login`
3. 修改 `auto_login` 中的 `username` 和 `password` 为你的校园网账号和密码 
    > 2025年6月2日记录： `username` 中运营商值 `@unicom` 仅中国联通可用，无需修改
4. 在OpenWrt路由器中安装 `curl` 软件包，示例命令 `opkg install curl`
5. 将 `auto_login.sh` 上传至路由器 `/etc/init.d/` 目录下
6. 将 `auto_login` 上传至路由器 `/etc/config/` 目录下
7. 执行命令
   ```sh
   chmod +x /etc/init.d/auto_login.sh
   /etc/init.d/auto_login.sh enable
   ```
8. 重启路由器，访问OpenWrt路由器Web管理页，`系统 > 启动项 > 启动脚本` ,你将能看到 `启动脚本：auto_login.bash` 
    | 文件名 | 功能 |
    |--------|------|
    | `auto_login` | 配置校园网账号密码 |
    | `auto_login.sh` | 自动登录校园网 |

#### 开发者选项
对于OpenWrt系统，可使用命令 `logread | grep auto_login.bash` 查看脚本执行日志