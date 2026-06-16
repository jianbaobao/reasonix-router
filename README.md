# 🛜 Reasonix Router — 开源软路由系统

基于 **Linux Kernel + BusyBox** 的极简软路由系统，可在虚拟机中启动运行。

## 系统架构

```
                    ┌──────────────────────────────┐
                    │      Reasonix Router          │
[Internet] ◄─WAN──► │  ┌───┐  ┌──────┐  ┌──────┐  │ ◄──LAN──► [客户端]
  (DHCP)   eth0     │  │NAT│─►│DHCP  │  │Web   │  │  eth1   192.168.2.x
                    │  │FW │  │DNS   │  │UI    │  │           (DHCP)
                    │  └───┘  └──────┘  └──────┘  │
                    │        192.168.2.1/24        │
                    └──────────────────────────────┘
```

## 功能特性

- ✅ **NAT 路由** — 通过 iptables/nftables 的 MASQUERADE 实现 IP 伪装
- ✅ **DHCP 服务器** — 自动为 LAN 设备分配 IP (192.168.2.100-200)
- ✅ **DNS 缓存** — dnsmasq 提供本地 DNS 缓存加速
- ✅ **Web 管理界面** — 浏览器访问 http://192.168.2.1 管理路由器
- ✅ **防火墙** — WAN 侧仅开放 SSH(22) 和 HTTP(80)
- ✅ **自动检测** — 自动识别 WAN/LAN 接口
- ✅ **极简启动** — 从 GRUB 引导到控制台仅需几秒

## 快速开始

### 环境要求

构建需要 **Linux 环境**（或 WSL）：

```bash
# Ubuntu/Debian
sudo apt install grub-pc-bin grub-common xorriso mtools python3 qemu-system-x86

# Arch Linux
sudo pacman -S grub libisoburn mtools qemu python
```

### 构建

```bash
# 完整构建
python3 build.py

# 快速构建（使用缓存）
python3 build.py --quick

# 构建 + 直接启动 QEMU 测试
python3 build.py --qemu
```

或者使用 Make：

```bash
make          # 构建 ISO
make qemu     # 构建 + 测试
make dev      # 开发模式
make clean    # 清理
```

### 测试

**QEMU:**
```bash
qemu-system-x86_64 -m 512 -smp 2 \
    -cdrom dist/reasonix-router-1.0.iso \
    -netdev user,id=wan -device e1000,netdev=wan \
    -netdev user,id=lan -device e1000,netdev=lan

# 带端口转发（宿主机可访问 Web UI）
qemu-system-x86_64 -m 512 \
    -cdrom dist/reasonix-router-1.0.iso \
    -nic user,id=wan,hostfwd=tcp::8080-:80 \
    -nic user,id=lan
```

**VirtualBox:**
```
1. 新建 VM → Linux 2.6/3.x/4.x, 512MB RAM
2. 网卡1: NAT（默认）
3. 网卡2: Host-Only → 网段 192.168.2.0/24
4. 挂载 ISO 启动
5. 浏览器打开 http://192.168.2.1
```

## 网络配置

| 接口 | 角色 | IP 配置 |
|------|------|---------|
| eth0 | WAN | DHCP 自动获取 |
| eth1 | LAN | 192.168.2.1/24 |

- **DHCP 池**: 192.168.2.100 - 192.168.2.200
- **DNS 服务器**: 114.114.114.114, 8.8.8.8, 223.5.5.5
- **Web 管理**: http://192.168.2.1

## 项目结构

```
soft-router/
├── build.py              # ISO 构建脚本 (Python)
├── Makefile              # 构建快捷命令
├── README.md             # 本文件
├── iso/                  # ISO 构建源文件
│   ├── grub/
│   │   └── grub.cfg      # GRUB 启动菜单
│   └── initramfs/        # 初始根文件系统
│       ├── init           # PID 1 初始化脚本
│       ├── etc/
│       │   ├── init.d/    # SysV 风格启动脚本
│       │   ├── network/   # 网络配置
│       │   └── profile    # Shell 环境
│       └── www/          # Web 管理界面
│           ├── index.html
│           ├── style.css
│           ├── app.js
│           └── cgi-bin/api  # API 后端
├── scripts/              # 测试辅助脚本
│   ├── qemu-test.sh
│   └── vmware-test.sh
└── kernel/               # 内核配置
    └── config
```

## 技术栈

- **Bootloader**: GRUB 2
- **Kernel**: Linux (Alpine / distro kernel)
- **Init**: BusyBox init + shell scripts
- **Shell**: BusyBox ash
- **Networking**: iproute2, udhcpc, dnsmasq
- **Firewall**: iptables / nftables
- **Web UI**: HTML5 + CSS3 + vanilla JS + CGI

## 许可

MIT License
