<#
.SYNOPSIS
  Reasonix Router - 全平台一键构建脚本
  自动安装依赖 → 构建 ISO → 打包 VMDK/VDI/OVA
.DESCRIPTION
  Windows: 自动安装 WSL Ubuntu + 构建
  Linux/Mac: 直接构建
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

Write-Host @"

╔══════════════════════════════════════════╗
║     Reasonix Router - Build System      ║
║      一键构建: ISO + VMDK + VDI + OVA    ║
╚══════════════════════════════════════════╝

"@ -ForegroundColor Cyan

function Test-Linux {
    return $IsLinux -or (-not $IsWindows -and [Environment]::OSVersion.Platform -eq 'Unix')
}

function Test-MacOS {
    return $IsMacOS -or (-not $IsWindows -and [Environment]::OSVersion.Platform -eq 'MacOSX')
}

function Build-Linux {
    Write-Host "📍 Linux 环境: 直接构建" -ForegroundColor Yellow

    # 安装依赖
    Write-Host "  📦 检查依赖..." -ForegroundColor Cyan
    $pkgs = @()
    if (-not (Get-Command "grub-mkrescue" -ErrorAction SilentlyContinue)) {
        $pkgs += "grub-pc-bin"
        $pkgs += "grub-common"
    }
    if (-not (Get-Command "xorriso" -ErrorAction SilentlyContinue)) { $pkgs += "xorriso" }
    if (-not (Get-Command "mformat" -ErrorAction SilentlyContinue)) { $pkgs += "mtools" }
    if (-not (Get-Command "qemu-img" -ErrorAction SilentlyContinue)) { $pkgs += "qemu-utils" }

    if ($pkgs.Count -gt 0) {
        Write-Host "  安装: $($pkgs -join ', ')" -ForegroundColor Yellow
        if (Get-Command "apt" -ErrorAction SilentlyContinue) {
            sudo apt update -qq
            sudo apt install -y -qq $pkgs
        } elseif (Get-Command "pacman" -ErrorAction SilentlyContinue) {
            sudo pacman -S --noconfirm $pkgs
        } elseif (Get-Command "apk" -ErrorAction SilentlyContinue) {
            sudo apk add $pkgs
        }
    }

    # 运行验证
    Write-Host "  🔍 验证项目..." -ForegroundColor Cyan
    python3 "$ProjectRoot/scripts/verify.py"

    # 构建
    Write-Host "  🔨 构建 ISO..." -ForegroundColor Cyan
    cd "$ProjectRoot"
    python3 build.py --all-formats

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ 构建成功!" -ForegroundColor Green
        $iso = Get-ChildItem "$ProjectRoot/dist/*.iso" | Select-Object -First 1
        if ($iso) {
            Write-Host "   ISO: $($iso.FullName) ($($iso.Length/1MB -as [int]) MB)" -ForegroundColor White
        }
    } else {
        Write-Host "❌ 构建失败!" -ForegroundColor Red
        exit 1
    }
}

function Build-Windows {
    Write-Host "📍 Windows 环境: 通过 WSL 构建" -ForegroundColor Yellow

    # 1. 检查 WSL
    Write-Host "  📦 Step 1/4: 检查 WSL..." -ForegroundColor Cyan
    $wslStatus = wsl --status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ⚠️  WSL 未安装, 正在安装..." -ForegroundColor Yellow
        Write-Host "  请以管理员身份运行此脚本, 或手动执行:" -ForegroundColor Gray
        Write-Host "    wsl --install -d Ubuntu" -ForegroundColor Gray
        Write-Host "  安装后重启终端重新运行此脚本。" -ForegroundColor Gray
        
        $choice = Read-Host "  是否尝试自动安装? [y/N]"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Write-Host "  正在启用 WSL 功能..." -ForegroundColor Yellow
            dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /quiet
            dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /quiet
            Write-Host "  ⚠️  请重启计算机后重新运行此脚本" -ForegroundColor Red
            exit 0
        }
        exit 1
    }

    # 2. 检查 Ubuntu 发行版
    Write-Host "  📦 Step 2/4: 检查 WSL 发行版..." -ForegroundColor Cyan
    $distros = wsl -l -v 2>&1
    if ($distros -notmatch "Ubuntu") {
        Write-Host "  ⬇️  正在安装 Ubuntu..." -ForegroundColor Yellow
        wsl --install -d Ubuntu
        Write-Host "  ⚠️  安装后请重启终端" -ForegroundColor Red
        exit 0
    }
    Write-Host "  ✅ Ubuntu 已就绪" -ForegroundColor Green

    # 3. 在 WSL 中构建
    Write-Host "  📦 Step 3/4: 在 WSL 中构建..." -ForegroundColor Cyan
    $buildScript = @"
cd ~
mkdir -p reasonix-build
cd reasonix-build

# 从 Windows 复制项目
cp -r "/mnt/$($ProjectRoot.Replace(':','').Replace('\','/'))/"* .

# 安装依赖
sudo apt-get update -qq 2>/dev/null
sudo apt-get install -y -qq grub-pc-bin grub-common xorriso mtools python3 qemu-utils 2>/dev/null

# 验证
python3 scripts/verify.py

# 构建所有格式
python3 build.py --all-formats

# 复制产物回 Windows
mkdir -p "/mnt/$($ProjectRoot.Replace(':','').Replace('\','/'))/dist/" 2>/dev/null
cp dist/* "/mnt/$($ProjectRoot.Replace(':','').Replace('\','/'))/dist/" 2>/dev/null
echo "BUILD_DONE"
"@
    $result = wsl -d Ubuntu -- bash -c "$buildScript"
    if ($result -match "BUILD_DONE") {
        Write-Host "  ✅ WSL 构建完成!" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  WSL 输出: $result" -ForegroundColor Yellow
    }

    # 4. 显示结果
    Write-Host "`n  📦 Step 4/4: 构建产物" -ForegroundColor Cyan
    $distDir = Join-Path $ProjectRoot "dist"
    if (Test-Path $distDir) {
        Get-ChildItem $distDir | ForEach-Object {
            $size = if ($_.Length -gt 1MB) { "$($_.Length/1MB -as [int]) MB" } else { "$($_.Length/1KB -as [int]) KB" }
            Write-Host "  ✅ $($_.Name) ($size)" -ForegroundColor Green
        }
    }
}

# ─── 主流程 ──────────────────────────────────────────────

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

if (Test-Linux) {
    Build-Linux
} elseif (Test-MacOS) {
    Write-Host "⚠️ macOS 暂不支持, 请使用 Linux 或 WSL" -ForegroundColor Yellow
    exit 1
} else {
    Build-Windows
}

$stopwatch.Stop()
Write-Host "`n⏱️  构建耗时: $($stopwatch.Elapsed.TotalSeconds -as [int]) 秒" -ForegroundColor Cyan
Write-Host "📂 输出目录: $(Join-Path $ProjectRoot 'dist')" -ForegroundColor White
Write-Host ""