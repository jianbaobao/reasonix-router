#!/bin/bash
# ============================================================
#  Reasonix Router - VirtualBox 自动化创建脚本
#  需要: VirtualBox + VBoxManage
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ISO_PATH="$PROJECT_DIR/dist/reasonix-router-1.0.iso"
VM_NAME="ReasonixRouter"

echo "╔══════════════════════════════════════════╗"
echo "║  Reasonix Router - VirtualBox Setup     ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 检查 VBoxManage
if ! command -v VBoxManage &>/dev/null; then
    echo "❌ VBoxManage not found. Is VirtualBox installed?"
    echo ""
    echo "手动配置步骤:"
    echo "1. 打开 VirtualBox → 新建"
    echo "2. 名称: Reasonix Router"
    echo "3. 类型: Linux, 版本: Other Linux (64-bit)"
    echo "4. 内存: 512 MB"
    echo "5. 硬盘: 不创建 (启动后是 Live 系统)"
    echo "6. 设置 → 存储 → 挂载 ISO: $ISO_PATH"
    echo "7. 设置 → 网络 → 网卡1: NAT"
    echo "8. 设置 → 网络 → 添加网卡2: Host-Only (vboxnet0)"
    echo "9. 启动"
    exit 1
fi

if [ ! -f "$ISO_PATH" ]; then
    echo "❌ ISO not found. Build it first: python3 build.py"
    exit 1
fi

echo "✅ VBoxManage found"
echo "✅ ISO: $ISO_PATH"

# 检查虚拟机是否已存在
if VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
    echo "⚠️  VM '$VM_NAME' already exists."
    read -rp "Delete and recreate? (y/N): " CONFIRM
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true
    else
        echo "  Using existing VM."
    fi
fi

# 创建 VM
echo ""
echo "Creating VM: $VM_NAME"

VBoxManage createvm --name "$VM_NAME" --ostype "Linux_64" --register 2>/dev/null || {
    echo "  VM already registered, continuing..."
}

# 配置 VM
VBoxManage modifyvm "$VM_NAME" \
    --memory 512 \
    --cpus 2 \
    --acpi on \
    --boot1 dvd \
    --nic1 nat \
    --nictype1 82540EM \
    --cableconnected1 on \
    --nic2 hostonly \
    --nictype2 82540EM \
    --hostonlyadapter2 "vboxnet0" \
    --cableconnected2 on 2>/dev/null || true

# 添加 IDE 控制器并挂载 ISO
VBoxManage storagectl "$VM_NAME" --name "IDE" --add ide 2>/dev/null || true
VBoxManage storageattach "$VM_NAME" \
    --storagectl "IDE" \
    --port 0 \
    --device 0 \
    --type dvddrive \
    --medium "$ISO_PATH" 2>/dev/null || {
    echo "  ⚠️  Could not attach ISO (may need to close VM settings first)"
}

echo ""
echo "✅ VM '$VM_NAME' created and configured!"
echo ""
echo "启动 VM:"
echo "  VBoxManage startvm \"$VM_NAME\""
echo ""
echo "或通过 VirtualBox GUI 启动"
echo ""
echo "启动后访问:"
echo "  http://192.168.2.1  (通过 Host-Only 网卡)"
echo ""
