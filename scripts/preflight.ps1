# preflight.ps1 — Windows 環境適性ゲート
# 「サンドボックスで安全に始めるローカルAI入門」実践編 第1章の前に実行
#
# 使い方:
#   powershell -ExecutionPolicy Bypass -File preflight.ps1

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "=== preflight: 環境適性チェック (Windows) ===" -ForegroundColor Cyan
Write-Host ""

$verdict = "PASS"
$checks = @()

function Add-Check {
    param([string]$Name, [string]$Value, [string]$Status, [string]$Note)
    $color = switch ($Status) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "Gray" }
    }
    $line = "  {0,-20} {1,-30} [{2}]" -f $Name, $Value, $Status
    Write-Host $line -ForegroundColor $color
    if ($Note) { Write-Host "                     $Note" -ForegroundColor DarkGray }
    $script:checks += @{ name=$Name; value=$Value; status=$Status; note=$Note }
}

# --- arch ---
$arch = $env:PROCESSOR_ARCHITECTURE
Add-Check -Name "arch" -Value $arch -Status "info"

# --- cpu_name ---
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
if ($null -eq $cpu) { $cpu = "unknown" }
Add-Check -Name "cpu" -Value $cpu.Trim() -Status "info"

# --- ram_gb ---
$ramBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$ramGb = [math]::Round($ramBytes / 1GB)
if ($ramGb -ge 32) {
    Add-Check -Name "ram" -Value "$ramGb GB" -Status "PASS" -Note "32GB以上: 実測表の環境と同等"
} elseif ($ramGb -ge 16) {
    Add-Check -Name "ram" -Value "$ramGb GB" -Status "PASS" -Note "16GB以上: 本書の手順を完遂可能"
} elseif ($ramGb -ge 8) {
    Add-Check -Name "ram" -Value "$ramGb GB" -Status "WARN" -Note "16GB未満: 小型モデル(1B)のみ動作可能"
    $verdict = "WARN"
} else {
    Add-Check -Name "ram" -Value "$ramGb GB" -Status "FAIL" -Note "8GB未満: 本書の手順を完遂できない可能性が高い"
    $verdict = "FAIL"
}

# --- disk_free_gb ---
$sysDrive = $env:SystemDrive
if ($null -eq $sysDrive) { $sysDrive = "C:" }
$disk = Get-PSDrive -Name $sysDrive.TrimEnd(':') -ErrorAction SilentlyContinue
if ($null -ne $disk) {
    $freeGb = [math]::Round($disk.Free / 1GB)
} else {
    $vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sysDrive'"
    if ($null -ne $vol) {
        $freeGb = [math]::Round($vol.FreeSpace / 1GB)
    } else {
        $freeGb = -1
    }
}
if ($freeGb -ge 20) {
    Add-Check -Name "disk_free" -Value "$freeGb GB ($sysDrive)" -Status "PASS"
} elseif ($freeGb -ge 10) {
    Add-Check -Name "disk_free" -Value "$freeGb GB ($sysDrive)" -Status "WARN" -Note "20GB 以上を推奨"
    if ($verdict -eq "PASS") { $verdict = "WARN" }
} elseif ($freeGb -ge 0) {
    Add-Check -Name "disk_free" -Value "$freeGb GB ($sysDrive)" -Status "FAIL" -Note "ディスク空き不足"
    $verdict = "FAIL"
} else {
    Add-Check -Name "disk_free" -Value "取得不可" -Status "WARN"
}

# --- virtualization ---
# VirtualizationFirmwareEnabled はハイパーバイザー稼働中に False を返すことがある。
# HyperVisorPresent（Hyper-V/WSL2 稼働中）を併用して判定する。
$vtEnabled = $false
$vtLabel = "not detected"
try {
    $cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1
    if ($cpuInfo.VirtualizationFirmwareEnabled -eq $true) {
        $vtEnabled = $true
        $vtLabel = "enabled"
    }
} catch {}
if (-not $vtEnabled) {
    try {
        $hvPresent = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
        if ($hvPresent -eq $true) {
            $vtEnabled = $true
            $vtLabel = "enabled (hypervisor active)"
        }
    } catch {}
}
if ($vtEnabled) {
    Add-Check -Name "virtualization" -Value $vtLabel -Status "PASS"
} else {
    Add-Check -Name "virtualization" -Value "not detected" -Status "WARN" -Note "BIOS で VT-x/AMD-V を有効にしてください（第1章参照）"
    if ($verdict -eq "PASS") { $verdict = "WARN" }
}

# --- wsl ---
# wsl.exe --version は UTF-16 LE で出力する。Console.OutputEncoding を
# 一時的に Unicode に切り替えてキャプチャし、元に戻す。
$wslVersion = ""
try {
    $null = Get-Command wsl.exe -ErrorAction Stop
    $prevEnc = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $wslOut = wsl --version 2>$null
    [Console]::OutputEncoding = $prevEnc
    $wslLine = ($wslOut | Where-Object { $_ -match 'WSL' } | Select-Object -First 1)
    if ($wslLine) { $wslVersion = $wslLine.Trim() -replace '\s+', ' ' }
} catch {}
if ($wslVersion) {
    Add-Check -Name "wsl" -Value $wslVersion -Status "PASS"
} else {
    Add-Check -Name "wsl" -Value "not found" -Status "WARN" -Note "WSL2 のインストールが必要です（第1章参照）"
    if ($verdict -eq "PASS") { $verdict = "WARN" }
}

# --- docker ---
$dockerVersion = ""
try {
    $dockerOut = docker --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $dockerVersion = $dockerOut.ToString().Trim()
    }
} catch {}
if ($dockerVersion) {
    Add-Check -Name "docker" -Value $dockerVersion -Status "PASS"
} else {
    Add-Check -Name "docker" -Value "not found" -Status "WARN" -Note "Docker Desktop のインストールが必要です（第1章参照）"
    if ($verdict -eq "PASS") { $verdict = "WARN" }
}

# --- tier ---
if ($ramGb -ge 32) { $tier = "recommended" }
elseif ($ramGb -ge 16) { $tier = "standard" }
elseif ($ramGb -ge 8)  { $tier = "minimum" }
else { $tier = "unsupported" }

# --- verdict ---
Write-Host ""
$verdictColor = switch ($verdict) {
    "PASS" { "Green" }
    "WARN" { "Yellow" }
    "FAIL" { "Red" }
    default { "White" }
}
Write-Host "  verdict: $verdict (tier: $tier)" -ForegroundColor $verdictColor
Write-Host ""

if ($verdict -eq "FAIL") { exit 2 }
elseif ($verdict -eq "WARN") { exit 1 }
else { exit 0 }
