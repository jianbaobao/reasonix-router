#!/bin/bash
# ============================================================
#  Reasonix Router - 快速 ISO 构建脚本 (Shell 版)
#  需要: grub-mkrescue, xorriso, busybox, 内核
# ============================================================

set -e
cd "$(dirname "$0")/.."
PROJECT_DIR="$PWD"

echo "╔══════════════════════════════════════════╗"
echo "║  Reasonix Router - Quick Build          ║"
echo "╚══════════════════════════════════════════╝"

# 检查依赖
for cmd in grub-mkrescue xorriso; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ Missing: $cmd"
        echo "   sudo apt install grub-pc-bin grub-common xorriso mtools"
        exit 1
    fi
done

BUILD_DIR="$PROJECT_DIR/build"
INITRAMFS_DIR="$PROJECT_DIR/iso/initramfs"
GRUB_DIR="$PROJECT_DIR/iso/grub"
ISO_ROOT="$BUILD_DIR/iso_root"
DIST_DIR="$PROJECT_DIR/dist"

# 清理
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/kernel" "$BUILD_DIR/initramfs" "$ISO_ROOT/boot/grub"

# 1. 获取内核
echo ""
echo "Step 1/4: Getting kernel..."
KERNEL_SRC=""

# 尝试从本地系统获取
for k in /boot/vmlinuz /boot/vmlinuz-lts /boot/vmlinuz-*; do
    if [ -f "$k" ]; then
        KERNEL_SRC="$k"
        break
    fi
done

if [ -n "$KERNEL_SRC" ]; then
    cp "$KERNEL_SRC" "$BUILD_DIR/kernel/vmlinuz"
    echo "  ✅ Kernel: $KERNEL_SRC ($(du -h "$KERNEL_SRC" | cut -f1))"
else
    echo "  ⚠️  No local kernel found. Trying Alpine..."
    # 下载 Alpine 内核
    ALPINE_ISO="$BUILD_DIR/alpine.iso"
    if [ ! -f "$ALPINE_ISO" ]; then
        echo "  Downloading Alpine ISO..."
        wget -q -O "$ALPINE_ISO" \
            "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.3-x86_64.iso" || {
            echo "  Download failed, try: python3 build.py"
            exit 1
        }
    fi

    # 尝试提取内核
    xorriso -osirrox on -indev "$ALPINE_ISO" \
        -extract /boot/vmlinuz-virt "$BUILD_DIR/kernel/vmlinuz" 2>/dev/null || \
    xorriso -osirrox on -indev "$ALPINE_ISO" \
        -extract /boot/vmlinuz-lts "$BUILD_DIR/kernel/vmlinuz" 2>/dev/null || {
        echo "  Failed to extract kernel from Alpine ISO"
        exit 1
    }
    echo "  ✅ Kernel extracted from Alpine"
fi

# 2. 获取 BusyBox
echo ""
echo "Step 2/4: Getting BusyBox..."
if command -v busybox &>/dev/null; then
    cp "$(which busybox)" "$BUILD_DIR/busybox"
    echo "  ✅ BusyBox from system: $(busybox --help 2>&1 | head -1)"
else
    echo "  Downloading BusyBox..."
    wget -q -O "$BUILD_DIR/busybox" \
        "https://busybox.net/downloads/binaries/1.36.1/busybox-x86_64" || {
        echo "  Download failed"
        exit 1
    }
    chmod +x "$BUILD_DIR/busybox"
    echo "  ✅ BusyBox downloaded"
fi

# 3. 构建 initramfs
echo ""
echo "Step 3/4: Building initramfs..."
INITRAMFS_BUILD="$BUILD_DIR/initramfs/root"

# 创建目录结构
for dir in bin sbin etc/init.d etc/network dev proc sys tmp root \
           www www/cgi-bin var/log var/run var/lib mnt lib; do
    mkdir -p "$INITRAMFS_BUILD/$dir"
done

# 复制 BusyBox 并创建 applet 链接
cp "$BUILD_DIR/busybox" "$INITRAMFS_BUILD/bin/busybox"
chmod 755 "$INITRAMFS_BUILD/bin/busybox"

# 常见 applet 链接
for applet in sh ls cp mv rm cat echo printf clear mount umount \
              ps kill pwd find grep sed awk cut sort uniq head tail \
              wc tee test sleep pidof killall env export set date \
              free dmesg modprobe lsmod insmod rmmod \
              ifconfig ip route udhcpc arping ping nc telnet \
              vi editor more less mkdir rmdir ln chmod chown \
              tar gzip gunzip dd df du sync reboot halt poweroff \
              login adduser deluser passwd hostname dnsdomainname \
              httpd tftp udhcpd hostname login mdev switch_root; do
    ln -sf /bin/busybox "$INITRAMFS_BUILD/bin/$applet" 2>/dev/null || true
done

for applet in halt reboot shutdown fdisk mkfs swapon swapoff \
              ifconfig route ip udhcpc udhcpd modprobe insmod \
              rmmod lsmod mount umount losetup; do
    ln -sf /bin/busybox "$INITRAMFS_BUILD/sbin/$applet" 2>/dev/null || true
done

# 复制自定义 initramfs 文件
echo "  Copying custom initramfs files..."
cp -r "$INITRAMFS_DIR/"* "$INITRAMFS_BUILD/" 2>/dev/null || true

# 确保 init 可执行
chmod 755 "$INITRAMFS_BUILD/init"
[ -f "$INITRAMFS_BUILD/www/cgi-bin/api" ] && chmod 755 "$INITRAMFS_BUILD/www/cgi-bin/api"

# 压缩
cd "$INITRAMFS_BUILD"
find . -print0 | cpio --null --format=newc -o 2>/dev/null | gzip -1 > "$BUILD_DIR/initramfs.gz"
cd "$PROJECT_DIR"

INITRAMFS_SIZE=$(du -h "$BUILD_DIR/initramfs.gz" | cut -f1)
echo "  ✅ initramfs.gz: $INITRAMFS_SIZE ($(find "$INITRAMFS_BUILD" -type f | wc -l) files)"

# 4. 构建 ISO
echo ""
echo "Step 4/4: Building bootable ISO..."
cp "$BUILD_DIR/kernel/vmlinuz" "$ISO_ROOT/boot/"
cp "$BUILD_DIR/initramfs.gz" "$ISO_ROOT/boot/"
cp "$GRUB_DIR/grub.cfg" "$ISO_ROOT/boot/grub/"

# 创建 README
cat > "$ISO_ROOT/README.TXT" << 'EOF'
Reasonix Router v1.0 - Bootable ISO
====================================
WAN: DHCP (eth0)
LAN: 192.168.2.1/24 (eth1)
Web: http://192.168.2.1
EOF

# 构建
mkdir -p "$DIST_DIR"
ISO_PATH="$DIST_DIR/reasonix-router-1.0.iso"
grub-mkrescue -o "$ISO_PATH" "$ISO_ROOT" 2>/dev/null

ISO_SIZE=$(du -h "$ISO_PATH" | cut -f1)
echo ""
echo "========================================"
echo "  ✅ Build Complete!"
echo "  ISO: $ISO_PATH ($ISO_SIZE)"
echo "========================================"
echo ""
echo "  Run with QEMU:"
echo "    qemu-system-x86_64 -m 512 \\"
echo "      -cdrom $ISO_PATH \\"
echo "      -netdev user,id=wan -device e1000,netdev=wan \\"
echo "      -netdev user,id=lan -device e1000,netdev=lan"
echo ""
