<#
.SYNOPSIS
  Reasonix Router - USB 启动盘写入工具 (Windows)
  将镜像写入 USB 驱动器，制作可启动安装盘

.DESCRIPTION
  用法:
    .\scripts\write-usb.ps1                    # 交互模式
    .\scripts\write-usb.ps1 -Image dist\reasonix-router-1.0.img  # 指定镜像
    .\scripts\write-usb.ps1 -Image dist\reasonix-router-1.0.iso  # ISO 也可用
  
  注意: 需要管理员权限运行!
#>

param(
    [string]$Image = "",
    [switch]$Force
)

# 需要管理员权限
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ 需要管理员权限！请以管理员身份运行 PowerShell。" -ForegroundColor Red
    Write-Host "   右键 PowerShell → 以管理员身份运行" -ForegroundColor Yellow
    exit 1
}

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

Write-Host @"

╔══════════════════════════════════════════╗
║  Reasonix Router - USB 启动盘写入工具    ║
╚══════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# 查找镜像文件
if (-not $Image) {
    $candidates = @()
    $candidates += Get-ChildItem (Join-Path $ProjectRoot "dist\*.img") -ErrorAction SilentlyContinue
    $candidates += Get-ChildItem (Join-Path $ProjectRoot "dist\*.iso") -ErrorAction SilentlyContinue
    
    if ($candidates.Count -eq 0) {
        Write-Host "❌ 未找到镜像文件。请先构建:" -ForegroundColor Red
        Write-Host "   python build.py --usb" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "可用镜像:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $size = "{0:N1} MB" -f ($candidates[$i].Length / 1MB)
        Write-Host "  [$i] $($candidates[$i].Name) ($size)" -ForegroundColor White
    }
    $choice = Read-Host "选择镜像编号 [0]"
    if (-not $choice) { $choice = 0 }
    $Image = $candidates[$choice].FullName
}

if (-not (Test-Path $Image)) {
    Write-Host "❌ 文件不存在: $Image" -ForegroundColor Red
    exit 1
}

$imageSize = (Get-Item $Image).Length
Write-Host "✅ 镜像: $Image ($($imageSize/1MB -as [int]) MB)" -ForegroundColor Green

# 列出可用磁盘
Write-Host "`n💾 可用磁盘:" -ForegroundColor Cyan
$disks = Get-Disk | Where-Object { $_.BusType -ne "LoB" -and $_.Size -gt 1GB -and $_.OperationalStatus -eq "Online" }
$usbDisks = @()

foreach ($disk in $disks) {
    $style = if ($disk.PartitionStyle -eq "RAW") { "RAW" } else { "已分区" }
    $busType = "$($disk.BusType)"
    $size = "{0:N1} GB" -f ($disk.Size / 1GB)
    $path = "\\\\.\\PHYSICALDRIVE$($disk.Number)"
    
    # 标记 USB 设备
    $isUSB = $disk.BusType -eq "USB"
    $tag = if ($isUSB) { "🔵 USB" } else { "   " }
    Write-Host "  $tag 磁盘 $($disk.Number): $($disk.FriendlyName) ($size) [$busType]"
    
    if ($isUSB) {
        $usbDisks += $disk
    }
}

if ($usbDisks.Count -eq 0) {
    Write-Host "  ⚠️  未检测到 USB 设备！" -ForegroundColor Yellow
    Write-Host "  请插入 USB 闪存盘后重试。" -ForegroundColor Yellow
    exit 1
}

# 选择目标磁盘
$targetDisk = $usbDisks[0]
if ($usbDisks.Count -gt 1) {
    $choice = Read-Host "选择 USB 磁盘编号 [0-$($usbDisks.Count-1)]"
    if ($choice -and $choice -ge 0 -and $choice -lt $usbDisks.Count) {
        $targetDisk = $usbDisks[$choice]
    }
}

$targetPath = "\\\\.\\PHYSICALDRIVE$($targetDisk.Number)"

Write-Host "`n⚠️  ${RED}警告: 磁盘 $($targetDisk.Number) ($($targetDisk.FriendlyName)) 上的所有数据将被清除！" -ForegroundColor Red
Write-Host "   镜像大小: $($imageSize/1MB -as [int]) MB" -ForegroundColor Yellow
Write-Host "   目标磁盘: $($targetDisk.FriendlyName) ($($targetDisk.Size/1GB -as [int]) GB)" -ForegroundColor Yellow

if (-not $Force) {
    $confirm = Read-Host "`n确认写入? (输入 YES 确认)"
    if ($confirm -ne "YES") {
        Write-Host "已取消。" -ForegroundColor Yellow
        exit 0
    }
}

# 写入
Write-Host "`n📝 正在写入 $Image 到 $targetPath ..." -ForegroundColor Cyan

# 打开磁盘设备进行写入
$fileStream = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Write, [System.IO.FileAccess]::Write)
$imageStream = [System.IO.File]::OpenRead($Image)
$buffer = New-Object byte[] (4MB)
$totalWritten = 0
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while ($bytesRead = $imageStream.Read($buffer, 0, $buffer.Length)) {
        $fileStream.Write($buffer, 0, $bytesRead)
        $totalWritten += $bytesRead
        $percent = [math]::Round($totalWritten / $imageSize * 100, 1)
        $speed = $totalWritten / $stopwatch.Elapsed.TotalSeconds / 1MB
        Write-Progress -Activity "写入 USB..." -Status "$percent% - $($speed -as [int]) MB/s" -PercentComplete $percent
    }
    Write-Progress -Activity "写入 USB..." -Completed
    
    $elapsed = $stopwatch.Elapsed.TotalSeconds
    $speed = $totalWritten / $elapsed / 1MB
    Write-Host "✅ 写入完成! $($totalWritten/1MB -as [int]) MB 已写入, 平均速度: $($speed -as [int]) MB/s" -ForegroundColor Green
    
    # 刷新缓冲区
    $fileStream.Flush($true)
    Start-Sleep -Seconds 1
    
    Write-Host "`n📋 下一步:" -ForegroundColor Cyan
    Write-Host "  1. 安全弹出 USB 设备" -ForegroundColor White
    Write-Host "  2. 将 USB 插入要安装的电脑" -ForegroundColor White
    Write-Host "  3. 开机从 USB 启动 (通常按 F12/F2/Del 选择启动设备)" -ForegroundColor White
    Write-Host "  4. 在 GRUB 菜单选择「安装到硬盘」" -ForegroundColor White
    Write-Host "  5. 按照安装向导完成安装" -ForegroundColor White
    
} catch {
    Write-Host "❌ 写入失败: $_" -ForegroundColor Red
} finally {
    $imageStream.Close()
    $fileStream.Close()
}
