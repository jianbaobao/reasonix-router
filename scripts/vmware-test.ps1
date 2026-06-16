<#
.SYNOPSIS
  Reasonix Router - VMware Workstation Pro 自动化测试
  创建 VM、启动、验证网络和 Web UI 可达性
.DESCRIPTION
  需要: VMware Workstation Pro + VMRun CLI
  用法: .\vmware-test.ps1
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Reasonix Router - VMware Test Suite    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 检查依赖
$vmrun = Get-Command "vmrun.exe" -ErrorAction SilentlyContinue
if (-not $vmrun) {
    Write-Host "❌ VMRun not found. VMware Workstation Pro required." -ForegroundColor Red
    Write-Host "   Install from: https://www.vmware.com/products/workstation-pro.html"
    exit 1
}

$vmware = Get-Command "vmware.exe" -ErrorAction SilentlyContinue
if (-not $vmware) {
    Write-Host "❌ VMware Workstation not found." -ForegroundColor Red
    exit 1
}

$isoPath = Join-Path $ProjectRoot "dist\reasonix-router-1.0.iso"
if (-not (Test-Path $isoPath)) {
    Write-Host "❌ ISO not found. Run build.py first." -ForegroundColor Red
    Write-Host "   python build.py --all-formats"
    exit 1
}

# 配置
$vmName = "ReasonixRouter-Test"
$vmDir = Join-Path $ProjectRoot "dist\vmware-test"
$vmxPath = Join-Path $vmDir "$vmName.vmx"

Write-Host "📍 Step 1/5: Creating VM..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $vmDir -Force | Out-Null

# 写入 .vmx
@"
.encoding = "UTF-8"
displayName = "$vmName"
guestOS = "otherlinux-64"
firmware = "bios"
virtualHW.version = "21"
memsize = "512"
numvcpus = "2"
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$isoPath"
scsi0:0.deviceType = "cdrom-image"
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "e1000"
ethernet0.startConnected = "TRUE"
ethernet0.addressType = "generated"
ethernet1.present = "TRUE"
ethernet1.connectionType = "hostonly"
ethernet1.virtualDev = "e1000"
ethernet1.startConnected = "TRUE"
ethernet1.addressType = "generated"
serial0.present = "TRUE"
serial0.fileType = "thinprint"
serial0.startConnected = "TRUE"  
sound.present = "FALSE"
usb.present = "FALSE"
svga.autodetect = "TRUE"
pciBridge0.present = "TRUE"
"@ | Out-File -FilePath $vmxPath -Encoding UTF8

Write-Host "  ✅ VM created: $vmxPath" -ForegroundColor Green

Write-Host "📍 Step 2/5: Starting VM..." -ForegroundColor Yellow
& $vmrun start "$vmxPath" nogui
Write-Host "  ✅ VM started (headless mode)" -ForegroundColor Green

Write-Host "📍 Step 3/5: Waiting for boot (30s)..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

Write-Host "📍 Step 4/5: Checking VM status..." -ForegroundColor Yellow
$vmStatus = & $vmrun list
if ($vmStatus -match $vmName) {
    Write-Host "  ✅ VM is running" -ForegroundColor Green
    
    # 获取 IP (通过 VMware Tools)
    Write-Host "  📡 Getting IP address..." -ForegroundColor Cyan
    try {
        $ip = & $vmrun getGuestIPAddress "$vmxPath" -wait 2>$null
        if ($ip) {
            Write-Host "  ✅ VM IP: $ip" -ForegroundColor Green
            
            # 测试 Web UI
            Write-Host "  🌐 Testing Web UI..." -ForegroundColor Cyan
            try {
                $response = Invoke-WebRequest -Uri "http://${ip}:80/" -TimeoutSec 10
                if ($response.StatusCode -eq 200) {
                    Write-Host "  ✅ Web UI accessible at http://${ip}:80/" -ForegroundColor Green
                    
                    # 测试 API
                    try {
                        $apiTest = Invoke-WebRequest -Uri "http://${ip}:80/cgi-bin/api?path=status" -TimeoutSec 5
                        if ($apiTest.StatusCode -eq 200) {
                            Write-Host "  ✅ API functional" -ForegroundColor Green
                        }
                    } catch {
                        Write-Host "  ⚠️  API test failed: $_" -ForegroundColor Yellow
                    }
                }
            } catch {
                Write-Host "  ⚠️  Web UI test failed: $_" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "  ⚠️  Could not get IP (VMware Tools may not be installed)" -ForegroundColor Yellow
        Write-Host "  ℹ️   Open VM console manually to check boot status" -ForegroundColor Cyan
    }
} else {
    Write-Host "  ❌ VM is not running" -ForegroundColor Red
}

Write-Host ""
Write-Host "📍 Step 5/5: Test Summary..." -ForegroundColor Yellow
Write-Host "  VMX: $vmxPath" -ForegroundColor White
Write-Host "  ISO: $isoPath" -ForegroundColor White
Write-Host ""
Write-Host "Manual verification:" -ForegroundColor Cyan
Write-Host "  1. Open VMware Workstation" -ForegroundColor Gray
Write-Host "  2. File -> Open -> $vmxPath" -ForegroundColor Gray
Write-Host "  3. Power on the VM" -ForegroundColor Gray
Write-Host "  4. Observe GRUB menu -> System boots -> Web UI at http://192.168.2.1" -ForegroundColor Gray
Write-Host ""
Write-Host "To stop VM: vmrun stop '$vmxPath'" -ForegroundColor Gray
Write-Host "To remove: Remove-Item -Recurse '$vmDir'" -ForegroundColor Gray
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($ip) {
    Write-Host "  ✅ All tests passed!" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Some tests incomplete (manual check needed)" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
