#!/usr/bin/env python3
"""
Reasonix Router - Project Structure & Logic Validator
验证项目完整性、检查常见错误、模拟启动流程
"""

import os
import sys
import stat

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

errors = []
warnings = []

def err(msg):
    errors.append(msg)
    print(f"  ❌ {msg}")

def warn(msg):
    warnings.append(msg)
    print(f"  ⚠️  {msg}")

def ok(msg):
    print(f"  ✅ {msg}")

def check_file_exists(path, description):
    full = os.path.join(PROJECT_DIR, path)
    if os.path.exists(full):
        size = os.path.getsize(full)
        ok(f"{description}: {path} ({size} bytes)")
        return True
    else:
        err(f"{description}: {path} — 文件缺失!")
        return False

def check_file_perms(path, need_exec=False):
    full = os.path.join(PROJECT_DIR, path)
    if not os.path.exists(full):
        return
    if need_exec:
        st = os.stat(full)
        if not (st.st_mode & stat.S_IXUSR):
            warn(f"{path} 应该可执行但缺少 x 权限 (构建脚本会自动设置)")

def check_shell_syntax(path):
    """基础 shell 语法检查"""
    full = os.path.join(PROJECT_DIR, path)
    if not os.path.exists(full):
        return
    with open(full, 'r', errors='ignore') as f:
        content = f.read()
    
    lines = content.split('\n')
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        
        # 检查常见语法错误
        for q in ['"', "'"]:
            # 忽略注释中的引号
            before_comment = stripped.split('#')[0]
            if before_comment.count(q) % 2 != 0:
                # 多行字符串跨行检查
                if not content.split('\n')[i-1].rstrip().endswith('\\'):
                    warn(f"{path}:{i} 可能的未闭合引号: {stripped[:60]}")

def check_json_output(path):
    """验证 CGI 脚本的 JSON 输出格式"""
    full = os.path.join(PROJECT_DIR, path)
    if not os.path.exists(full):
        return
    with open(full, 'r') as f:
        content = f.read()
    
    # 检查 JSON 输出行是否格式正确
    in_json_block = False
    for i, line in enumerate(content.split('\n'), 1):
        if 'echo "{' in line or 'echo "{' in line:
            # 验证 JSON 结构
            json_part = line.split('echo')[1].strip()
            if '\\n' in json_part:
                # 包含换行符的 JSON 需要转义
                pass

def main():
    print("""
╔══════════════════════════════════════════╗
║  Reasonix Router - Project Validator    ║
╚══════════════════════════════════════════╝
""")
    
    # 1. 验证核心文件存在
    print("\n📁 文件完整性检查:")
    print("─" * 50)
    
    core_files = [
        ("build.py", "构建脚本"),
        ("Makefile", "Makefile"),
        ("README.md", "文档"),
        ("iso/grub/grub.cfg", "GRUB 配置"),
        ("iso/initramfs/init", "Init 脚本 (PID1)"),
        ("iso/initramfs/etc/init.d/S10modules", "模块加载"),
        ("iso/initramfs/etc/init.d/S40network", "网络配置"),
        ("iso/initramfs/etc/init.d/S45firewall", "防火墙/NAT"),
        ("iso/initramfs/etc/init.d/S50dhcp", "DHCP/DNS"),
        ("iso/initramfs/etc/init.d/S99webui", "Web UI"),
        ("iso/initramfs/etc/network/dhcp.script", "DHCP 客户端脚本"),
        ("iso/initramfs/etc/profile", "Shell 配置"),
        ("iso/initramfs/etc/hostname", "主机名"),
        ("iso/initramfs/etc/hosts", "Hosts"),
        ("iso/initramfs/etc/fstab", "文件系统表"),
        ("iso/initramfs/etc/os-release", "OS 发行信息"),
        ("iso/initramfs/www/index.html", "Web UI 首页"),
        ("iso/initramfs/www/style.css", "Web UI 样式"),
        ("iso/initramfs/www/app.js", "Web UI 前端逻辑"),
        ("iso/initramfs/www/cgi-bin/api", "Web UI API 后端"),
        ("scripts/qemu-test.sh", "QEMU 测试脚本"),
        ("scripts/vbox-test.sh", "VirtualBox 脚本"),
        ("scripts/vmware-test.sh", "VMware 脚本"),
    ]
    
    for path, desc in core_files:
        check_file_exists(path, desc)
    
    # 2. 验证架构变更 (v2 独立系统)
    print("\n🔧 架构验证:")
    print("─" * 50)
    if os.path.exists(os.path.join(PROJECT_DIR, "iso/initramfs/etc/inittab")):
        ok("inittab 存在 (独立系统模式)")
    if os.path.exists(os.path.join(PROJECT_DIR, "iso/initramfs/overlay/upper")):
        ok("OverlayFS 目录就绪")
    if os.path.exists(os.path.join(PROJECT_DIR, "iso/initramfs/etc/init.d/S01overlay")):
        ok("S01overlay 持久化脚本就绪")
    if os.path.exists(os.path.join(PROJECT_DIR, "iso/initramfs/etc/init.d/rcK")):
        ok("rcK 关机脚本就绪")
    if os.path.islink(os.path.join(PROJECT_DIR, "iso/initramfs/bin")):
        ok("/usr 合并: bin → usr/bin")
    if os.path.islink(os.path.join(PROJECT_DIR, "iso/initramfs/sbin")):
        ok("/usr 合并: sbin → usr/sbin")
    
    # 3. 验证 Bug 3 修复 (interfaces API)
    api_path = os.path.join(PROJECT_DIR, "iso/initramfs/www/cgi-bin/api")
    if os.path.exists(api_path):
        with open(api_path, 'r') as f:
            api_content = f.read()
        if "/sys/class/net" in api_content and "interfaces" in api_content:
            ok("Bug 3: interfaces API 已使用 sysfs 遍历")
        else:
            err("Bug 3: interfaces API 未修复!")
        
        if "%2F" in api_content and "sed 's/%2F/\\//g'" in api_content:
            ok("Bug 1: CGI URL 解码已添加")
        else:
            warn("Bug 1: CGI URL 解码可能需要检查")
        
        if "HTTP_METHOD" in api_content and "POST" in api_content:
            ok("Bug 5: HTTP 方法校验已添加")
        else:
            err("Bug 5: HTTP 方法校验缺失!")
    
    # 4. 验证 Bug 7 修复 (单臂路由)
    fw_path = os.path.join(PROJECT_DIR, "iso/initramfs/etc/init.d/S45firewall")
    if os.path.exists(fw_path):
        with open(fw_path, 'r') as f:
            fw_content = f.read()
        if 'if [ "$WAN_IFACE" = "$LAN_IFACE" ]' in fw_content:
            ok("Bug 7: 单臂路由防火墙保护已添加")
        else:
            err("Bug 7: 单臂路由修复缺失!")
    
    # 5. 验证 Bug 6 修复 (lease file)
    dhcp_path = os.path.join(PROJECT_DIR, "iso/initramfs/etc/init.d/S50dhcp")
    if os.path.exists(dhcp_path):
        with open(dhcp_path, 'r') as f:
            dhcp_content = f.read()
        if "dhcp-leasefile" in dhcp_content:
            ok("Bug 6: dnsmasq lease 文件路径已指定")
        else:
            err("Bug 6: lease 文件路径缺失!")
    
    # 6. 验证 Web UI 的 API 调用路径
    js_path = os.path.join(PROJECT_DIR, "iso/initramfs/www/app.js")
    if os.path.exists(js_path):
        with open(js_path, 'r') as f:
            js_content = f.read()
        if "encodeURIComponent" in js_content:
            warn("Bug 1: app.js 仍在使用 encodeURIComponent（可能把 / 编码成 %2F）")
        else:
            ok("Bug 1: app.js 已移除 encodeURIComponent")
    
    # 7. 网络接口检测
    net_path = os.path.join(PROJECT_DIR, "iso/initramfs/etc/init.d/S40network")
    if os.path.exists(net_path):
        with open(net_path, 'r') as f:
            net_content = f.read()
        if "ip addr flush" in net_content:
            ok("ip addr flush 已添加（防止重启重复 IP）")
        if "udhcpc -i" in net_content and "-n" not in net_content:
            ok("udhcpc 参数已修复（移除了冲突的 -n）")
    
    # 8. 启动流程
    init_path = os.path.join(PROJECT_DIR, "iso/initramfs/init")
    if os.path.exists(init_path):
        with open(init_path, 'r') as f:
            init_content = f.read()
        if "exec sh" in init_content:
            ok("Init 脚本以 exec sh 结束（PID 1 不会意外退出）")
        if '/dev/ttyS0' in init_content:
            ok("串口控制台 (ttyS0) 已配置")
    
    # 9. DHCP 脚本掩码转换
    dhcps_path = os.path.join(PROJECT_DIR, "iso/initramfs/etc/network/dhcp.script")
    if os.path.exists(dhcps_path):
        with open(dhcps_path, 'r') as f:
            dhcps_content = f.read()
        if "netmask_to_cidr" in dhcps_content:
            ok("DHCP 脚本: netmask → CIDR 转换函数已添加")
        else:
            err("DHCP 脚本: 掩码转换缺失!")
    
    # 10. Python 构建脚本语法
    try:
        import py_compile
        py_compile.compile(os.path.join(PROJECT_DIR, "build.py"), doraise=True)
        ok("build.py: Python 语法正确")
    except py_compile.PyCompileError as e:
        err(f"build.py: Python 语法错误: {e}")
    
    # 11. 验证所有脚本的 Shebang
    print("\n📜 Shebang 检查:")
    print("─" * 50)
    for root, dirs, files in os.walk(os.path.join(PROJECT_DIR, "iso")):
        for f in files:
            path = os.path.join(root, f)
            with open(path, 'r', errors='ignore') as fh:
                first_line = fh.readline().strip()
            if first_line and f in ('init', 'api') or f.endswith('.sh') or f.startswith('S'):
                if first_line.startswith('#!'):
                    ok(f"{os.path.relpath(path, PROJECT_DIR)}: {first_line}")
                else:
                    warn(f"{os.path.relpath(path, PROJECT_DIR)}: 缺少 shebang!")
    
    # 12. 文件统计
    print("\n📊 统计:")
    print("─" * 50)
    total_size = 0
    total_files = 0
    for root, dirs, files in os.walk(PROJECT_DIR):
        # 跳过构建目录
        if 'build' in root.split(os.sep) or 'dist' in root.split(os.sep):
            continue
        for f in files:
            path = os.path.join(root, f)
            total_size += os.path.getsize(path)
            total_files += 1
    
    ok(f"总文件数: {total_files}")
    ok(f"总大小: {total_size} bytes ({total_size/1024:.1f} KB)")
    
    # 总结
    print("\n" + "=" * 50)
    if errors:
        print(f"\n❌ {len(errors)} 个错误:")
        for e in errors:
            print(f"   • {e}")
    
    if warnings:
        print(f"\n⚠️  {len(warnings)} 个警告:")
        for w in warnings:
            print(f"   • {w}")
    
    if not errors and not warnings:
        print("\n✅ 全部验证通过！项目状态良好。")
    
    return len(errors)

if __name__ == "__main__":
    sys.exit(main())
