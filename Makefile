# Reasonix Router Makefile
# =========================

VERSION ?= 1.0

.PHONY: all build clean qemu vbox help

all: build

build:
	python3 build.py

quick:
	python3 build.py --quick

qemu: build
	python3 build.py --qemu

clean:
	python3 build.py --clean
	rm -rf build/ dist/

distclean: clean
	rm -rf build/ dist/

# 快速构建并测试 (使用本地内核/busybox)
dev: quick
	@echo "ISO ready in dist/"

# QEMU 测试 (需要先有 ISO)
test-qemu:
	@echo "Starting QEMU with Reasonix Router..."
	qemu-system-x86_64 -m 512 -smp 2 \
		-cdrom dist/reasonix-router-$(VERSION).iso \
		-boot d \
		-netdev user,id=wan,net=10.0.2.0/24,dhcpstart=10.0.2.10 \
		-device e1000,netdev=wan,mac=52:54:00:12:34:01 \
		-netdev user,id=lan,net=192.168.2.0/24,dhcpstart=192.168.2.10 \
		-device e1000,netdev=lan,mac=52:54:00:12:34:02 \
		-vga std -display gtk

# QEMU 无图形模式 (通过串口交互)
test-qemu-nographic:
	qemu-system-x86_64 -m 512 -smp 2 \
		-cdrom dist/reasonix-router-$(VERSION).iso \
		-boot d \
		-netdev user,id=wan,net=10.0.2.0/24,dhcpstart=10.0.2.10 \
		-device e1000,netdev=wan,mac=52:54:00:12:34:01 \
		-netdev user,id=lan,net=192.168.2.0/24,dhcpstart=192.168.2.10 \
		-device e1000,netdev=lan,mac=52:54:00:12:34:02 \
		-nographic

# 查看 initramfs 内容
list-initramfs:
	@echo "Files in initramfs:"
	@find iso/initramfs -type f | sort

# 创建 VirtualBox VM 脚本
vbox:
	@echo "Creating VirtualBox VM script..."
	@cat > /tmp/create-reasonix-vm.sh << 'EOF'
#!/bin/bash
VM_NAME="ReasonixRouter"
VBoxManage createvm --name "$$VM_NAME" --ostype "Linux_64" --register
VBoxManage modifyvm "$$VM_NAME" --memory 512 --cpus 2
VBoxManage modifyvm "$$VM_NAME" --nic1 nat --nictype1 82540EM
VBoxManage modifyvm "$$VM_NAME" --nic2 hostonly --nictype2 82540EM --hostonlyadapter2 "vboxnet0"
VBoxManage storagectl "$$VM_NAME" --name "IDE" --add ide
VBoxManage storageattach "$$VM_NAME" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium dist/reasonix-router-$(VERSION).iso
echo "VM '$$VM_NAME' created. Start with:"
echo "  VBoxManage startvm \"$$VM_NAME\""
EOF
	@echo "Script written to /tmp/create-reasonix-vm.sh"
	@echo "Run: bash /tmp/create-reasonix-vm.sh"

help:
	@echo "Reasonix Router Build System"
	@echo "============================"
	@echo "  make          - 完整构建 ISO"
	@echo "  make quick    - 快速构建 (使用缓存)"
	@echo "  make qemu     - 构建 + QEMU 测试"
	@echo "  make clean    - 清理"
	@echo "  make dev      - 开发模式 (快速构建)"
	@echo "  make test-qemu - 启动 QEMU 测试"
	@echo "  make test-qemu-nographic - QEMU 串口模式"
	@echo "  make vbox     - 生成 VirtualBox 脚本"
