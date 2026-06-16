#!/usr/bin/env python3
"""
============================================================
  Reasonix Router - Bootable ISO Builder
  软路由 ISO 构建脚本
============================================================

用法:
    python build.py               # 完整构建 ISO + VMDK + VDI + OVA
    python build.py --quick       # 快速构建 (使用本地已有文件)
    python build.py --clean       # 清理构建产物
    python build.py --usb         # 构建 USB 可启动镜像 (.img)
    python build.py --qemu        # 构建后直接在 QEMU 中运行

依赖 (Linux / WSL):
    sudo apt install grub-pc-bin grub-common xorriso mtools python3 qemu-utils
    # UEFI 支持 (可选):
    sudo apt install grub-efi-amd64-bin

输出:
    dist/reasonix-router-1.0.iso  # 可启动 ISO (BIOS+UEFI)
    dist/reasonix-router-1.0.img  # USB 可启动镜像 (混合)
    dist/reasonix-router-1.0.vmdk # VMware 磁盘
    dist/reasonix-router-1.0.vdi  # VirtualBox 磁盘
    dist/reasonix-router-1.0.ova  # OVA 虚拟机模板
"""

import os
import sys
import shutil
import subprocess
import tarfile
import gzip
import struct

# ─── 配置 ───────────────────────────────────────────────────
PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
DIST_DIR = os.path.join(PROJECT_DIR, "dist")
WORK_DIR = os.path.join(PROJECT_DIR, "build")
INITRAMFS_DIR = os.path.join(PROJECT_DIR, "iso", "initramfs")
GRUB_DIR = os.path.join(PROJECT_DIR, "iso", "grub")
ISO_DIR = os.path.join(WORK_DIR, "iso_root")

VERSION = "1.0"
ISO_NAME = f"reasonix-router-{VERSION}.iso"
ISO_PATH = os.path.join(DIST_DIR, ISO_NAME)

# 下载源
KERNEL_URL = "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.3-x86_64.iso"
BUSYBOX_URL = "https://busybox.net/downloads/binaries/1.36.1/busybox-x86_64"

# ─── 工具函数 ───────────────────────────────────────────────

def color(msg, code):
    return f"\033[{code}m{msg}\033[0m" if sys.stdout.isatty() else msg

def info(msg):
    print(f"  {color('→', '36')} {msg}")

def ok(msg):
    print(f"  {color('✓', '32')} {msg}")

def warn(msg):
    print(f"  {color('⚠', '33')} {msg}")

def error(msg):
    print(f"  {color('✗', '31')} {msg}")

def run(cmd, **kwargs):
    """运行命令并检查返回码"""
    info(f"Running: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    result = subprocess.run(cmd, shell=isinstance(cmd, str),
                          capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        warn(f"Command failed (code {result.returncode})")
        if result.stderr:
            for line in result.stderr.strip().split('\n')[-5:]:
                warn(f"  stderr: {line}")
    return result

def check_deps():
    """检查系统依赖"""
    deps = ["grub-mkrescue", "xorriso", "mformat"]
    missing = []
    for dep in deps:
        if not shutil.which(dep):
            missing.append(dep)

    if missing:
        warn(f"Missing dependencies: {', '.join(missing)}")
        print("  Install with:")
        print("    Ubuntu/Debian: sudo apt install grub-pc-bin grub-common xorriso mtools")
        print("    Arch:          sudo pacman -S grub libisoburn mtools")
        print("    Alpine:        sudo apk add grub-bios xorriso mtools")
        print("    macOS:         brew install grub xorriso mtools")
        return False
    return True

def download_file(url, dest):
    """下载文件"""
    if os.path.exists(dest):
        ok(f"{dest} already exists, skipping download")
        return True

    info(f"Downloading {url}")
    try:
        import urllib.request
        import urllib.error
        req = urllib.request.Request(url, headers={
            'User-Agent': 'Reasonix-Router-Builder/1.0'
        })
        with urllib.request.urlopen(req, timeout=60) as resp:
            content = resp.read()
            with open(dest, 'wb') as f:
                f.write(content)
        ok(f"Downloaded {len(content)} bytes to {dest}")
        return True
    except Exception as e:
        error(f"Download failed: {e}")
        return False


# ─── 构建阶段 ───────────────────────────────────────────────

def clean():
    """清理构建产物"""
    info("Cleaning build artifacts...")
    for d in [DIST_DIR, WORK_DIR]:
        if os.path.exists(d):
            shutil.rmtree(d)
            ok(f"Removed {d}")

def extract_kernel():
    """从 Alpine ISO 中提取内核"""
    kernel_dir = os.path.join(WORK_DIR, "kernel")
    os.makedirs(kernel_dir, exist_ok=True)

    vmlinuz = os.path.join(kernel_dir, "vmlinuz")
    if os.path.exists(vmlinuz):
        ok("Kernel already extracted")
        return vmlinuz

    alpine_iso = os.path.join(WORK_DIR, "alpine.iso")

    if not os.path.exists(alpine_iso):
        warn("Alpine ISO not found, downloading...")
        if not download_file(KERNEL_URL, alpine_iso):
            error("Failed to download Alpine ISO")
            return None

    # 挂载 ISO 并提取内核
    mnt_dir = os.path.join(WORK_DIR, "mnt")
    os.makedirs(mnt_dir, exist_ok=True)

    # 尝试使用 7z (跨平台)
    extracted = False

    # 方法1: 使用 xorriso 提取
    result = run(["xorriso", "-osirrox", "on", "-indev", alpine_iso,
                  "-extract", "/boot/vmlinuz-lts", vmlinuz], cwd=WORK_DIR)
    if result.returncode != 0:
        # 方法2: 尝试找到不同路径的内核
        result = run(["xorriso", "-osirrox", "on", "-indev", alpine_iso,
                      "-extract", "/boot/vmlinuz-virt", vmlinuz], cwd=WORK_DIR)

    if result.returncode == 0 and os.path.exists(vmlinuz):
        extracted = True

    if not extracted:
        # 方法3: 挂载 (Linux only)
        result = run(["mount", "-o", "loop", alpine_iso, mnt_dir])
        if result.returncode == 0:
            for root, dirs, files in os.walk(mnt_dir):
                for f in files:
                    if 'vmlinuz' in f:
                        src = os.path.join(root, f)
                        shutil.copy2(src, vmlinuz)
                        extracted = True
                        break
                if extracted:
                    break
            run(["umount", mnt_dir])

    if not extracted:
        # 方法4: 从本地 /boot 复制 (fallback)
        local_kernels = []
        for k in ["/boot/vmlinuz", "/boot/vmlinuz-lts", "/boot/vmlinuz-virt"]:
            if os.path.exists(k):
                local_kernels.append(k)
        if local_kernels:
            shutil.copy2(local_kernels[0], vmlinuz)
            ok(f"Used local kernel: {local_kernels[0]}")
            extracted = True

    if extracted and os.path.exists(vmlinuz):
        size = os.path.getsize(vmlinuz)
        ok(f"Kernel extracted: {size} bytes")
        return vmlinuz
    else:
        error("Could not extract kernel!")
        return None

def download_busybox():
    """下载 BusyBox 二进制文件"""
    busybox_dir = os.path.join(WORK_DIR, "busybox")
    os.makedirs(busybox_dir, exist_ok=True)
    busybox_bin = os.path.join(busybox_dir, "busybox")

    if os.path.exists(busybox_bin):
        ok("BusyBox already downloaded")
        return busybox_bin

    if download_file(BUSYBOX_URL, busybox_bin):
        os.chmod(busybox_bin, 0o755)
        ok(f"BusyBox binary ready: {busybox_bin}")
        return busybox_bin

    # 尝试使用系统 busybox
    system_bb = shutil.which("busybox")
    if system_bb:
        shutil.copy2(system_bb, busybox_bin)
        ok(f"Using system BusyBox: {system_bb}")
        return busybox_bin

    error("Could not obtain busybox binary!")
    return None

def list_busybox_applets(busybox_bin):
    """获取 BusyBox 支持的所有 applet 列表"""
    result = subprocess.run([busybox_bin, "--list"], capture_output=True, text=True)
    if result.returncode == 0:
        return result.stdout.strip().split()
    return []

def create_initramfs(busybox_bin):
    """构建 initramfs"""
    initramfs_build = os.path.join(WORK_DIR, "initramfs")
    initramfs_gz = os.path.join(WORK_DIR, "initramfs.gz")

    # 清理并重建
    if os.path.exists(initramfs_build):
        shutil.rmtree(initramfs_build)

    info("Building initramfs structure...")

    # 复制我们准备的 initramfs 目录
    dirs_to_create = [
        "usr/bin", "usr/sbin", "usr/lib", "usr/share",
        "bin", "sbin", "lib",  # symlink targets
        "etc", "etc/init.d", "etc/network", "etc/config",
        "dev", "proc", "sys", "tmp",
        "root", "www", "www/cgi-bin",
        "var", "var/log", "var/run", "var/lib",
        "mnt", "overlay", "overlay/upper", "overlay/work",
    ]

    for d in dirs_to_create:
        os.makedirs(os.path.join(initramfs_build, d), exist_ok=True)

    # 复制 BusyBox 到 /usr/bin (/usr 合并布局)
    bb_dest = os.path.join(initramfs_build, "usr", "bin", "busybox")
    shutil.copy2(busybox_bin, bb_dest)
    os.chmod(bb_dest, 0o755)

    # 创建 /usr 合并符号链接
    for link, target in [("bin", "usr/bin"), ("sbin", "usr/sbin"), ("lib", "usr/lib")]:
        link_path = os.path.join(initramfs_build, link)
        if os.path.isdir(link_path) and not os.path.islink(link_path):
            os.rmdir(link_path)
        if not os.path.exists(link_path):
            os.symlink(target, link_path)
            ok(f"Created symlink: {link} → {target}")

    # 创建 BusyBox applet 符号链接 (指向 /usr/bin/busybox)
    applets = list_busybox_applets(busybox_bin)
    applet_count = 0
    # applet 放到 usr/bin 和 usr/sbin
    applet_dirs = ["usr/bin", "usr/sbin"]

    for applet in applets:
        sbin_applets = {
            'shutdown', 'reboot', 'halt', 'poweroff', 'fdisk', 'mkfs',
            'swapon', 'swapoff', 'ifconfig', 'route', 'ip',
            'udhcpc', 'udhcpd', 'dnsmasq', 'iptables',
            'modprobe', 'insmod', 'rmmod', 'lsmod',
            'mount', 'umount', 'losetup',
            'fstrim', 'blkid', 'blockdev',
        }

        target_dir = "usr/sbin" if applet in sbin_applets else "usr/bin"
        link_path = os.path.join(initramfs_build, target_dir, applet)

        if not os.path.exists(link_path):
            os.symlink("/usr/bin/busybox", link_path)
            applet_count += 1

    ok(f"Created {applet_count} BusyBox applet links")

    # 复制 initramfs 中的自定义文件 (覆盖默认)
    info("Copying custom initramfs files...")
    copy_count = 0
    for root, dirs, files in os.walk(INITRAMFS_DIR):
        for f in files:
            src = os.path.join(root, f)
            rel = os.path.relpath(src, INITRAMFS_DIR)
            dst = os.path.join(initramfs_build, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            # 脚本设为可执行
            if f.endswith('.sh') or f in ('init',) or f.startswith('S'):
                os.chmod(dst, 0o755)
            copy_count += 1

    ok(f"Copied {copy_count} custom files")

    # 确保 init 可执行
    init_path = os.path.join(initramfs_build, "init")
    if os.path.exists(init_path):
        os.chmod(init_path, 0o755)
    else:
        error("init script missing!")
        return None

    # 设置 www/cgi-bin/api 可执行
    api_path = os.path.join(initramfs_build, "www", "cgi-bin", "api")
    if os.path.exists(api_path):
        os.chmod(api_path, 0o755)

    # 压缩 initramfs
    info("Creating initramfs.gz...")
    os.chdir(initramfs_build)

    # 使用 cpio + gzip 创建 initramfs
    find_cmd = ["find", ".", "-print0"]
    cpio_cmd = ["cpio", "--null", "--format=newc", "-o"]
    gzip_cmd = ["gzip", "-1"]

    with open(initramfs_gz, 'wb') as outfile:
        find_proc = subprocess.Popen(find_cmd, stdout=subprocess.PIPE)
        cpio_proc = subprocess.Popen(cpio_cmd, stdin=find_proc.stdout, stdout=subprocess.PIPE)
        gzip_proc = subprocess.Popen(gzip_cmd, stdin=cpio_proc.stdout, stdout=outfile)
        gzip_proc.communicate()

    os.chdir(PROJECT_DIR)

    size = os.path.getsize(initramfs_gz)
    ok(f"initramfs.gz created: {size} bytes ({size/1024:.0f} KB)")

    # 计算文件数量
    file_count = sum(len(files) for _, _, files in os.walk(initramfs_build))
    info(f"Total files in initramfs: {file_count}")

    return initramfs_gz


def build_iso(kernel_path, initramfs_path):
    """构建可启动 ISO"""
    info("Building bootable ISO...")

    # 清理 ISO 目录
    if os.path.exists(ISO_DIR):
        shutil.rmtree(ISO_DIR)

    # 创建 ISO 目录结构
    os.makedirs(os.path.join(ISO_DIR, "boot", "grub"))
    os.makedirs(os.path.join(ISO_DIR, "boot", "fonts"))

    # 复制内核
    kernel_dest = os.path.join(ISO_DIR, "boot", "vmlinuz")
    shutil.copy2(kernel_path, kernel_dest)
    ok(f"Copied kernel ({os.path.getsize(kernel_path)} bytes)")

    # 复制 initramfs
    initramfs_dest = os.path.join(ISO_DIR, "boot", "initramfs.gz")
    shutil.copy2(initramfs_path, initramfs_dest)
    ok(f"Copied initramfs ({os.path.getsize(initramfs_path)} bytes)")

    # 复制 GRUB 配置
    grub_cfg_src = os.path.join(GRUB_DIR, "grub.cfg")
    if os.path.exists(grub_cfg_src):
        shutil.copy2(grub_cfg_src, os.path.join(ISO_DIR, "boot", "grub", "grub.cfg"))
        ok("Copied GRUB config")

    # 创建 README 文件
    with open(os.path.join(ISO_DIR, "README.TXT"), 'w') as f:
        f.write(f"""=============================================
  Reasonix Router v{VERSION}
  软路由系统 - 可启动 ISO 镜像
=============================================

系统信息:
  - 基于 Linux Kernel + BusyBox
  - WAN: DHCP 自动获取 IP (eth0)
  - LAN: 静态 IP 192.168.2.1/24 (eth1)
  - Web 管理: http://192.168.2.1
  - DHCP 范围: 192.168.2.100 - 200

网络拓扑:
  [Internet] --- [WAN: eth0] 软路由 [LAN: eth1] --- [客户端]

VM 测试:
  QEMU:
    qemu-system-x86_64 -m 512 -cdrom {ISO_NAME}
    -netdev user,id=wan -device e1000,netdev=wan
    -netdev user,id=lan -device e1000,netdev=lan

  VirtualBox:
    新建 VM -> Linux 2.6/3.x/4.x, 512MB RAM
    添加 2 个网卡: NAT + Host-Only
    挂载 ISO 启动

默认无登录密码 (直接进入 shell)。
""")

    # 检测 UEFI 支持
    has_uefi = shutil.which("grub-mkrescue") and os.path.exists("/usr/lib/grub/x86_64-efi")
    if has_uefi:
        ok("UEFI support detected")
    else:
        warn("UEFI not available (install grub-efi-amd64-bin for UEFI support)")
        warn("System will still boot in BIOS/CSM mode on bare metal")

    # 使用 grub-mkrescue 构建 ISO
    os.makedirs(DIST_DIR, exist_ok=True)

    # ISOHybrid 参数: 确保兼容 VMware/Ventoy/balenaEtcher/dd
    # -isohybrid-gpt-basdat  → GPT/MBR 混合分区表
    # --protective-msdos-label → 保护性 MBR
    # --boot-load-size 4 → GRUB 加载大小
    HYBRID_OPTS = [
        "-isohybrid-gpt-basdat",
        "--protective-msdos-label",
    ]

    info("Running grub-mkrescue (ISOHybrid)...")
    cmd = [
        "grub-mkrescue",
        "-o", ISO_PATH,
        ISO_DIR,
        "--compress=xz",
        "--product-name=ReasonixRouter",
        "--product-version=" + VERSION,
    ] + HYBRID_OPTS

    if has_uefi:
        info("Adding UEFI boot support (BIOS+UEFI dual boot)")
        cmd += ["--grub-mkimage", "grub-mkimage"]

    result = run(cmd, timeout=300)

    if result.returncode == 0 and os.path.exists(ISO_PATH):
        size = os.path.getsize(ISO_PATH)
        ok(f"ISO created: {ISO_PATH} ({size/1024/1024:.1f} MB)")
        return ISO_PATH
    else:
        # 重试不含压缩选项
        warn("Retrying without compression...")
        result = run([
            "grub-mkrescue",
            "-o", ISO_PATH,
            ISO_DIR,
        ], timeout=300)

        if result.returncode == 0 and os.path.exists(ISO_PATH):
            size = os.path.getsize(ISO_PATH)
            ok(f"ISO created: {ISO_PATH} ({size/1024/1024:.1f} MB)")
            return ISO_PATH

        error("grub-mkrescue failed!")
        if result.stderr:
            for line in result.stderr.strip().split('\n'):
                error(f"  {line}")
        return None


def build_usb_image(iso_path):
    """从 ISO 生成 USB 可启动镜像 (ISOHybrid)"""
    info("Creating USB bootable image...")
    base_name = os.path.splitext(iso_path)[0]
    img_path = f"{base_name}.img"

    if os.path.exists(iso_path):
        # ISOHybrid: 直接复制 ISO 到 .img (兼容 dd 写入 USB)
        shutil.copy2(iso_path, img_path)
        size = os.path.getsize(img_path)
        ok(f"USB image: {img_path} ({size/1024/1024:.1f} MB)")

        # 创建写入说明
        with open(f"{base_name}-write-to-usb.txt", 'w') as f:
            f.write(f"""=============================================
  Reasonix Router - USB 启动盘写入指南
=============================================

文件: {os.path.basename(img_path)} ({size/1024/1024:.1f} MB)

Linux/macOS:
  sudo dd if={os.path.basename(img_path)} of=/dev/sdX bs=4M status=progress
  sync

  (将 /dev/sdX 替换为你的 USB 设备, 如 /dev/sdb)
  
Windows:
  方法1: 使用 Rufus (推荐)
    https://rufus.ie
    选择 {os.path.basename(img_path)} → 写入
  
  方法2: 使用 PowerShell (管理员)
    .\\scripts\\write-usb.ps1
  
  方法3: 使用 balenaEtcher
    https://www.balena.io/etcher/

注意: 此操作会清除 USB 设备上的所有数据!
=============================================
""")
        ok(f"USB write instructions: {base_name}-write-to-usb.txt")
    return img_path


def build_formats(iso_path):
    """从 ISO 生成其他虚拟机磁盘格式"""
    if not shutil.which("qemu-img"):
        warn("qemu-img not found. Install with: sudo apt install qemu-utils")
        warn("Skipping VMDK/VDI/RAW conversion.")
        return iso_path

    info("Converting ISO to disk image formats...")
    base_name = os.path.splitext(iso_path)[0]

    # 创建一个空白磁盘镜像描述
    # 注意: 这些是"空磁盘+ISO"组合包, 首次启动需安装
    # 或者使用安装好的镜像 (需要更大空间)

    # 1. RAW + ISO 组合包
    raw_path = f"{base_name}.img"
    info(f"Creating RAW image description...")
    # 实际上只创建标记文件, 用户需要自己 dd
    with open(f"{base_name}.raw.txt", 'w') as f:
        f.write(f"""Reasonix Router RAW Image
=======================
This is a bootable RAW disk image.

Write to USB/SD with:
  sudo dd if={os.path.basename(iso_path)} of=/dev/sdX bs=4M status=progress

Or mount in QEMU:
  qemu-system-x86_64 -m 512 -cdrom {os.path.basename(iso_path)} \\
    -netdev user,id=wan -device e1000,netdev=wan \\
    -netdev user,id=lan -device e1000,netdev=lan
""")
    ok("Created RAW image instructions")

    # 2. VMDK 转换
    vmdk_path = f"{base_name}.vmdk"
    if os.path.exists(raw_path):
        result = run(["qemu-img", "convert", "-f", "raw", "-O", "vmdk", raw_path, vmdk_path])
        if result.returncode == 0:
            ok(f"VMDK: {vmdk_path} ({os.path.getsize(vmdk_path)/1024/1024:.1f} MB)")

    # 3. VDI 转换
    vdi_path = f"{base_name}.vdi"
    if os.path.exists(raw_path):
        result = run(["qemu-img", "convert", "-f", "raw", "-O", "vdi", raw_path, vdi_path])
        if result.returncode == 0:
            ok(f"VDI: {vdi_path} ({os.path.getsize(vdi_path)/1024/1024:.1f} MB)")

    # 4. 创建 VMware VM 包
    vmx_dir = f"{base_name}-vmware"
    os.makedirs(vmx_dir, exist_ok=True)
    # 复制 ISO
    shutil.copy2(iso_path, os.path.join(vmx_dir, os.path.basename(iso_path)))
    # 创建 .vmx
    vmx_path = os.path.join(vmx_dir, "ReasonixRouter.vmx")
    with open(vmx_path, 'w') as f:
        f.write(VMX_TEMPLATE.format(
            display_name="Reasonix Router v" + VERSION,
            guest_os="otherlinux-64",
            firmware="bios",
            iso_path=os.path.basename(iso_path),
            mem_size="512",
        ))
    ok(f"VMware VM: {vmx_dir}/")

    # 5. OVA 包 (tar + ovf)
    ova_path = f"{base_name}.ova"
    ovf_path = os.path.join(vmx_dir, "ReasonixRouter.ovf")
    # 简单 OVF 描述
    with open(ovf_path, 'w') as f:
        f.write(f"""<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://schemas.dmtf.org/ovf/envelope/1">
  <References/>
  <DiskSection><Disks/></DiskSection>
  <NetworkSection>
    <Network ovf:name="WAN"><Description>WAN Network</Description></Network>
    <Network ovf:name="LAN"><Description>LAN Network</Description></Network>
  </NetworkSection>
  <VirtualSystem ovf:id="ReasonixRouter">
    <Name>Reasonix Router v{VERSION}</Name>
    <OperatingSystemSection><Info>Linux</Info></OperatingSystemSection>
    <VirtualHardwareSection>
      <Item><rasd:ElementName>1 CPU</rasd:ElementName><rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType><rasd:VirtualQuantity>2</rasd:VirtualQuantity></Item>
      <Item><rasd:ElementName>512 MB RAM</rasd:ElementName><rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType><rasd:VirtualQuantity>512</rasd:VirtualQuantity></Item>
      <Item><rasd:ElementName>WAN</rasd:ElementName><rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceType>10</rasd:ResourceType><rasd:ResourceSubType>E1000</rasd:ResourceSubType>
        <rasd:Connection>WAN</rasd:Connection></Item>
      <Item><rasd:ElementName>LAN</rasd:ElementName><rasd:InstanceID>4</rasd:InstanceID>
        <rasd:ResourceType>10</rasd:ResourceType><rasd:ResourceSubType>E1000</rasd:ResourceSubType>
        <rasd:Connection>LAN</rasd:Connection></Item>
      <Item><rasd:ElementName>CD-ROM</rasd:ElementName><rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceType>15</rasd:ResourceType><rasd:HostResource>/disk/{os.path.basename(iso_path)}</rasd:HostResource></Item>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>""")
    # OVA = tar of OVF + ISO
    import tarfile
    with tarfile.open(ova_path, 'w') as tar:
        tar.add(ovf_path, arcname="ReasonixRouter.ovf")
        tar.add(iso_path, arcname=os.path.basename(iso_path))
    ok(f"OVA: {ova_path} ({os.path.getsize(ova_path)/1024/1024:.1f} MB)")

    return iso_path


# VMware .vmx 模板
VMX_TEMPLATE = """#!/usr/bin/vmware
.encoding = "UTF-8"
displayName = "{display_name}"
guestOS = "{guest_os}"
firmware = "{firmware}"
virtualHW.version = "21"
memsize = "{mem_size}"
numvcpus = "2"
sched.cpu.affinity = "all"
sched.mem.pin = "TRUE"

# IDE 控制器 (CD-ROM 用 IDE 更稳定)
ide0:0.present = "TRUE"
ide0:0.deviceType = "cdrom-image"
ide0:0.fileName = "{iso_path}"
ide0:0.autodetect = "TRUE"

# 网卡 1 (WAN)
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "e1000"
ethernet0.startConnected = "TRUE"
ethernet0.addressType = "generated"

# 网卡 2 (LAN)  
ethernet1.present = "TRUE"
ethernet1.connectionType = "hostonly"
ethernet1.virtualDev = "e1000"
ethernet1.startConnected = "TRUE"
ethernet1.addressType = "generated"

# 串口 (控制台日志)
serial0.present = "TRUE"
serial0.fileType = "thinprint"
serial0.startConnected = "TRUE"

# 禁用不必要的硬件
sound.present = "FALSE"
usb.present = "FALSE"
svga.autodetect = "TRUE"
pciBridge0.present = "TRUE"
"""


def run_qemu(iso_path):
    """在 QEMU 中测试"""
    if not shutil.which("qemu-system-x86_64"):
        warn("QEMU not found. Install with:")
        warn("  sudo apt install qemu-system-x86 qemu-kvm")
        return

    info("Starting QEMU (Ctrl+Alt+G to release mouse)...")
    print(f"""
    QEMU 配置:
    - CPU: 2 cores
    - RAM: 512 MB
    - 网卡1 (WAN): 用户模式网络 (自动 DHCP)
    - 网卡2 (LAN): 内部网络 192.168.2.0/24
    - 串口重定向到终端 (可选: -nographic)

    软路由启动后:
    - WAN 会自动获取 10.0.2.0/24 网段 IP
    - LAN 地址: 192.168.2.1
    - 在 LAN 客户端可访问 http://192.168.2.1
    """)

    cmd = [
        "qemu-system-x86_64",
        "-m", "512",
        "-smp", "2",
        "-cdrom", iso_path,
        "-boot", "d",
        "-netdev", "user,id=wan,net=10.0.2.0/24,dhcpstart=10.0.2.10",
        "-device", "e1000,netdev=wan,mac=52:54:00:12:34:01",
        "-netdev", "user,id=lan,net=192.168.2.0/24,dhcpstart=192.168.2.10",
        "-device", "e1000,netdev=lan,mac=52:54:00:12:34:02",
        "-vga", "std",
        "-display", "gtk",
    ]

    info(f"Running: {' '.join(cmd)}")
    subprocess.run(cmd)


# ─── 主流程 ─────────────────────────────────────────────────

def build(quick=False):
    """主构建流程"""
    print(f"""
╔══════════════════════════════════════════╗
║   Reasonix Router v{VERSION}  ISO Builder    ║
╚══════════════════════════════════════════╝
""")

    # 1. 检查依赖
    if not check_deps():
        return None

    # 2. 获取内核
    info("Step 1/4: Obtaining kernel...")
    kernel = None
    if quick:
        # 快速模式: 使用本地已有内核
        for k in [os.path.join(WORK_DIR, "kernel", "vmlinuz"),
                  "/boot/vmlinuz", "/boot/vmlinuz-lts"]:
            if os.path.exists(k):
                kernel = k
                ok(f"Using local kernel: {k}")
                break
    if not kernel:
        kernel = extract_kernel()
    if not kernel:
        return None

    # 3. 获取 BusyBox
    info("Step 2/4: Obtaining BusyBox...")
    busybox = None
    if quick:
        local_bb = os.path.join(WORK_DIR, "busybox", "busybox")
        if os.path.exists(local_bb):
            busybox = local_bb
            ok(f"Using local BusyBox: {local_bb}")
    if not busybox:
        busybox = download_busybox()
    if not busybox:
        return None

    # 4. 构建 initramfs
    info("Step 3/4: Building initramfs...")
    initramfs = create_initramfs(busybox)
    if not initramfs:
        return None

    # 5. 构建 ISO
    info("Step 4/4: Assembling ISO...")
    iso = build_iso(kernel, initramfs)
    if not iso:
        return None

    print(f"""
╔══════════════════════════════════════════╗
║   ✅  Build Complete!                     ║
║                                           ║
║   ISO: {os.path.basename(iso)}
║   Size: {os.path.getsize(iso)/1024/1024:.1f} MB
║                                           ║
║   在 QEMU 中测试:                         ║
║     python build.py --qemu                ║
║                                           ║
║   手动测试:                               ║
║     qemu-system-x86_64 -m 512             ║
║       -cdrom {os.path.basename(iso)}
║       -netdev user,id=wan                 ║
║       -device e1000,netdev=wan            ║
║       -netdev user,id=lan                  ║
║       -device e1000,netdev=lan            ║
╚══════════════════════════════════════════╝
""")

    return iso


def main():
    if len(sys.argv) > 1:
        arg = sys.argv[1].lower()
        if arg in ('-c', '--clean'):
            clean()
            return
        elif arg in ('-q', '--quick'):
            build(quick=True)
            return
        elif arg in ('--qemu', '--run'):
            iso = build()
            if iso:
                run_qemu(iso)
            return
        elif arg in ('-a', '--all', '--all-formats'):
            iso = build()
            if iso:
                build_formats(iso)
            return
        elif arg in ('--usb',):
            iso = build()
            if iso:
                build_usb_image(iso)
            return
        elif arg in ('-h', '--help'):
            print(__doc__)
            return

    iso = build()
    if iso:
        build_formats(iso)


if __name__ == "__main__":
    main()
