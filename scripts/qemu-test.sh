#!/bin/bash
# ============================================================
#  Reasonix Router - QEMU 测试脚本
#  创建虚拟网络环境进行测试
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ISO_PATH="$PROJECT_DIR/dist/reasonix-router-1.0.iso"

echo "╔══════════════════════════════════════════╗"
echo "║  Reasonix Router - QEMU Test            ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 检查 ISO
if [ ! -f "$ISO_PATH" ]; then
    echo "❌ ISO not found at: $ISO_PATH"
    echo "   Run 'python3 build.py' first."
    exit 1
fi

echo "✅ ISO: $ISO_PATH ($(du -h "$ISO_PATH" | cut -f1))"

# 检查 QEMU
QEMU=""
for cmd in qemu-system-x86_64 qemu-system-x86_64.exe qemu; do
    if command -v "$cmd" &> /dev/null; then
        QEMU="$cmd"
        break
    fi
done

if [ -z "$QEMU" ]; then
    echo "❌ QEMU not found. Install with:"
    echo "   Linux: sudo apt install qemu-system-x86"
    echo "   macOS: brew install qemu"
    echo "   Windows: https://www.qemu.org/download/"
    exit 1
fi

echo "✅ QEMU: $QEMU"
echo ""

# 网络拓扑:
#   [Internet] ←→ [WAN: 10.0.2.0/24] ←→ [路由器] ←→ [LAN: 192.168.2.0/24] ←→ [客户端]
#
# QEMU 网络:
#   -netdev user,id=wan  → 模拟 WAN (NAT 到宿主机)
#   -netdev user,id=lan  → 模拟 LAN (隔离网络)

echo "网络拓扑:"
echo "  [Internet] ── WAN(10.0.2.x) ── [Reasonix Router] ── LAN(192.168.2.1) ── [Clients]"
echo ""
echo "启动模式:"
echo "  1) 图形模式 (GTK 窗口)"
echo "  2) 终端模式 (串口控制台)"
echo "  3) SSH 转发模式 (通过 hostfwd)"
echo ""
read -rp "选择 [1]: " MODE
MODE=${MODE:-1}

case "$MODE" in
    2|3)
        echo ""
        echo "============================================"
        echo "  启动中... 等待系统初始化..."
        echo "  预计 5-10 秒后出现登录提示"
        echo "============================================"
        echo ""

        EXTRA_ARGS="-nographic"

        if [ "$MODE" = "3" ]; then
            # 转发 SSH 和 HTTP 到宿主机
            EXTRA_ARGS="$EXTRA_ARGS -nic user,id=wan,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80"
            echo "  SSH:  ssh -p 2222 root@localhost"
            echo "  Web:  http://localhost:8080"
            echo ""
        fi

        "$QEMU" -m 512 -smp 2 \
            -cdrom "$ISO_PATH" \
            -boot d \
            -netdev user,id=wan,net=10.0.2.0/24,dhcpstart=10.0.2.10 \
            -device e1000,netdev=wan,mac=52:54:00:12:34:01 \
            -netdev user,id=lan,net=192.168.2.0/24,dhcpstart=192.168.2.10 \
            -device e1000,netdev=lan,mac=52:54:00:12:34:02 \
            $EXTRA_ARGS
        ;;
    *)
        "$QEMU" -m 512 -smp 2 \
            -cdrom "$ISO_PATH" \
            -boot d \
            -netdev user,id=wan,net=10.0.2.0/24,dhcpstart=10.0.2.10 \
            -device e1000,netdev=wan,mac=52:54:00:12:34:01 \
            -netdev user,id=lan,net=192.168.2.0/24,dhcpstart=192.168.2.10 \
            -device e1000,netdev=lan,mac=52:54:00:12:34:02 \
            -vga std -display gtk
        ;;
esac
