#!/bin/bash
# ============================================================
#  Reasonix Router - VMware 测试指引
# ============================================================

echo "╔══════════════════════════════════════════╗"
echo "║  Reasonix Router - VMware Setup          ║"
echo "╚══════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

ISO_PATH="$PROJECT_DIR/dist/reasonix-router-1.0.iso"

if [ ! -f "$ISO_PATH" ]; then
    echo "❌ ISO 文件不存在，请先运行: python3 build.py"
    exit 1
fi

echo "✅ ISO: $ISO_PATH"
echo ""
echo "============================================"
echo "  VMware Workstation/Player 配置步骤"
echo "============================================"
echo ""
echo "1. 创建新虚拟机:"
echo "   File → New Virtual Machine"
echo "   - Typical (推荐)"
echo "   - Installer disc image file (iso): 选择:"
echo "     $ISO_PATH"
echo "   - Guest Operating System: Linux"
echo "   - Version: Other Linux 4.x/5.x kernel 64-bit"
echo "   - VM Name: Reasonix Router"
echo "   - Disk: 不创建虚拟硬盘 (Live CD 模式)"
echo ""
echo "2. 配置网卡:"
echo "   VM Settings → Network Adapter"
echo "   - Network Adapter 1: NAT (用于 WAN)"
echo "   - Network Adapter 2: Host-only (用于 LAN)"
echo "     (需要先添加新网卡: Add → Network Adapter)"
echo ""
echo "3. 启动:"
echo "   点击 Power On 启动虚拟器"
echo ""
echo "4. 验证:"
echo "   启动后路由器会自动配置网络"
echo "   - WAN (ens33): DHCP 获取 IP"
echo "   - LAN (ens38): 192.168.2.1"
echo "   - Web 管理: http://192.168.2.1"
echo ""
echo "5. 客户端测试:"
echo "   在宿主机上添加一个 Host-Only 网卡:"
echo "   Edit → Virtual Network Editor"
echo "   将 VMnet1 (Host-only) 设为: 192.168.2.0/24"
echo "   然后宿主机就能通过 192.168.2.1 访问路由器"
echo ""
