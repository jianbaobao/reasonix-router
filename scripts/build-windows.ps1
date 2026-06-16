<#
.SYNOPSIS
  Reasonix Router - Windows 一键构建脚本
  自动检查/安装 WSL、构建 ISO、启动 QEMU 测试
.DESCRIPTION
  在 Windows 10/11 上使用 WSL 自动构建 Reasonix Router ISO
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Reasonix Router - Windows Builder      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 1. 检查 WSL
Write-Host "📍 Step 1/4: 检查 WSL..." -ForegroundColor Yellow
$wslInstalled = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslInstalled) {
    Write-Host "  ⚠️  WSL 未安装。正在启用 WSL 功能..." -ForegroundColor Yellow
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /quiet
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /quiet
    Write-Host "  请重启计算机后重新运行此脚本" -ForegroundColor Red
    exit 1
}

# 2. 检查 Ubuntu 是否已安装
Write-Host "📍 Step 2/4: 检查 WSL 发行版..." -ForegroundColor Yellow
$distros = wsl -l -v 2>&1 | Out-String
if ($distros -notmatch "Ubuntu") {
    Write-Host "  ⬇️  正在安装 Ubuntu (首次安装需要几分钟)..." -ForegroundColor Yellow
    wsl --install -d Ubuntu
    Write-Host "  ⚠️  安装完成后请重新启动终端" -ForegroundColor Red
    exit 0
}
Write-Host "  ✅ Ubuntu 已安装" -ForegroundColor Green

# 3. 在 WSL 中构建 ISO
Write-Host "📍 Step 3/4: 在 WSL 中构建 ISO..." -ForegroundColor Yellow

$buildScript = @"
cd ~
mkdir -p reasonix-router
cd reasonix-router

# 复制项目文件
cp -r /mnt/$($ProjectRoot.Replace(':','').Replace('\','/'))/* .

# 安装依赖
sudo apt-get update -qq
sudo apt-get install -y -qq grub-pc-bin grub-common xorriso mtools python3 2>/dev/null | tail -1

# 运行验证
python3 scripts/verify.py

# 构建
python3 build.py

# 复制 ISO 回 Windows
cp dist/*.iso /mnt/$($ProjectRoot.Replace(':','').Replace('\','/'))/dist/ 2>/dev/null
echo "BUILD_DONE"
"@

$result = wsl -d Ubuntu -- bash -c $buildScript
if ($result -match "BUILD_DONE") {
    Write-Host "  ✅ ISO 构建成功!" -ForegroundColor Green
} else {
    Write-Host "  ❌ 构建失败:" -ForegroundColor Red
    Write-Host $result
    exit 1
}

# 4. 检查 QEMU (可选)
Write-Host "📍 Step 4/4: 检查 QEMU..." -ForegroundColor Yellow
$qemuCheck = Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue
if ($qemuCheck) {
    Write-Host "  ✅ QEMU 已安装" -ForegroundColor Green
    Write-Host ""
    Write-Host "启动测试:" -ForegroundColor Cyan
    Write-Host "  qemu-system-x86_64 -m 512 -cdrom dist/reasonix-router-1.0.iso" -ForegroundColor White
    Write-Host "    -netdev user,id=wan -device e1000,netdev=wan" -ForegroundColor White
    Write-Host "    -netdev user,id=lan -device e1000,netdev=lan" -ForegroundColor White
} else {
    Write-Host "  ⚠️  QEMU 未安装。如需本地测试，请安装 QEMU:" -ForegroundColor Yellow
    Write-Host "  1. 下载: https://qemu.weilnetz.de/w64/2024/qemu-w64-setup-20241130.exe" -ForegroundColor Gray
    Write-Host "  2. 或将 ISO 导入 VirtualBox/VMware 测试" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ✅ 构建完成!" -ForegroundColor Green
Write-Host "  ISO 位置: $ProjectRoot\dist\reasonix-router-1.0.iso" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
