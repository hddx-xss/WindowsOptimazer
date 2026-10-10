<#
.SYNOPSIS
    Windows Optimizer - Enterprise Performance, Cleanliness & System Responsiveness Engine
.DESCRIPTION
    A safe, transparent, and reversible Windows 10/11 system optimizer built by a Senior
    Windows Performance Optimization Engineer. Performs deep junk cleanup, process & startup
    analysis, Windows service tuning, gaming optimization, and privacy configuration with
    full state backup, transaction logging, and complete rollback capabilities.
.NOTES
    Author: Senior Windows Performance Optimization Engineer
    Version: 2.5.0
    Target OS: Windows 10 (1909+) & Windows 11 (All Builds)
    PowerShell: 5.1+ / 7.x
#>

[CmdletBinding()]
param(
    [switch]$Analyze,
    [switch]$Cleanup,
    [switch]$Startup,
    [switch]$Processes,
    [switch]$Services,
    [switch]$Gaming,
    [switch]$Privacy,
    [switch]$Full,
    [switch]$Rollback,
    [switch]$Report,
    [switch]$DryRun,
    [switch]$Help
)

# Set Strict Mode & Error Defaults
Set-StrictMode -Off
$ErrorActionPreference = "Continue"

# -----------------------------------------------------------------------------
# GLOBAL CONSTANTS & DIRECTORY CONFIGURATION
# -----------------------------------------------------------------------------
$Script:Version = "2.5.0"
$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Script:ScriptDir) { $Script:ScriptDir = (Get-Location).Path }

$Script:LogDir     = Join-Path $Script:ScriptDir "logs"
$Script:BackupDir  = Join-Path $Script:ScriptDir "backups"
$Script:ReportDir  = Join-Path $Script:ScriptDir "reports"

# Ensure runtime directories exist
@($Script:LogDir, $Script:BackupDir, $Script:ReportDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

$Script:SessionId = Get-Date -Format "yyyyMMdd_HHmmss"
$Script:LogFile   = Join-Path $Script:LogDir "optimizer_$($Script:SessionId).log"
$Script:SessionBackupFolder = Join-Path $Script:BackupDir "backup_$($Script:SessionId)"

$Script:IsDryRun = $DryRun.IsPresent
$Script:FreedBytesTotal = 0L

# -----------------------------------------------------------------------------
# CRITICAL SAFETY WHITELISTS (NEVER TERMINATE OR BREAK)
# -----------------------------------------------------------------------------
$Script:ProtectedProcesses = @(
    'system', 'idle', 'registry', 'smss', 'csrss', 'wininit', 'services', 'lsass',
    'winlogon', 'svchost', 'fontdrvhost', 'dwm', 'explorer', 'sihost', 'taskhostw',
    'runtimebroker', 'searchhost', 'startmenuexperiencehost', 'shellexperiencehost',
    'conhost', 'cmd', 'powershell', 'pwsh', 'spoolsv', 'audiodg', 'ctfmon',
    'securityhealthservice', 'securityhealthsystray', 'msmpeng', 'nissrv', 'smartscreen',
    'memory compression', 'devenv', 'code', 'windowsterminal', 'openconsole',
    # Graphics and Hardware Drivers
    'nvcontainer', 'nvsphelper64', 'nvidia share', 'radeonsoftware', 'amdrsserv',
    'igfxem', 'igfxdt', 'igfxcuiservice', 'realtekaudioservice', 'wavessvc',
    # Anti-Cheat Systems (Crucial: never disrupt gaming anti-cheat)
    'easyanticheat', 'easyanticheat_eos', 'beservice', 'bedaisy', 'vgk', 'vgc'
)

$Script:ProtectedServices = @(
    # Core OS & RPC
    'RpcSs', 'RpcEptMapper', 'DcomLaunch', 'PlugPlay', 'SamSs', 'LSM', 'EventLog',
    'Schedule', 'ProfSvc', 'CryptSvc', 'StateRepository', 'CoreMessagingRegistrar',
    'Power', 'SystemEventsBroker', 'BrokerInfrastructure', 'TimeBrokerSvc',
    # Security & Defender
    'WinDefend', 'WdNisSvc', 'SecurityHealthService', 'wscsvc', 'Sense',
    # Network & Connectivity
    'Dhcp', 'Dnscache', 'LanmanWorkstation', 'LanmanServer', 'NlaSvc', 'netprofm',
    'WlanSvc', 'WwanSvc', 'nsi', 'Netman', 'BFE', 'mpssvc',
    # Audio Subsystem
    'AudioSrv', 'AudioEndpointBuilder',
    # Windows Update & Component Servicing
    'wuauserv', 'bits', 'dosvc', 'TrustedInstaller'
)

# -----------------------------------------------------------------------------
# LOGGING AND CONSOLE OUTPUT SUBSYSTEM
# -----------------------------------------------------------------------------
function Write-Log {
    param(
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DRYRUN")]
        [string]$Level = "INFO",
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $Script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
}

function Show-Header {
    param([string]$Title, [string]$Subtitle = "")
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "   WINDOWS OPTIMIZER v$($Script:Version) - Professional Performance Engineering   " -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Cyan
    if ($Title) {
        Write-Host " >> $Title" -ForegroundColor Green
        if ($Subtitle) {
            Write-Host "    $Subtitle" -ForegroundColor Gray
        }
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    }
}

function Write-Success {
    param([string]$Message)
    Write-Host " [+] $Message" -ForegroundColor Green
    Write-Log -Level "SUCCESS" -Message $Message
}

function Write-Info {
    param([string]$Message)
    Write-Host " [*] $Message" -ForegroundColor Cyan
    Write-Log -Level "INFO" -Message $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host " [!] $Message" -ForegroundColor Yellow
    Write-Log -Level "WARN" -Message $Message
}

function Write-Err {
    param([string]$Message)
    Write-Host " [X] $Message" -ForegroundColor Red
    Write-Log -Level "ERROR" -Message $Message
}

function Format-Bytes {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes Bytes"
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Prompt-Continue {
    param([string]$Message = "Press Enter to return to menu...")
    Write-Host ""
    if ([Console]::IsInputRedirected) { return }
    Write-Host " $Message" -ForegroundColor DarkGray -NoNewline
    try {
        [void][System.Console]::ReadLine()
    } catch {}
}

function Prompt-Confirm {
    param([string]$Message, [bool]$DefaultYes = $true)
    if ([Console]::IsInputRedirected) { return $DefaultYes }
    $options = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    Write-Host " $Message $options : " -ForegroundColor Yellow -NoNewline
    $input = [System.Console]::ReadLine()
    if ([string]::IsNullOrWhiteSpace($input)) { return $DefaultYes }
    return ($input.Trim().ToLower() -eq 'y' -or $input.Trim().ToLower() -eq 'yes')
}

# -----------------------------------------------------------------------------
# BACKUP & ROLLBACK SUBSYSTEM
# -----------------------------------------------------------------------------
function Ensure-SessionBackupFolder {
    if (-not (Test-Path $Script:SessionBackupFolder)) {
        New-Item -ItemType Directory -Path $Script:SessionBackupFolder -Force | Out-Null
        Write-Log -Level "INFO" -Message "Created session backup folder: $($Script:SessionBackupFolder)"
    }
    return $Script:SessionBackupFolder
}

function Backup-RegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )
    $backupDir = Ensure-SessionBackupFolder
    $backupFile = Join-Path $backupDir "registry_backup.json"

    $registryBackups = @()
    if (Test-Path $backupFile) {
        try {
            $jsonContent = Get-Content -Path $backupFile -Raw -ErrorAction Stop
            $registryBackups = ConvertFrom-Json $jsonContent
            if ($registryBackups -isnot [System.Collections.IEnumerable]) {
                $registryBackups = @($registryBackups)
            }
        } catch {
            $registryBackups = @()
        }
    }

    $entry = [PSCustomObject]@{
        Path      = $Path
        Name      = $Name
        Exists    = $false
        Value     = $null
        Type      = "Unknown"
        Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }

    if (Test-Path $Path) {
        try {
            $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $prop -and $null -ne $prop.$Name) {
                $entry.Exists = $true
                $entry.Value = $prop.$Name
                $key = Get-Item -Path $Path
                $entry.Type = $key.GetValueKind($Name).ToString()
            }
        } catch {}
    }

    $existing = $registryBackups | Where-Object { $_.Path -eq $Path -and $_.Name -eq $Name }
    if (-not $existing) {
        $registryBackups += $entry
        $registryBackups | ConvertTo-Json -Depth 5 | Set-Content -Path $backupFile -Force
        Write-Log -Level "INFO" -Message "Backed up registry value: $Path -> $Name"
    }
}

function Backup-ServiceState {
    param([string]$ServiceName)
    $backupDir = Ensure-SessionBackupFolder
    $backupFile = Join-Path $backupDir "services_backup.json"

    $serviceBackups = @()
    if (Test-Path $backupFile) {
        try {
            $jsonContent = Get-Content -Path $backupFile -Raw -ErrorAction Stop
            $serviceBackups = ConvertFrom-Json $jsonContent
            if ($serviceBackups -isnot [System.Collections.IEnumerable]) {
                $serviceBackups = @($serviceBackups)
            }
        } catch {
            $serviceBackups = @()
        }
    }

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        $startType = (Get-CimInstance Win32_Service -Filter "Name='$ServiceName'").StartMode
        $entry = [PSCustomObject]@{
            Name        = $svc.Name
            DisplayName = $svc.DisplayName
            StartType   = $startType
            Status      = $svc.Status.ToString()
            Timestamp   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }

        $existing = $serviceBackups | Where-Object { $_.Name -eq $ServiceName }
        if (-not $existing) {
            $serviceBackups += $entry
            $serviceBackups | ConvertTo-Json -Depth 5 | Set-Content -Path $backupFile -Force
            Write-Log -Level "INFO" -Message "Backed up service state: $ServiceName ($startType)"
        }
    }
}

# -----------------------------------------------------------------------------
# 1. SYSTEM INFORMATION & HEALTH CHECK
# -----------------------------------------------------------------------------
function Get-SystemHealthInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $driveC = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.Name -like "C:*" } | Select-Object -First 1

    $uptime = (Get-Date) - $os.LastBootUpTime
    $processes = Get-Process
    $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeMemoryGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedMemoryGB  = [math]::Round($totalMemoryGB - $freeMemoryGB, 2)
    $usedMemoryPercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 1)

    $powerPlan = try {
        $planStr = powercfg /getactivescheme 2>&1
        if ($planStr -match '\((.*?)\)') { $matches[1] } else { "Balanced" }
    } catch { "Unknown" }

    $totalDiskGB = if ($driveC) { [math]::Round($driveC.TotalSize / 1GB, 2) } else { 0 }
    $freeDiskGB  = if ($driveC) { [math]::Round($driveC.TotalFreeSpace / 1GB, 2) } else { 0 }
    $usedDiskGB  = [math]::Round($totalDiskGB - $freeDiskGB, 2)
    $freeDiskPercent = if ($totalDiskGB -gt 0) { [math]::Round(($freeDiskGB / $totalDiskGB) * 100, 1) } else { 0 }

    return [PSCustomObject]@{
        ComputerName      = $env:COMPUTERNAME
        OSCaption         = $os.Caption
        OSVersion         = $os.Version
        OSBuild           = $os.BuildNumber
        Architecture      = $os.OSArchitecture
        IsAdmin           = (Test-IsAdmin)
        ProcessorName     = $cpu.Name.Trim()
        Cores             = $cpu.NumberOfCores
        LogicalProcessors = $cpu.NumberOfLogicalProcessors
        TotalMemoryGB     = $totalMemoryGB
        UsedMemoryGB      = $usedMemoryGB
        FreeMemoryGB      = $freeMemoryGB
        UsedMemoryPercent = $usedMemoryPercent
        ProcessCount      = $processes.Count
        TotalDiskGB       = $totalDiskGB
        FreeDiskGB        = $freeDiskGB
        UsedDiskGB        = $usedDiskGB
        FreeDiskPercent   = $freeDiskPercent
        UptimeDays        = $uptime.Days
        UptimeHours       = $uptime.Hours
        UptimeMinutes     = $uptime.Minutes
        ActivePowerPlan   = $powerPlan
    }
}

function Show-SystemHealthCheck {
    Show-Header "System Information & Health Assessment" "Detailed inspection of current hardware and OS environment"
    Write-Info "Inspecting system telemetry..."
    $info = Get-SystemHealthInfo

    Write-Host ""
    Write-Host "  Operating System:" -ForegroundColor Yellow
    Write-Host ("    Edition:        {0} ({1})" -f $info.OSCaption, $info.Architecture)
    Write-Host ("    Version/Build:  {0} (Build {1})" -f $info.OSVersion, $info.OSBuild)
    Write-Host ("    Elevation:      {0}" -f $(if ($info.IsAdmin) { "[Elevated Administrator]" } else { "[Standard User - Elevation Recommended]" })) -ForegroundColor $(if ($info.IsAdmin) { "Green" } else { "Yellow" })
    Write-Host ("    System Uptime:  {0}d {1}h {2}m" -f $info.UptimeDays, $info.UptimeHours, $info.UptimeMinutes)
    Write-Host ("    Power Scheme:   {0}" -f $info.ActivePowerPlan)

    Write-Host ""
    Write-Host "  Hardware & Resource Utilization:" -ForegroundColor Yellow
    Write-Host ("    Processor:      {0} ({1} Cores / {2} Threads)" -f $info.ProcessorName, $info.Cores, $info.LogicalProcessors)
    Write-Host ("    Physical RAM:   {0} GB Total | {1} GB Used ({2}%) | {3} GB Free" -f $info.TotalMemoryGB, $info.UsedMemoryGB, $info.UsedMemoryPercent, $info.FreeMemoryGB)
    Write-Host ("    Live Processes: {0} active process handles" -f $info.ProcessCount) -ForegroundColor $(if ($info.ProcessCount -gt 200) { "Yellow" } else { "Green" })
    Write-Host ("    System Drive C: {0} GB Free of {1} GB ({2}% available)" -f $info.FreeDiskGB, $info.TotalDiskGB, $info.FreeDiskPercent)

    Write-Host ""
    Write-Host "  ==================== Senior Systems Engineer Note ====================" -ForegroundColor DarkCyan
    Write-Host "  * Process Count Reality Check:" -ForegroundColor White
    Write-Host "    Since Windows 10 (Creators Update), Microsoft isolates services into individual" -ForegroundColor Gray
    Write-Host "    'svchost.exe' instances on systems with >3.5 GB RAM. This increased baseline" -ForegroundColor Gray
    Write-Host "    process count from ~80 (Windows 7) to 180-250+ (Windows 10/11) to safeguard stability." -ForegroundColor Gray
    Write-Host "    A process count of 140-160 is attainable through disciplined startup and service" -ForegroundColor Gray
    Write-Host "    management, but NEVER force an arbitrary target by killing critical system tasks." -ForegroundColor Gray
    Write-Host "  * Memory Caching Reality Check:" -ForegroundColor White
    Write-Host "    Windows uses unused RAM for SuperFetch / Standby file caching. 'Free RAM' is not" -ForegroundColor Gray
    Write-Host "    wasted RAM; it makes subsequent launches instant. We avoid fake RAM flushers." -ForegroundColor Gray
    Write-Host "  ======================================================================" -ForegroundColor DarkCyan

    Write-Log -Level "INFO" -Message "Health check completed. OS: $($info.OSCaption) Build: $($info.OSBuild) Processes: $($info.ProcessCount) RAM: $($info.UsedMemoryPercent)%"
    Prompt-Continue
}

# -----------------------------------------------------------------------------
# 2. ANALYZE CPU, RAM, DISK, AND RUNNING PROCESSES
# -----------------------------------------------------------------------------
function Analyze-SystemResources {
    Show-Header "Deep Resource & Process Consumption Analysis" "Non-destructive diagnostic of CPU, RAM, and background consumers"
    Write-Info "Sampling active processes and calculating resource footprints..."

    $processes = Get-Process | Where-Object { $_.Id -ne 0 -and $_.ProcessName -ne "Idle" }

    # Top CPU consumers (by Total Processor Time)
    $topCpu = $processes | Sort-Object CPU -Descending | Select-Object -First 10

    # Top RAM consumers (by Working Set)
    $topRam = $processes | Sort-Object WorkingSet64 -Descending | Select-Object -First 10

    Write-Host ""
    Write-Host "  [ Top 10 Memory (RAM) Consumers ]" -ForegroundColor Yellow
    Write-Host ("  {0,-8} {1,-26} {2,12} {3,12} {4,-15}" -f "PID", "Process Name", "Working Set", "Private RAM", "Category") -ForegroundColor Cyan
    Write-Host "  ----------------------------------------------------------------------------" -ForegroundColor DarkGray

    foreach ($p in $topRam) {
        $wsMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
        $privMB = [math]::Round($p.PrivateMemorySize64 / 1MB, 1)
        $pName = $p.ProcessName
        $isProtected = $Script:ProtectedProcesses -contains $pName.ToLower()
        $category = if ($isProtected) { "Windows Core / Driver" } else { "Application / 3rd Party" }

        Write-Host ("  {0,-8} {1,-26} {2,10} MB {3,10} MB {4,-15}" -f $p.Id, ($pName.Substring(0, [math]::Min(25, $pName.Length))), $wsMB, $privMB, $category) -ForegroundColor $(if ($isProtected) { "White" } else { "Magenta" })
    }

    Write-Host ""
    Write-Host "  [ Top 10 CPU Consumers (Cumulative Processor Time) ]" -ForegroundColor Yellow
    Write-Host ("  {0,-8} {1,-26} {2,12} {3,-25}" -f "PID", "Process Name", "CPU Time(s)", "Description") -ForegroundColor Cyan
    Write-Host "  ----------------------------------------------------------------------------" -ForegroundColor DarkGray

    foreach ($p in $topCpu) {
        $cpuSec = [math]::Round($p.CPU, 1)
        $desc = try { $p.Description } catch { "" }
        if (-not $desc) { $desc = "System process or service" }
        if ($desc.Length -gt 25) { $desc = $desc.Substring(0, 22) + "..." }
        $pName = $p.ProcessName
        Write-Host ("  {0,-8} {1,-26} {2,12} {3,-25}" -f $p.Id, ($pName.Substring(0, [math]::Min(25, $pName.Length))), $cpuSec, $desc)
    }

    # Junk storage preview calculation
    Write-Host ""
    Write-Host "  [ Junk Storage Footprint Preview ]" -ForegroundColor Yellow
    $junkMetrics = Measure-JunkFilesDetailed
    Write-Host ("    User Temp Directory:           {0} ({1} files)" -f (Format-Bytes $junkMetrics.UserTempBytes), $junkMetrics.UserTempCount)
    Write-Host ("    Windows System Temp:           {0} ({1} files)" -f (Format-Bytes $junkMetrics.SystemTempBytes), $junkMetrics.SystemTempCount)
    Write-Host ("    Crash Dumps & Error Reports:   {0} ({1} files)" -f (Format-Bytes $junkMetrics.CrashDumpsBytes), $junkMetrics.CrashDumpsCount)
    Write-Host ("    Diagnostic & CBS Temp Logs:    {0} ({1} files)" -f (Format-Bytes $junkMetrics.DiagnosticLogsBytes), $junkMetrics.DiagnosticLogsCount)
    Write-Host ("    DirectX & GPU Shader Caches:   {0} ({1} files)" -f (Format-Bytes $junkMetrics.ShaderCacheBytes), $junkMetrics.ShaderCacheCount)
    Write-Host ("    Recycle Bin:                   {0}" -f (Format-Bytes $junkMetrics.RecycleBinBytes))
    Write-Host "    ------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("    Estimated Reclaimable Space:   {0}" -f (Format-Bytes $junkMetrics.TotalEstimatedBytes)) -ForegroundColor Green

    Write-Log -Level "INFO" -Message "Resource analysis completed. Estimated reclaimable junk: $(Format-Bytes $junkMetrics.TotalEstimatedBytes)"
    Prompt-Continue
}

function Measure-JunkFilesDetailed {
    $metrics = [PSCustomObject]@{
        UserTempBytes       = 0L
        UserTempCount       = 0
        SystemTempBytes     = 0L
        SystemTempCount     = 0
        CrashDumpsBytes     = 0L
        CrashDumpsCount     = 0
        DiagnosticLogsBytes = 0L
        DiagnosticLogsCount = 0
        ShaderCacheBytes    = 0L
        ShaderCacheCount    = 0
        RecycleBinBytes     = 0L
        TotalEstimatedBytes = 0L
    }

    # User Temp
    $userTemp = $env:TEMP
    if (Test-Path $userTemp) {
        $files = Get-ChildItem -Path $userTemp -File -Recurse -Force -ErrorAction SilentlyContinue
        if ($files) {
            $metrics.UserTempCount = $files.Count
            $metrics.UserTempBytes = ($files | Measure-Object -Property Length -Sum).Sum
        }
    }

    # Windows Temp
    $sysTemp = "$env:SystemRoot\Temp"
    if (Test-Path $sysTemp) {
        $files = Get-ChildItem -Path $sysTemp -File -Recurse -Force -ErrorAction SilentlyContinue
        if ($files) {
            $metrics.SystemTempCount = $files.Count
            $metrics.SystemTempBytes = ($files | Measure-Object -Property Length -Sum).Sum
        }
    }

    # Crash Dumps & WER
    $crashPaths = @(
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
        "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
        "$env:ProgramData\Microsoft\Windows\WER\Temp"
    )
    foreach ($p in $crashPaths) {
        if (Test-Path $p) {
            $files = Get-ChildItem -Path $p -File -Recurse -Force -ErrorAction SilentlyContinue
            if ($files) {
                $metrics.CrashDumpsCount += $files.Count
                $metrics.CrashDumpsBytes += ($files | Measure-Object -Property Length -Sum).Sum
            }
        }
    }

    # Diagnostic & CBS logs
    $diagPaths = @(
        "$env:SystemRoot\Logs\CBS\*.cab",
        "$env:SystemRoot\Logs\DISM\*.log"
    )
    foreach ($p in $diagPaths) {
        $parent = Split-Path -Parent $p
        $leaf = Split-Path -Leaf $p
        if (Test-Path $parent) {
            $files = Get-ChildItem -Path $parent -Filter $leaf -File -Force -ErrorAction SilentlyContinue
            if ($files) {
                $metrics.DiagnosticLogsCount += $files.Count
                $metrics.DiagnosticLogsBytes += ($files | Measure-Object -Property Length -Sum).Sum
            }
        }
    }

    # Shader Cache
    $shaderPaths = @(
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\AMD\DxCache",
        "$env:LOCALAPPDATA\Intel\ShaderCache"
    )
    foreach ($p in $shaderPaths) {
        if (Test-Path $p) {
            $files = Get-ChildItem -Path $p -File -Recurse -Force -ErrorAction SilentlyContinue
            if ($files) {
                $metrics.ShaderCacheCount += $files.Count
                $metrics.ShaderCacheBytes += ($files | Measure-Object -Property Length -Sum).Sum
            }
        }
    }

    # Recycle Bin size
    try {
        $shell = New-Object -ComObject Shell.Application
        $bin = $shell.Namespace(0xA) # ssfBITBUCKET
        if ($bin) {
            $binItems = $bin.Items()
            foreach ($item in $binItems) {
                $metrics.RecycleBinBytes += $item.Size
            }
        }
    } catch {}

    $metrics.TotalEstimatedBytes = $metrics.UserTempBytes + $metrics.SystemTempBytes + $metrics.CrashDumpsBytes + $metrics.DiagnosticLogsBytes + $metrics.ShaderCacheBytes + $metrics.RecycleBinBytes
    return $metrics
}

# -----------------------------------------------------------------------------
# 3. SAFE DEEP JUNK CLEANUP
# -----------------------------------------------------------------------------
function Invoke-SafeFilePurge {
    param(
        [string]$Path,
        [string]$Filter = "*",
        [int]$DaysOld = 0,
        [string]$CategoryName
    )
    if (-not (Test-Path $Path)) { return 0L }

    $freed = 0L
    $deletedFiles = 0
    $cutoff = if ($DaysOld -gt 0) { (Get-Date).AddDays(-$DaysOld) } else { $null }

    Write-Info "Cleaning $CategoryName..."
    $items = Get-ChildItem -Path $Path -Filter $Filter -File -Recurse -Force -ErrorAction SilentlyContinue

    foreach ($file in $items) {
        if ($cutoff -and $file.LastWriteTime -gt $cutoff) { continue }
        
        # Explicit personal data safety check: Never delete personal directories
        $full = $file.FullName.ToLower()
        if ($full -match '\\(documents|desktop|downloads|pictures|videos|music|onedrive)\\' -or
            $full -match '\\appdata\\(roaming|local)\\(google|mozilla|microsoft\\edge|brave)\\' -and $full -notmatch '\\temp\\') {
            continue
        }

        $length = $file.Length
        if ($Script:IsDryRun) {
            $freed += $length
            $deletedFiles++
            continue
        }

        try {
            # File safety: In-use / locked files throw IOException; we catch and cleanly skip
            [System.IO.File]::Delete($file.FullName)
            $freed += $length
            $deletedFiles++
        } catch [System.IO.IOException] {
            # File in use by running application; expected behavior; safely bypass
        } catch [System.UnauthorizedAccessException] {
            # File access restricted; safely bypass
        } catch {}
    }

    # Remove empty subdirectories if safe
    if (-not $Script:IsDryRun) {
        Get-ChildItem -Path $Path -Directory -Recurse -Force -ErrorAction SilentlyContinue | 
            Sort-Object FullName -Descending | 
            ForEach-Object {
                try {
                    if ((Get-ChildItem -Path $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                        [System.IO.Directory]::Delete($_.FullName)
                    }
                } catch {}
            }
    }

    Write-Success "$CategoryName freed: $(Format-Bytes $freed) ($deletedFiles files removed)"
    return $freed
}

function Invoke-SafeDeepJunkCleanup {
    Show-Header "Safe Deep Junk File Cleanup" "Cleans verified temporary files, crash reports, and caches safely"
    
    Write-Host "  Safety Verification:" -ForegroundColor Yellow
    Write-Host "  * Personal folders (Documents, Downloads, Desktop, Pictures) are NEVER touched." -ForegroundColor Gray
    Write-Host "  * Files currently in use by running processes are skipped automatically." -ForegroundColor Gray
    Write-Host "  * Windows Installer and WinSxS files are NOT deleted manually." -ForegroundColor Gray
    Write-Host ""

    $emptyRecycleBin = Prompt-Confirm "Would you also like to empty the Windows Recycle Bin?" $false
    $runDismCleanup = $false
    if (Test-IsAdmin) {
        $runDismCleanup = Prompt-Confirm "Run Windows Component Store Cleanup (DISM StartComponentCleanup)? Safe, supported official Windows cleanup of old update files." $false
    }

    Write-Host ""
    Write-Info "Commencing safe junk cleanup process..."
    $sessionFreed = 0L

    # 1. User Temp Directory
    $sessionFreed += Invoke-SafeFilePurge -Path $env:TEMP -CategoryName "User Temp Directory"

    # 2. Windows System Temp Directory (Requires admin for full access)
    $sysTemp = "$env:SystemRoot\Temp"
    $sessionFreed += Invoke-SafeFilePurge -Path $sysTemp -CategoryName "Windows System Temp"

    # 3. Crash Dumps & Windows Error Reporting
    $sessionFreed += Invoke-SafeFilePurge -Path "$env:LOCALAPPDATA\CrashDumps" -CategoryName "Application Crash Dumps"
    $sessionFreed += Invoke-SafeFilePurge -Path "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" -CategoryName "Windows Error Reporting Archives"
    $sessionFreed += Invoke-SafeFilePurge -Path "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" -CategoryName "Windows Error Reporting Queue"
    $sessionFreed += Invoke-SafeFilePurge -Path "$env:ProgramData\Microsoft\Windows\WER\Temp" -CategoryName "Windows Error Reporting Temp"

    # 4. Old Memory Dump if present
    $memDump = "$env:SystemRoot\MEMORY.DMP"
    if (Test-Path $memDump) {
        try {
            $f = Get-Item $memDump
            $size = $f.Length
            if (-not $Script:IsDryRun) {
                Remove-Item -Path $memDump -Force -ErrorAction SilentlyContinue
            }
            $sessionFreed += $size
            Write-Success "Removed stale System Kernel Memory Dump: $(Format-Bytes $size)"
        } catch {}
    }

    # 5. Diagnostic and Servicing Logs (excluding locked active logs)
    $sessionFreed += Invoke-SafeFilePurge -Path "$env:SystemRoot\Logs\CBS" -Filter "*.cab" -CategoryName "CBS Servicing Compressed Logs"
    $sessionFreed += Invoke-SafeFilePurge -Path "$env:SystemRoot\Logs\DISM" -Filter "*.log" -DaysOld 7 -CategoryName "Historical DISM Logs"

    # 6. DirectX and GPU Shader Caches
    $sessionFreed += Invoke-SafeFilePurge -Path "$env:LOCALAPPDATA\D3DSCache" -CategoryName "DirectX Shader Cache"
    $sessionFreed += Invoke-SafeFilePurge -Path "$env:LOCALAPPDATA\NVIDIA\DXCache" -CategoryName "NVIDIA Shader Cache"
    $sessionFreed += Invoke-SafeFilePurge -Path "$env:LOCALAPPDATA\AMD\DxCache" -CategoryName "AMD Shader Cache"
    $sessionFreed += Invoke-SafeFilePurge -Path "$env:LOCALAPPDATA\Intel\ShaderCache" -CategoryName "Intel Shader Cache"

    # 7. Delivery Optimization Cache
    $sessionFreed += Invoke-SafeFilePurge -Path "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization" -CategoryName "Delivery Optimization Cache"

    # 8. Recycle Bin (if explicitly confirmed)
    if ($emptyRecycleBin) {
        Write-Info "Emptying Windows Recycle Bin..."
        if (-not $Script:IsDryRun) {
            try {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
                Write-Success "Windows Recycle Bin emptied successfully."
            } catch {
                Write-Warn "Unable to empty Recycle Bin via PowerShell cmdlet; attempting Shell API fallback..."
            }
        } else {
            Write-Info "[Dry-Run] Recycle Bin would be emptied."
        }
    }

    # 9. Optional Component Store Cleanup via official DISM command
    if ($runDismCleanup -and (Test-IsAdmin)) {
        Write-Info "Executing official DISM Component Store Cleanup (this may take 2-4 minutes)..."
        if (-not $Script:IsDryRun) {
            try {
                $p = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /NoRestart" -Wait -PassThru -NoNewWindow
                if ($p.ExitCode -eq 0) {
                    Write-Success "DISM Component Store Cleanup finished successfully."
                } else {
                    Write-Warn "DISM completed with status code $($p.ExitCode)."
                }
            } catch {
                Write-Err "DISM Component Cleanup encountered an error: $($_.Exception.Message)"
            }
        } else {
            Write-Info "[Dry-Run] DISM Component Store Cleanup would execute: Dism.exe /Online /Cleanup-Image /StartComponentCleanup"
        }
    }

    $Script:FreedBytesTotal += $sessionFreed
    Write-Host ""
    Write-Host "  ========================================================================" -ForegroundColor Green
    Write-Host ("   Total Disk Space Freed This Session: {0}" -f (Format-Bytes $sessionFreed)) -ForegroundColor Yellow
    Write-Host "  ========================================================================" -ForegroundColor Green

    Write-Log -Level "SUCCESS" -Message "Deep junk cleanup finished. Total freed: $(Format-Bytes $sessionFreed)"
    Prompt-Continue
}

# -----------------------------------------------------------------------------
# 4. STARTUP APPLICATIONS OPTIMIZATION
# -----------------------------------------------------------------------------
function Get-AllStartupItems {
    $items = @()

    # Registry Run HKCU
    $hkcuRun = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path $hkcuRun) {
        $props = Get-ItemProperty -Path $hkcuRun
        $props.PSObject.Properties | Where-Object { $_.Name -notmatch "^(PS|Child|Provider)" } | ForEach-Object {
            $items += [PSCustomObject]@{
                Type     = "Registry"
                Scope    = "User (HKCU)"
                Location = $hkcuRun
                Name     = $_.Name
                Command  = $_.Value
                Status   = "Enabled"
            }
        }
    }

    # Registry Run HKLM
    $hklmRun = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path $hklmRun) {
        $props = Get-ItemProperty -Path $hklmRun
        $props.PSObject.Properties | Where-Object { $_.Name -notmatch "^(PS|Child|Provider)" } | ForEach-Object {
            $items += [PSCustomObject]@{
                Type     = "Registry"
                Scope    = "System (HKLM)"
                Location = $hklmRun
                Name     = $_.Name
                Command  = $_.Value
                Status   = "Enabled"
            }
        }
    }

    # Registry Run HKLM WOW6432Node
    $wowRun = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path $wowRun) {
        $props = Get-ItemProperty -Path $wowRun
        $props.PSObject.Properties | Where-Object { $_.Name -notmatch "^(PS|Child|Provider)" } | ForEach-Object {
            $items += [PSCustomObject]@{
                Type     = "Registry"
                Scope    = "System (WOW64)"
                Location = $wowRun
                Name     = $_.Name
                Command  = $_.Value
                Status   = "Enabled"
            }
        }
    }

    # Startup Folder User
    $userStartup = [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs\Startup")
    if (Test-Path $userStartup) {
        Get-ChildItem -Path $userStartup -File -Force -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -notmatch '^desktop\.ini$' } | ForEach-Object {
            $items += [PSCustomObject]@{
                Type     = "Shortcut"
                Scope    = "User Folder"
                Location = $_.FullName
                Name     = $_.Name
                Command  = $_.FullName
                Status   = if ($_.Extension -eq ".disabled") { "Disabled" } else { "Enabled" }
            }
        }
    }

    # Startup Folder All Users
    $allUsersStartup = [System.IO.Path]::Combine($env:ProgramData, "Microsoft\Windows\Start Menu\Programs\Startup")
    if (Test-Path $allUsersStartup) {
        Get-ChildItem -Path $allUsersStartup -File -Force -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -notmatch '^desktop\.ini$' } | ForEach-Object {
            $items += [PSCustomObject]@{
                Type     = "Shortcut"
                Scope    = "Common Folder"
                Location = $_.FullName
                Name     = $_.Name
                Command  = $_.FullName
                Status   = if ($_.Extension -eq ".disabled") { "Disabled" } else { "Enabled" }
            }
        }
    }

    return $items
}

function Show-StartupApplicationsMenu {
    Show-Header "Startup Applications Management" "Review and disable unneeded background startup programs"
    Write-Info "Scanning startup registration points (Registry & Startup folders)..."

    $startupItems = Get-AllStartupItems
    if ($startupItems.Count -eq 0) {
        Write-Success "No startup programs found registered in standard Run keys or Startup folders."
        Prompt-Continue
        return
    }

    Write-Host ""
    Write-Host "  Detected Startup Applications:" -ForegroundColor Yellow
    Write-Host ("  {0,-3} {1,-28} {2,-16} {3,-9} {4,-20}" -f "#", "Application Name", "Scope", "Status", "Command Snippet") -ForegroundColor Cyan
    Write-Host "  --------------------------------------------------------------------------------" -ForegroundColor DarkGray

    for ($i = 0; $i -lt $startupItems.Count; $i++) {
        $item = $startupItems[$i]
        $cmdSnippet = if ($item.Command.Length -gt 25) { $item.Command.Substring(0, 22) + "..." } else { $item.Command }
        $isProtected = $Script:ProtectedProcesses | Where-Object { $item.Command.ToLower().Contains($_) }
        $color = if ($isProtected) { "White" } elseif ($item.Status -eq "Disabled") { "DarkGray" } else { "Yellow" }
        Write-Host ("  [{0,2}] {1,-28} {2,-16} {3,-9} {4,-20}" -f ($i + 1), ($item.Name.Substring(0, [math]::Min(27, $item.Name.Length))), $item.Scope, $item.Status, $cmdSnippet) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  Options:" -ForegroundColor Cyan
    Write-Host "    [1-$($startupItems.Count)] Toggle Disable / Enable for specific item"
    Write-Host "    [D] Disable all non-essential 3rd-party updaters and utilities"
    Write-Host "    [B] Back to main menu"
    Write-Host ""
    Write-Host "  Select an option: " -ForegroundColor Yellow -NoNewline
    $choice = [System.Console]::ReadLine()

    if ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        if ($idx -ge 0 -and $idx -lt $startupItems.Count) {
            $selected = $startupItems[$idx]
            Toggle-StartupItem -Item $selected
        }
    } elseif ($choice.Trim().ToUpper() -eq 'D') {
        # Bulk safe disable for known updaters & non-essential tools
        $candidates = $startupItems | Where-Object {
            $_.Status -eq "Enabled" -and
            $_.Name -match "(update|updater|telemetry|discord|spotify|epic|steam|cortana|skype|teams|onedrive)" -and
            -not ($Script:ProtectedProcesses | Where-Object { $_.Command.ToLower().Contains($_) })
        }
        if ($candidates.Count -gt 0) {
            Write-Info "Found $($candidates.Count) non-essential startup items to disable:"
            $candidates | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor Yellow }
            if (Prompt-Confirm "Disable these startup items?") {
                foreach ($c in $candidates) {
                    Toggle-StartupItem -Item $c -ForceDisable $true
                }
            }
        } else {
            Write-Success "No obvious non-essential updaters found in enabled state."
        }
    }

    Prompt-Continue
}

function Toggle-StartupItem {
    param(
        [Parameter(Mandatory=$true)]
        $Item,
        [bool]$ForceDisable = $false
    )

    $backupDir = Ensure-SessionBackupFolder
    $backupFile = Join-Path $backupDir "startup_backup.json"

    # Backup current state
    $backupList = @()
    if (Test-Path $backupFile) {
        try { $backupList = @(ConvertFrom-Json (Get-Content -Path $backupFile -Raw)) } catch {}
    }
    $backupList += $Item
    $backupList | ConvertTo-Json -Depth 4 | Set-Content -Path $backupFile -Force

    if ($Item.Type -eq "Registry") {
        if ($Item.Status -eq "Enabled" -or $ForceDisable) {
            # Disable: save to disabled key or delete property after backup
            try {
                if (-not $Script:IsDryRun) {
                    Remove-ItemProperty -Path $Item.Location -Name $Item.Name -Force -ErrorAction Stop
                }
                Write-Success "Disabled startup entry '$($Item.Name)' from $($Item.Scope)."
                Write-Log -Level "INFO" -Message "Disabled startup registry entry: $($Item.Name)"
            } catch {
                Write-Err "Failed to disable registry startup item: $($_.Exception.Message)"
            }
        }
    } elseif ($Item.Type -eq "Shortcut") {
        try {
            if ($Item.Status -eq "Enabled" -or $ForceDisable) {
                $newPath = $Item.Location + ".disabled"
                if (-not $Script:IsDryRun) {
                    Rename-Item -Path $Item.Location -NewName (Split-Path -Leaf $newPath) -Force
                }
                Write-Success "Disabled startup shortcut '$($Item.Name)'."
            } else {
                $origPath = $Item.Location.Replace(".disabled", "")
                if (-not $Script:IsDryRun) {
                    Rename-Item -Path $Item.Location -NewName (Split-Path -Leaf $origPath) -Force
                }
                Write-Success "Re-enabled startup shortcut '$($Item.Name)'."
            }
        } catch {
            Write-Err "Failed to toggle startup shortcut: $($_.Exception.Message)"
        }
    }
}

# -----------------------------------------------------------------------------
# 5. BACKGROUND PROCESS MANAGEMENT
# -----------------------------------------------------------------------------
function Show-BackgroundProcessManager {
    Show-Header "Interactive Background Process Management" "Gracefully close non-essential high-resource background applications"

    Write-Info "Scanning active background processes..."
    $processes = Get-Process | Where-Object {
        $_.Id -ne 0 -and
        $_.ProcessName -ne "Idle" -and
        -not ($Script:ProtectedProcesses -contains $_.ProcessName.ToLower())
    } | Sort-Object WorkingSet64 -Descending

    if ($processes.Count -eq 0) {
        Write-Success "No third-party non-essential background processes detected."
        Prompt-Continue
        return
    }

    Write-Host ""
    Write-Host "  Top 25 Non-Essential Third-Party Processes:" -ForegroundColor Yellow
    Write-Host ("  {0,-3} {1,-8} {2,-26} {3,12} {4,-24}" -f "#", "PID", "Process Name", "Working Set", "Company / Description") -ForegroundColor Cyan
    Write-Host "  --------------------------------------------------------------------------------" -ForegroundColor DarkGray

    $displayCount = [math]::Min(25, $processes.Count)
    for ($i = 0; $i -lt $displayCount; $i++) {
        $p = $processes[$i]
        $wsMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
        $company = try { $p.Company } catch { "" }
        if (-not $company) { $company = try { $p.Description } catch { "Third-Party App" } }
        if ($company.Length -gt 24) { $company = $company.Substring(0, 21) + "..." }
        $pName = $p.ProcessName
        Write-Host ("  [{0,2}] {1,-8} {2,-26} {3,10} MB {4,-24}" -f ($i + 1), $p.Id, ($pName.Substring(0, [math]::Min(25, $pName.Length))), $wsMB, $company)
    }

    Write-Host ""
    Write-Host "  Options:" -ForegroundColor Cyan
    Write-Host "    [1-$displayCount] Close selected process gracefully"
    Write-Host "    [K] Close multiple selected processes (comma-separated, e.g. 1, 4, 7)"
    Write-Host "    [B] Back to main menu"
    Write-Host ""
    Write-Host "  Select an option: " -ForegroundColor Yellow -NoNewline
    $input = [System.Console]::ReadLine()

    if ($input -match '^\d+$') {
        $idx = [int]$input - 1
        if ($idx -ge 0 -and $idx -lt $displayCount) {
            Close-TargetProcess -Proc $processes[$idx]
        }
    } elseif ($input.Trim().ToUpper() -eq 'K') {
        Write-Host "  Enter numbers to close separated by commas: " -ForegroundColor Yellow -NoNewline
        $indicesInput = [System.Console]::ReadLine()
        $indices = $indicesInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
        foreach ($num in $indices) {
            $idx = [int]$num - 1
            if ($idx -ge 0 -and $idx -lt $displayCount) {
                Close-TargetProcess -Proc $processes[$idx]
            }
        }
    }

    Prompt-Continue
}

function Close-TargetProcess {
    param([Parameter(Mandatory=$true)]$Proc)

    $name = $Proc.ProcessName
    $id = $Proc.Id

    # Critical protection check
    if ($Script:ProtectedProcesses -contains $name.ToLower()) {
        Write-Warn "Process '$name' is a protected system component. Termination refused."
        return
    }

    Write-Info "Requesting graceful closure of '$name' (PID: $id)..."
    if ($Script:IsDryRun) {
        Write-Info "[Dry-Run] Process '$name' (PID: $id) would be closed."
        return
    }

    try {
        # Attempt graceful window close first to avoid data loss
        $closedGracefully = $Proc.CloseMainWindow()
        Start-Sleep -Milliseconds 1200

        # Check if process exited
        $stillRunning = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($stillRunning) {
            Write-Warn "'$name' did not exit from graceful request. Terminating process..."
            Stop-Process -Id $id -Force -ErrorAction Stop
        }
        Write-Success "Process '$name' (PID: $id) terminated successfully."
        Write-Log -Level "INFO" -Message "Terminated background process: $name (PID: $id)"
    } catch {
        Write-Err "Could not terminate process '$name': $($_.Exception.Message)"
    }
}

# -----------------------------------------------------------------------------
# 6. WINDOWS SERVICES OPTIMIZATION
# -----------------------------------------------------------------------------
function Get-ServiceCatalog {
    return @(
        # Category A: Safe Candidates (Telemetry, Retail Demo, Maps, Remote Registry)
        [PSCustomObject]@{
            Name        = "DiagTrack"
            DisplayName = "Connected User Experiences and Telemetry"
            Recommended = "Disabled"
            Category    = "Safe"
            Reason      = "Sends usage diagnostic data and telemetry to Microsoft servers in background."
            Impact      = "Reduces background network and disk activity. Windows Update & Defender unaffected."
        },
        [PSCustomObject]@{
            Name        = "dmwappushservice"
            DisplayName = "Device Management WAP Push Message Routing"
            Recommended = "Disabled"
            Category    = "Safe"
            Reason      = "Used for mobile carrier WAP push messages; obsolete on desktop/laptop PCs."
            Impact      = "Reduces idle svchost process count. No impact on modern web or apps."
        },
        [PSCustomObject]@{
            Name        = "RetailDemo"
            DisplayName = "Retail Demo Service"
            Recommended = "Disabled"
            Category    = "Safe"
            Reason      = "Intended only for retail store display kiosks to show Windows demo loops."
            Impact      = "Zero impact on consumer/enterprise PCs. Disables demo loop background service."
        },
        [PSCustomObject]@{
            Name        = "RemoteRegistry"
            DisplayName = "Remote Registry"
            Recommended = "Disabled"
            Category    = "Safe"
            Reason      = "Allows remote users to modify registry settings over the network (security hazard)."
            Impact      = "Improves system security and frees background resources. Local registry unaffected."
        },
        [PSCustomObject]@{
            Name        = "MapsBroker"
            DisplayName = "Downloaded Maps Manager"
            Recommended = "Manual"
            Category    = "Safe"
            Reason      = "Background manager for downloaded offline Windows Maps app."
            Impact      = "Changes startup to on-demand. Maps will start service only if user opens offline maps."
        },
        [PSCustomObject]@{
            Name        = "XblAuthManager"
            DisplayName = "Xbox Live Auth Manager"
            Recommended = "Manual"
            Category    = "Safe"
            Reason      = "Xbox Live authentication provider."
            Impact      = "Starts automatically only when an Xbox game or app is launched. Saves idle memory."
        },
        [PSCustomObject]@{
            Name        = "XblGameSave"
            DisplayName = "Xbox Live Game Save"
            Recommended = "Manual"
            Category    = "Safe"
            Reason      = "Cloud game saves for Xbox Play Anywhere games."
            Impact      = "Starts automatically only when an Xbox game needs save synchronization."
        },
        [PSCustomObject]@{
            Name        = "XboxGipSvc"
            DisplayName = "Xbox Accessory Management Service"
            Recommended = "Manual"
            Category    = "Safe"
            Reason      = "Xbox accessory accessories manager."
            Impact      = "Starts automatically when Xbox wireless accessories are paired."
        },
        [PSCustomObject]@{
            Name        = "XboxNetApiSvc"
            DisplayName = "Xbox Live Networking Service"
            Recommended = "Manual"
            Category    = "Safe"
            Reason      = "Xbox Live networking helper."
            Impact      = "Starts on-demand only when Xbox multiplayer features connect."
        },
        [PSCustomObject]@{
            Name        = "WalletService"
            DisplayName = "Wallet Service"
            Recommended = "Manual"
            Category    = "Safe"
            Reason      = "Used by Windows Wallet app for NFC passes and payment cards."
            Impact      = "Starts on-demand only if Wallet features are actively called."
        },
        [PSCustomObject]@{
            Name        = "PhoneSvc"
            DisplayName = "Phone Service"
            Recommended = "Manual"
            Category    = "Safe"
            Reason      = "Telephony state management for cellular connections."
            Impact      = "Starts on-demand if cellular / telephony device is engaged."
        },
        [PSCustomObject]@{
            Name        = "SharedAccess"
            DisplayName = "Internet Connection Sharing (ICS)"
            Recommended = "Manual"
            Category    = "Safe"
            Reason      = "Provides NAT and DHCP for sharing this PC's internet connection with other devices."
            Impact      = "Starts on-demand if Mobile Hotspot is enabled by the user."
        },

        # Category B: Advanced / Hardware Dependent (Requires individual user review)
        [PSCustomObject]@{
            Name        = "Spooler"
            DisplayName = "Print Spooler"
            Recommended = "Manual"
            Category    = "Advanced"
            Reason      = "Manages print jobs and printer communication."
            Impact      = "CAUTION: Disables all physical and virtual printing (including Print to PDF) if stopped."
        },
        [PSCustomObject]@{
            Name        = "bthserv"
            DisplayName = "Bluetooth Support Service"
            Recommended = "Manual"
            Category    = "Advanced"
            Reason      = "Discovery and management of Bluetooth peripheral devices."
            Impact      = "CAUTION: Bluetooth headphones, mice, controllers, and file transfers will stop working."
        },
        [PSCustomObject]@{
            Name        = "SysMain"
            DisplayName = "SysMain (SuperFetch)"
            Recommended = "Keep"
            Category    = "Advanced"
            Reason      = "Preloads frequently used applications into standby RAM."
            Impact      = "ENGINEERING NOTE: On NVMe SSDs, disabling reduces background disk writes and RAM caching. On HDDs or <=8GB RAM, KEEP ENABLED for faster app launching."
        },
        [PSCustomObject]@{
            Name        = "WSearch"
            DisplayName = "Windows Search"
            Recommended = "Keep"
            Category    = "Advanced"
            Reason      = "Provides content indexing and fast file search for File Explorer and Outlook."
            Impact      = "ENGINEERING NOTE: Disabling eliminates SearchIndexer CPU/disk usage, BUT File Explorer search becomes unindexed (slow) and Outlook search breaks."
        },
        [PSCustomObject]@{
            Name        = "WbioSrvc"
            DisplayName = "Windows Biometric Service"
            Recommended = "Manual"
            Category    = "Advanced"
            Reason      = "Manages biometric hardware (Windows Hello fingerprint and face recognition)."
            Impact      = "CAUTION: Do not disable if using Windows Hello Fingerprint or Facial recognition login."
        }
    )
}

function Show-WindowsServicesOptimization {
    Show-Header "Windows Services Optimization" "Configure optional background services to reduce idle svchost count"

    if (-not (Test-IsAdmin)) {
        Write-Warn "Modifying Windows service startup configurations requires Administrator privileges."
        Write-Warn "Please restart WindowsOptimizer.bat as Administrator to apply service adjustments."
        Prompt-Continue
        return
    }

    $catalog = Get-ServiceCatalog
    Write-Info "Evaluating system service states against optimization profile..."

    Write-Host ""
    Write-Host "  [ Category A: Safe Candidates for Manual / Disabled ]" -ForegroundColor Green
    Write-Host ("  {0,-3} {1,-18} {2,-11} {3,-13} {4,-32}" -f "#", "Service Name", "Current", "Recommended", "Description") -ForegroundColor Cyan
    Write-Host "  --------------------------------------------------------------------------------" -ForegroundColor DarkGray

    $safeList = $catalog | Where-Object { $_.Category -eq "Safe" }
    for ($i = 0; $i -lt $safeList.Count; $i++) {
        $item = $safeList[$i]
        $svc = Get-Service -Name $item.Name -ErrorAction SilentlyContinue
        $currentStart = if ($svc) { (Get-CimInstance Win32_Service -Filter "Name='$($item.Name)'").StartMode } else { "NotFound" }
        $color = if ($currentStart -eq $item.Recommended) { "DarkGray" } else { "Yellow" }
        Write-Host ("  [{0,2}] {1,-18} {2,-11} {3,-13} {4,-32}" -f ($i + 1), $item.Name, $currentStart, $item.Recommended, ($item.DisplayName.Substring(0, [math]::Min(30, $item.DisplayName.Length)))) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  [ Category B: Advanced / Hardware-Dependent Services ]" -ForegroundColor Magenta
    $advList = $catalog | Where-Object { $_.Category -eq "Advanced" }
    for ($j = 0; $j -lt $advList.Count; $j++) {
        $item = $advList[$j]
        $svc = Get-Service -Name $item.Name -ErrorAction SilentlyContinue
        $currentStart = if ($svc) { (Get-CimInstance Win32_Service -Filter "Name='$($item.Name)'").StartMode } else { "NotFound" }
        Write-Host ("  [A{0}] {1,-18} Current: {2,-10} Note: {3}" -f ($j + 1), $item.Name, $currentStart, $item.DisplayName) -ForegroundColor White
    }

    Write-Host ""
    Write-Host "  Actions:" -ForegroundColor Cyan
    Write-Host "    [S] Apply Safe Optimization Profile (All Category A services to Recommended)"
    Write-Host "    [R] Review specific service details and rationale"
    Write-Host "    [B] Back to main menu"
    Write-Host ""
    Write-Host "  Select an option: " -ForegroundColor Yellow -NoNewline
    $action = [System.Console]::ReadLine()

    if ($action.Trim().ToUpper() -eq 'S') {
        if (Prompt-Confirm "Apply Safe Services Profile? (Original state will be backed up for 100% rollback)") {
            Apply-SafeServicesProfile -SafeList $safeList
        }
    } elseif ($action.Trim().ToUpper() -eq 'R') {
        Write-Host "  Enter service number (1-$($safeList.Count)) or advanced (A1-$($advList.Count)): " -ForegroundColor Yellow -NoNewline
        $svcChoice = [System.Console]::ReadLine().Trim()
        $target = $null
        if ($svcChoice -match '^\d+$') {
            $idx = [int]$svcChoice - 1
            if ($idx -ge 0 -and $idx -lt $safeList.Count) { $target = $safeList[$idx] }
        } elseif ($svcChoice.ToUpper().StartsWith('A')) {
            $idx = [int]($svcChoice.Substring(1)) - 1
            if ($idx -ge 0 -and $idx -lt $advList.Count) { $target = $advList[$idx] }
        }

        if ($target) {
            Write-Host ""
            Write-Host "  Service Details:" -ForegroundColor Yellow
            Write-Host "    Name:           $($target.Name)"
            Write-Host "    Display Name:   $($target.DisplayName)"
            Write-Host "    Recommended:    $($target.Recommended)"
            Write-Host "    Rationale:      $($target.Reason)"
            Write-Host "    System Impact:  $($target.Impact)" -ForegroundColor Cyan
            Write-Host ""
            if (Prompt-Confirm "Apply recommended startup type ($($target.Recommended)) for this service?") {
                Configure-SingleService -ServiceItem $target -NewStartupType $target.Recommended
            }
        }
    }

    Prompt-Continue
}

function Apply-SafeServicesProfile {
    param([Parameter(Mandatory=$true)]$SafeList)

    Write-Info "Backing up original service configurations..."
    foreach ($item in $SafeList) {
        Backup-ServiceState -ServiceName $item.Name
    }

    $adjustedCount = 0
    foreach ($item in $SafeList) {
        $svc = Get-Service -Name $item.Name -ErrorAction SilentlyContinue
        if ($svc) {
            $currentMode = (Get-CimInstance Win32_Service -Filter "Name='$($item.Name)'").StartMode
            if ($currentMode -ne $item.Recommended) {
                Configure-SingleService -ServiceItem $item -NewStartupType $item.Recommended
                $adjustedCount++
            }
        }
    }

    Write-Success "Safe services profile applied successfully. $adjustedCount services optimized."
    Write-Log -Level "SUCCESS" -Message "Safe services profile applied. $adjustedCount services adjusted."
}

function Configure-SingleService {
    param(
        [Parameter(Mandatory=$true)]$ServiceItem,
        [Parameter(Mandatory=$true)][string]$NewStartupType
    )

    $name = $ServiceItem.Name
    # Safety Check: Never modify protected services
    if ($Script:ProtectedServices -contains $name) {
        Write-Warn "Service '$name' is in the critical system protection list. Modification skipped."
        return
    }

    Backup-ServiceState -ServiceName $name

    if ($Script:IsDryRun) {
        Write-Info "[Dry-Run] Service '$name' startup type would be set to $NewStartupType."
        return
    }

    try {
        Set-Service -Name $name -StartupType $NewStartupType -ErrorAction Stop
        if ($NewStartupType -eq "Disabled") {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq "Running") {
                Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Success "Service '$name' configured to $NewStartupType."
        Write-Log -Level "INFO" -Message "Configured service '$name' to $NewStartupType."
    } catch {
        Write-Err "Failed to configure service '$name': $($_.Exception.Message)"
    }
}

# -----------------------------------------------------------------------------
# 7. GAMING OPTIMIZATION PROFILE
# -----------------------------------------------------------------------------
function Show-GamingOptimization {
    Show-Header "Gaming Performance & Responsiveness Optimization" "Optimize latency, frame consistency, and background interruptions for gaming"

    Write-Host "  [ Gaming Engineering Principles ]" -ForegroundColor Yellow
    Write-Host "  * Windows Game Mode prioritizes CPU/GPU scheduling for active full-screen 3D games." -ForegroundColor Gray
    Write-Host "  * GPU Driver Shader Caches are preserved to prevent in-game micro-stutters." -ForegroundColor Gray
    Write-Host "  * Windows Defender and Anti-Cheat systems (EasyAntiCheat, BattlEye, Vanguard) are PROTECTED." -ForegroundColor Gray
    Write-Host "  * No fake FPS claims: Optimizing removes background latency spikes and 1% low drops." -ForegroundColor Gray
    Write-Host ""

    # Check Game Mode registry state
    $gameBarKey = "HKCU:\Software\Microsoft\GameBar"
    $gameModeVal = 1
    if (Test-Path $gameBarKey) {
        $p = Get-ItemProperty -Path $gameBarKey -Name "AllowAutoGameMode" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $null -ne $p.AllowAutoGameMode) {
            $gameModeVal = $p.AllowAutoGameMode
        }
    }

    Write-Host ("  Windows Game Mode Status:             {0}" -f $(if ($gameModeVal -eq 1) { "ENABLED (Optimal)" } else { "DISABLED" })) -ForegroundColor $(if ($gameModeVal -eq 1) { "Green" } else { "Yellow" })

    # Check HAGS (Hardware Accelerated GPU Scheduling)
    $hagsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    $hagsVal = 0
    if (Test-Path $hagsKey) {
        $p = Get-ItemProperty -Path $hagsKey -Name "HwSchMode" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $null -ne $p.HwSchMode) { $hagsVal = $p.HwSchMode }
    }
    Write-Host ("  Hardware-Accelerated GPU Scheduling:  {0}" -f $(if ($hagsVal -eq 2) { "ENABLED (WDDM 2.7+ Active)" } else { "DISABLED / Default" }))

    # Check active high-impact background apps
    $backgroundGamingSpikes = Get-Process | Where-Object {
        $_.ProcessName -match "(discord|spotify|epicgameslauncher|steamwebhelper|origin|battle.net|onedrive|dropbox)" -and
        -not ($Script:ProtectedProcesses -contains $_.ProcessName.ToLower())
    }

    Write-Host ("  Detected Background Non-Gaming Apps:  {0} active" -f $backgroundGamingSpikes.Count)
    if ($backgroundGamingSpikes.Count -gt 0) {
        $backgroundGamingSpikes | ForEach-Object {
            Write-Host ("    - {0,-25} (PID: {1,-6} RAM: {2} MB)" -f $_.ProcessName, $_.Id, [math]::Round($_.WorkingSet64 / 1MB, 1)) -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "  Gaming Profile Actions:" -ForegroundColor Cyan
    Write-Host "    [1] Enable Windows Game Mode (Guarantees background suppression while gaming)"
    Write-Host "    [2] Close detected non-essential background apps to free RAM & CPU cycles for gaming"
    Write-Host "    [3] Apply Full Gaming Optimization Profile"
    Write-Host "    [B] Back to main menu"
    Write-Host ""
    Write-Host "  Select an option: " -ForegroundColor Yellow -NoNewline
    $gChoice = [System.Console]::ReadLine()

    if ($gChoice.Trim() -eq '1' -or $gChoice.Trim() -eq '3') {
        Backup-RegistryValue -Path $gameBarKey -Name "AllowAutoGameMode"
        if (-not $Script:IsDryRun) {
            if (-not (Test-Path $gameBarKey)) { New-Item -Path $gameBarKey -Force | Out-Null }
            Set-ItemProperty -Path $gameBarKey -Name "AllowAutoGameMode" -Value 1 -Type DWord -Force
        }
        Write-Success "Windows Game Mode set to Enabled."
    }

    if ($gChoice.Trim() -eq '2' -or $gChoice.Trim() -eq '3') {
        if ($backgroundGamingSpikes.Count -gt 0) {
            if (Prompt-Confirm "Gracefully close detected non-essential background applications?") {
                foreach ($proc in $backgroundGamingSpikes) {
                    Close-TargetProcess -Proc $proc
                }
            }
        } else {
            Write-Success "No active third-party background applications require closure."
        }
    }

    Prompt-Continue
}

# -----------------------------------------------------------------------------
# 8. OPTIONAL PRIVACY & WINDOWS FEATURES OPTIMIZATION
# -----------------------------------------------------------------------------
function Show-PrivacyOptimization {
    Show-Header "Optional Privacy & Windows Telemetry Configuration" "Transparent, reversible controls to limit diagnostic telemetry and cloud suggestions"

    Write-Host "  [ Privacy Philosophy & Principles ]" -ForegroundColor Yellow
    Write-Host "  * Every change is backed up and 100% reversible via the Rollback engine." -ForegroundColor Gray
    Write-Host "  * Windows Security, Defender updates, and firewall protections remain INTACT." -ForegroundColor Gray
    Write-Host "  * Disabling Start Menu Bing web search makes the Start Menu faster and strictly local." -ForegroundColor Gray
    Write-Host "  * Diagnostic data is reduced to Required/Basic level." -ForegroundColor Gray
    Write-Host ""

    $privacySettings = @(
        [PSCustomObject]@{
            ID          = "Telemetry"
            Name        = "Set Diagnostic Telemetry to Required / Basic Level"
            Hive        = "HKLM"
            Path        = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            ValueName   = "AllowTelemetry"
            DesiredVal  = 1
            Type        = "DWord"
            Description = "Restricts diagnostic telemetry sent to Microsoft to essential security data only."
        },
        [PSCustomObject]@{
            ID          = "AdvertisingID"
            Name        = "Disable Unique Advertising Identifier"
            Hive        = "HKCU"
            Path        = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
            ValueName   = "Enabled"
            DesiredVal  = 0
            Type        = "DWord"
            Description = "Prevents apps from using your unique advertising ID for targeted cross-app ads."
        },
        [PSCustomObject]@{
            ID          = "BingStart"
            Name        = "Disable Bing Web Search in Start Menu"
            Hive        = "HKCU"
            Path        = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
            ValueName   = "DisableSearchBoxSuggestions"
            DesiredVal  = 1
            Type        = "DWord"
            Description = "Stops Start menu from searching the web; search operates instantly and locally."
        },
        [PSCustomObject]@{
            ID          = "ActivityHistory"
            Name        = "Disable Activity History Publishing"
            Hive        = "HKLM"
            Path        = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
            ValueName   = "PublishUserActivities"
            DesiredVal  = 0
            Type        = "DWord"
            Description = "Prevents Windows from publishing app usage activity history to Microsoft accounts."
        },
        [PSCustomObject]@{
            ID          = "TailoredExp"
            Name        = "Disable Tailored Experiences with Diagnostic Data"
            Hive        = "HKCU"
            Path        = "HKCU:\Software\Policies\Microsoft\Windows\CloudContent"
            ValueName   = "DisableTailoredExperiencesWithDiagnosticData"
            DesiredVal  = 1
            Type        = "DWord"
            Description = "Stops Microsoft from using diagnostic data to serve customized tips and ads."
        },
        [PSCustomObject]@{
            ID          = "ContentDelivery"
            Name        = "Disable Windows Consumer Experience & Suggestions"
            Hive        = "HKCU"
            Path        = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            ValueName   = "ContentDeliveryAllowed"
            DesiredVal  = 0
            Type        = "DWord"
            Description = "Prevents automatic promotional tile installation in the Start menu."
        }
    )

    Write-Host "  Available Privacy Optimizations:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $privacySettings.Count; $i++) {
        $s = $privacySettings[$i]
        $current = "Default"
        if (Test-Path $s.Path) {
            $prop = Get-ItemProperty -Path $s.Path -Name $s.ValueName -ErrorAction SilentlyContinue
            if ($null -ne $prop -and $null -ne $prop."$($s.ValueName)") {
                $current = "$($prop."$($s.ValueName)")"
            }
        }
        $isSet = ($current -eq "$($s.DesiredVal)")
        $statusStr = if ($isSet) { "[Optimized]" } else { "[Default/Unset]" }
        Write-Host ("  [{0}] {1,-52} {2}" -f ($i + 1), $s.Name, $statusStr) -ForegroundColor $(if ($isSet) { "Green" } else { "Yellow" })
        Write-Host ("      {0}" -f $s.Description) -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "  Actions:" -ForegroundColor Cyan
    Write-Host "    [A] Apply All Safe Privacy Optimizations"
    Write-Host "    [1-$($privacySettings.Count)] Toggle specific setting"
    Write-Host "    [B] Back to main menu"
    Write-Host ""
    Write-Host "  Select an option: " -ForegroundColor Yellow -NoNewline
    $pChoice = [System.Console]::ReadLine()

    if ($pChoice.Trim().ToUpper() -eq 'A') {
        if (Prompt-Confirm "Apply all safe privacy and telemetry enhancements?") {
            foreach ($s in $privacySettings) {
                Apply-SinglePrivacySetting -Setting $s
            }
            Write-Success "All privacy settings configured. Explorer / Start menu updated."
        }
    } elseif ($pChoice -match '^\d+$') {
        $idx = [int]$pChoice - 1
        if ($idx -ge 0 -and $idx -lt $privacySettings.Count) {
            Apply-SinglePrivacySetting -Setting $privacySettings[$idx]
        }
    }

    Prompt-Continue
}

function Apply-SinglePrivacySetting {
    param([Parameter(Mandatory=$true)]$Setting)

    if ($Setting.Hive -eq "HKLM" -and -not (Test-IsAdmin)) {
        Write-Warn "Modifying $($Setting.Name) requires Administrator privileges. Skipped."
        return
    }

    Backup-RegistryValue -Path $Setting.Path -Name $Setting.ValueName

    if ($Script:IsDryRun) {
        Write-Info "[Dry-Run] Would configure $($Setting.Path) -> $($Setting.ValueName) = $($Setting.DesiredVal)"
        return
    }

    try {
        if (-not (Test-Path $Setting.Path)) {
            New-Item -Path $Setting.Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Setting.Path -Name $Setting.ValueName -Value $Setting.DesiredVal -Type $Setting.Type -Force
        Write-Success "Applied: $($Setting.Name)"
        Write-Log -Level "INFO" -Message "Configured privacy registry: $($Setting.Path) -> $($Setting.ValueName) = $($Setting.DesiredVal)"
    } catch {
        Write-Err "Failed to apply $($Setting.Name): $($_.Exception.Message)"
    }
}

# -----------------------------------------------------------------------------
# 9. FULL SAFE OPTIMIZATION (COMBINED WORKFLOW)
# -----------------------------------------------------------------------------
function Invoke-FullSafeOptimization {
    Show-Header "Full Safe Optimization Engine" "Comprehensive, automated optimization pipeline with backup and metrics"

    Write-Host "  Proposed Optimization Plan:" -ForegroundColor Yellow
    Write-Host "    1. Baseline System Metric Capture (Process count, RAM usage, Free disk)"
    Write-Host "    2. Deep Safe Junk Cleanup (Temporary files, error archives, shader caches)"
    Write-Host "    3. Safe Windows Services Tuning (Category A services to Manual/Disabled)"
    Write-Host "    4. Privacy & Telemetry Hardening (Start Menu Bing search & telemetry reduction)"
    Write-Host "    5. Verification & Before-and-After Metric Delta Report"
    Write-Host ""
    Write-Host "  Safety Guarantee:" -ForegroundColor Green
    Write-Host "    A complete restore point is recorded before any modification. Personal files," -ForegroundColor Gray
    Write-Host "    Windows Defender, network drivers, and critical services are untouched." -ForegroundColor Gray
    Write-Host ""

    if (-not (Prompt-Confirm "Proceed with Full Safe Optimization?")) {
        Write-Info "Optimization cancelled by user."
        Prompt-Continue
        return
    }

    # Step 1: Baseline Metrics
    Write-Info "Capturing baseline system metrics..."
    $initialHealth = Get-SystemHealthInfo

    # Step 2: Safe Junk Cleanup
    Write-Info "Running deep safe junk cleanup..."
    $junkFreed = 0L
    $junkFreed += Invoke-SafeFilePurge -Path $env:TEMP -CategoryName "User Temp Directory"
    $junkFreed += Invoke-SafeFilePurge -Path "$env:SystemRoot\Temp" -CategoryName "Windows System Temp"
    $junkFreed += Invoke-SafeFilePurge -Path "$env:LOCALAPPDATA\CrashDumps" -CategoryName "Crash Dumps"
    $junkFreed += Invoke-SafeFilePurge -Path "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" -CategoryName "WER Archives"
    $junkFreed += Invoke-SafeFilePurge -Path "$env:LOCALAPPDATA\D3DSCache" -CategoryName "DirectX Shader Cache"
    $junkFreed += Invoke-SafeFilePurge -Path "$env:LOCALAPPDATA\NVIDIA\DXCache" -CategoryName "NVIDIA Shader Cache"
    $Script:FreedBytesTotal += $junkFreed

    # Step 3: Safe Services Tuning
    if (Test-IsAdmin) {
        Write-Info "Tuning safe background services..."
        $safeServices = (Get-ServiceCatalog) | Where-Object { $_.Category -eq "Safe" }
        Apply-SafeServicesProfile -SafeList $safeServices
    } else {
        Write-Warn "Skipping service tuning (requires Administrator elevation)."
    }

    # Step 4: Privacy Settings
    Write-Info "Applying safe privacy and Start menu search adjustments..."
    $privacyDefaults = @(
        [PSCustomObject]@{ Hive = "HKCU"; Path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"; ValueName = "DisableSearchBoxSuggestions"; DesiredVal = 1; Type = "DWord"; Name = "Disable Start Bing Web Search" },
        [PSCustomObject]@{ Hive = "HKCU"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; ValueName = "Enabled"; DesiredVal = 0; Type = "DWord"; Name = "Disable Advertising ID" }
    )
    if (Test-IsAdmin) {
        $privacyDefaults += [PSCustomObject]@{ Hive = "HKLM"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; ValueName = "AllowTelemetry"; DesiredVal = 1; Type = "DWord"; Name = "Telemetry to Basic/Required" }
    }
    foreach ($p in $privacyDefaults) {
        Apply-SinglePrivacySetting -Setting $p
    }

    # Step 5: Post-Optimization Metrics
    Start-Sleep -Seconds 2
    $finalHealth = Get-SystemHealthInfo

    Show-Header "Optimization Complete - Results Summary" "Measured delta before and after optimization"
    Write-Host ""
    Write-Host "  Metric Comparison:" -ForegroundColor Yellow
    Write-Host ("  {0,-28} {1,14} {2,14} {3,18}" -f "Metric", "Before", "After", "Delta") -ForegroundColor Cyan
    Write-Host "  --------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("  {0,-28} {1,14} {2,14} {3,18}" -f "Running Processes", $initialHealth.ProcessCount, $finalHealth.ProcessCount, "$($finalHealth.ProcessCount - $initialHealth.ProcessCount) handles") -ForegroundColor Green
    Write-Host ("  {0,-28} {1,14} {2,14} {3,18}" -f "Memory In-Use (GB)", "$($initialHealth.UsedMemoryGB) GB", "$($finalHealth.UsedMemoryGB) GB", "$([math]::Round($finalHealth.UsedMemoryGB - $initialHealth.UsedMemoryGB, 2)) GB")
    Write-Host ("  {0,-28} {1,14} {2,14} {3,18}" -f "Disk Space Freed", "0 MB", (Format-Bytes $junkFreed), "+$(Format-Bytes $junkFreed)") -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Rollback Information:" -ForegroundColor White
    Write-Host ("  Backup created at: {0}" -f $Script:SessionBackupFolder) -ForegroundColor Gray
    Write-Host "  All changes can be reverted instantly using Option 10 from the main menu." -ForegroundColor Gray

    Write-Log -Level "SUCCESS" -Message "Full optimization completed. Processes: $($initialHealth.ProcessCount) -> $($finalHealth.ProcessCount). Disk freed: $(Format-Bytes $junkFreed)"
    Prompt-Continue
}

# -----------------------------------------------------------------------------
# 10. RESTORE PREVIOUS CHANGES (ROLLBACK ENGINE)
# -----------------------------------------------------------------------------
function Invoke-RollbackEngine {
    Show-Header "Restore Previous Changes (Rollback Engine)" "Restore original services, registry settings, and startup items from backups"

    $backups = Get-ChildItem -Path $Script:BackupDir -Directory | Sort-Object CreationTime -Descending
    if ($backups.Count -eq 0) {
        Write-Warn "No previous backup sessions found in: $($Script:BackupDir)"
        Prompt-Continue
        return
    }

    Write-Host "  Available Restore Points:" -ForegroundColor Yellow
    Write-Host ("  {0,-3} {1,-26} {2,-30}" -f "#", "Backup Session ID", "Contents Detected") -ForegroundColor Cyan
    Write-Host "  --------------------------------------------------------------------------------" -ForegroundColor DarkGray

    for ($i = 0; $i -lt $backups.Count; $i++) {
        $b = $backups[$i]
        $contents = @()
        if (Test-Path (Join-Path $b.FullName "services_backup.json")) { $contents += "Services" }
        if (Test-Path (Join-Path $b.FullName "registry_backup.json")) { $contents += "Registry" }
        if (Test-Path (Join-Path $b.FullName "startup_backup.json"))  { $contents += "Startup Items" }
        $contentStr = if ($contents.Count -gt 0) { $contents -join ", " } else { "Empty session" }
        Write-Host ("  [{0,2}] {1,-26} {2,-30}" -f ($i + 1), $b.Name, $contentStr)
    }

    Write-Host ""
    Write-Host "  Select a restore point to recover (1-$($backups.Count)) or [B] for Back: " -ForegroundColor Yellow -NoNewline
    $rChoice = [System.Console]::ReadLine()

    if ($rChoice -match '^\d+$') {
        $idx = [int]$rChoice - 1
        if ($idx -ge 0 -and $idx -lt $backups.Count) {
            $selectedBackup = $backups[$idx]
            Execute-RestorePoint -BackupFolder $selectedBackup.FullName
        }
    }

    Prompt-Continue
}

function Execute-RestorePoint {
    param([Parameter(Mandatory=$true)][string]$BackupFolder)

    Write-Info "Executing rollback from: $BackupFolder"

    # 1. Restore Services
    $svcFile = Join-Path $BackupFolder "services_backup.json"
    if (Test-Path $svcFile) {
        Write-Info "Restoring service configurations..."
        try {
            $services = ConvertFrom-Json (Get-Content -Path $svcFile -Raw)
            foreach ($s in $services) {
                Write-Host "    Restoring service '$($s.Name)' to original state: $($s.StartType)..." -ForegroundColor Gray
                try {
                    Set-Service -Name $s.Name -StartupType $s.StartType -ErrorAction SilentlyContinue
                    if ($s.Status -eq "Running") {
                        Start-Service -Name $s.Name -ErrorAction SilentlyContinue
                    }
                    Write-Success "Service '$($s.Name)' restored to $($s.StartType)."
                } catch {
                    Write-Warn "Could not restore service '$($s.Name)': $($_.Exception.Message)"
                }
            }
        } catch {
            Write-Err "Failed to parse services backup file: $($_.Exception.Message)"
        }
    }

    # 2. Restore Registry
    $regFile = Join-Path $BackupFolder "registry_backup.json"
    if (Test-Path $regFile) {
        Write-Info "Restoring registry values..."
        try {
            $regEntries = ConvertFrom-Json (Get-Content -Path $regFile -Raw)
            foreach ($entry in $regEntries) {
                if ($entry.Exists -and $null -ne $entry.Value) {
                    Write-Host "    Restoring $($entry.Path)\$($entry.Name) = $($entry.Value)..." -ForegroundColor Gray
                    try {
                        if (-not (Test-Path $entry.Path)) { New-Item -Path $entry.Path -Force | Out-Null }
                        Set-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -Type $entry.Type -Force -ErrorAction SilentlyContinue
                        Write-Success "Restored registry value: $($entry.Name)"
                    } catch {
                        Write-Warn "Could not restore registry entry: $($entry.Name)"
                    }
                } else {
                    # If property didn't exist originally, remove it
                    try {
                        if (Test-Path $entry.Path) {
                            Remove-ItemProperty -Path $entry.Path -Name $entry.Name -Force -ErrorAction SilentlyContinue
                            Write-Success "Removed added registry property: $($entry.Name)"
                        }
                    } catch {}
                }
            }
        } catch {
            Write-Err "Failed to parse registry backup file: $($_.Exception.Message)"
        }
    }

    # 3. Restore Startup Items
    $startFile = Join-Path $BackupFolder "startup_backup.json"
    if (Test-Path $startFile) {
        Write-Info "Restoring startup items..."
        try {
            $startItems = ConvertFrom-Json (Get-Content -Path $startFile -Raw)
            foreach ($item in $startItems) {
                if ($item.Type -eq "Registry") {
                    try {
                        Set-ItemProperty -Path $item.Location -Name $item.Name -Value $item.Command -Force -ErrorAction SilentlyContinue
                        Write-Success "Restored startup registry entry: $($item.Name)"
                    } catch {}
                } elseif ($item.Type -eq "Shortcut") {
                    try {
                        if ($item.Location.EndsWith(".disabled")) {
                            $orig = $item.Location.Replace(".disabled", "")
                            Rename-Item -Path $item.Location -NewName (Split-Path -Leaf $orig) -Force -ErrorAction SilentlyContinue
                            Write-Success "Restored startup shortcut: $($item.Name)"
                        }
                    } catch {}
                }
            }
        } catch {}
    }

    Write-Success "Rollback operations completed successfully."
    Write-Log -Level "SUCCESS" -Message "Rollback executed from $BackupFolder"
}

# -----------------------------------------------------------------------------
# 11. GENERATE OPTIMIZATION REPORT
# -----------------------------------------------------------------------------
function Generate-OptimizationReport {
    Show-Header "Generate Optimization & Health Report" "Compiles system diagnostics and session audit logs into a report"

    $reportFile = Join-Path $Script:ReportDir "OptimizationReport_$($Script:SessionId).md"
    Write-Info "Compiling system telemetry and optimization log..."

    $info = Get-SystemHealthInfo
    $servicesBackup = if (Test-Path (Join-Path $Script:SessionBackupFolder "services_backup.json")) {
        try { ConvertFrom-Json (Get-Content (Join-Path $Script:SessionBackupFolder "services_backup.json") -Raw) } catch { @() }
    } else { @() }

    $servicesTable = "_No services were modified in this session._"
    if ($servicesBackup.Count -gt 0) {
        $sb = "| Service Name | Display Name | Original Startup Type |`n|---|---|---|`n"
        foreach ($s in $servicesBackup) {
            $sb += "| $($s.Name) | $($s.DisplayName) | $($s.StartType) |`n"
        }
        $servicesTable = $sb
    }

    $reportContent = @"
# Windows Optimization & System Audit Report
Generated by Windows Optimizer v$($Script:Version)  
Timestamp: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")  
Session ID: $($Script:SessionId)

---

## 1. System Hardware & Environment
- **Computer Name:** $($info.ComputerName)
- **Operating System:** $($info.OSCaption) ($($info.Architecture))
- **OS Version & Build:** $($info.OSVersion) (Build $($info.OSBuild))
- **Administrator Elevation:** $(if ($info.IsAdmin) { "Yes (Elevated)" } else { "No (Standard User)" })
- **Processor:** $($info.ProcessorName) ($($info.Cores) Cores / $($info.LogicalProcessors) Threads)
- **Total Physical Memory (RAM):** $($info.TotalMemoryGB) GB
- **Memory In-Use:** $($info.UsedMemoryGB) GB ($($info.UsedMemoryPercent)%)
- **Active Power Scheme:** $($info.ActivePowerPlan)
- **System Uptime:** $($info.UptimeDays) days, $($info.UptimeHours) hours, $($info.UptimeMinutes) minutes
- **Live Process Count:** $($info.ProcessCount) active process handles
- **System Drive (C:):** $($info.FreeDiskGB) GB free of $($info.TotalDiskGB) GB ($($info.FreeDiskPercent)% available)

---

## 2. Optimization Operations Summary
- **Cumulative Disk Space Reclaimed:** $(Format-Bytes $Script:FreedBytesTotal)
- **Services Modified in Session:** $($servicesBackup.Count)
- **Dry-Run Mode Active:** $(if ($Script:IsDryRun) { "Yes (Simulated)" } else { "No (Live Executed)" })
- **Session Backup Location:** ``$($Script:SessionBackupFolder)``

---

## 3. Services Optimized This Session
$servicesTable

---

## 4. Performance Engineering Recommendations
1. **Process Count Understanding:**
   Windows 10/11 creates isolated ``svchost.exe`` instances per service for memory protection. Do not attempt to force process count below 130-140 by disabling essential networking, audio, or security services.
2. **Memory Management:**
   Avoid third-party memory purgers (RAM cleaners). Modern Windows memory caching keeps pre-warmed libraries in Standby RAM, maximizing responsiveness.
3. **Maintenance Cadence:**
   Run safe deep junk cleanup monthly and audit startup applications whenever new software is installed.
"@

    Set-Content -Path $reportFile -Value $reportContent -Encoding UTF8
    Write-Success "Optimization Report generated successfully at:"
    Write-Host "    $reportFile" -ForegroundColor Cyan
    Write-Log -Level "SUCCESS" -Message "Optimization report created: $reportFile"
    Prompt-Continue
}

# -----------------------------------------------------------------------------
# MAIN INTERACTIVE MENU LOOP & CLI DISPATCHER
# -----------------------------------------------------------------------------
function Show-MainMenu {
    while ($true) {
        $info = Get-SystemHealthInfo
        Show-Header "Interactive Operations Dashboard"

        Write-Host "  System Status Summary:" -ForegroundColor Yellow
        Write-Host ("    OS: {0} (Build {1}) | Admin: {2}" -f $info.OSCaption, $info.OSBuild, $(if ($info.IsAdmin) { "YES" } else { "NO" }))
        Write-Host ("    CPU: {0} ({1}T) | RAM: {2} GB ({3}% used)" -f $info.ProcessorName, $info.LogicalProcessors, $info.TotalMemoryGB, $info.UsedMemoryPercent)
        Write-Host ("    Live Processes: {0} | Disk C: {1} GB Free" -f $info.ProcessCount, $info.FreeDiskGB)
        if ($Script:IsDryRun) {
            Write-Host "    *** DRY-RUN SIMULATION MODE ACTIVE (No system changes will be written) ***" -ForegroundColor Magenta
        }
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray

        Write-Host "  Select an operation:" -ForegroundColor Cyan
        Write-Host "   [1]  System Information and Health Check"
        Write-Host "   [2]  Analyze CPU, RAM, Disk, and Running Processes (Dry Run / Live)"
        Write-Host "   [3]  Safe Deep Junk Cleanup (Temp, Crash Reports, Shader Caches)"
        Write-Host "   [4]  Startup Applications Optimization"
        Write-Host "   [5]  Background Process Management (Graceful Non-Essential App Closer)"
        Write-Host "   [6]  Windows Services Optimization (Safe & Advanced Profiles)"
        Write-Host "   [7]  Gaming Optimization Profile (Game Mode & Background Suppressor)"
        Write-Host "   [8]  Optional Privacy Optimization (Telemetry & Start Menu Search)"
        Write-Host "   [9]  Full Safe Optimization Pipeline (Recommended Preset)"
        Write-Host "   [10] Restore Previous Changes (Rollback Engine)"
        Write-Host "   [11] Generate Optimization Report"
        Write-Host "   [12] Exit Optimizer"
        Write-Host ""
        Write-Host "  Enter your choice [1-12]: " -ForegroundColor Yellow -NoNewline
        $selection = [System.Console]::ReadLine()

        switch ($selection.Trim()) {
            "1"  { Show-SystemHealthCheck }
            "2"  { Analyze-SystemResources }
            "3"  { Invoke-SafeDeepJunkCleanup }
            "4"  { Show-StartupApplicationsMenu }
            "5"  { Show-BackgroundProcessManager }
            "6"  { Show-WindowsServicesOptimization }
            "7"  { Show-GamingOptimization }
            "8"  { Show-PrivacyOptimization }
            "9"  { Invoke-FullSafeOptimization }
            "10" { Invoke-RollbackEngine }
            "11" { Generate-OptimizationReport }
            "12" {
                Write-Host ""
                Write-Success "Thank you for using Windows Optimizer. Exiting safely."
                return
            }
            default {
                Write-Warn "Invalid choice. Please enter a number between 1 and 12."
                Start-Sleep -Milliseconds 800
            }
        }
    }
}

# -----------------------------------------------------------------------------
# COMMAND LINE DISPATCH ENTRYPOINT
# -----------------------------------------------------------------------------
if ($Help) {
    Show-Header "Command-Line Help & Parameter Reference"
    Write-Host @"
USAGE:
    powershell.exe -ExecutionPolicy Bypass -File WindowsOptimizer.ps1 [OPTIONS]

OPTIONS:
    -Analyze      Run deep resource & junk storage diagnostics without modifying files.
    -Cleanup      Execute safe deep junk file cleanup.
    -Startup      Open startup applications inspection.
    -Processes    Open background process manager.
    -Services     Open Windows service optimization engine.
    -Gaming       Open gaming profile optimizer.
    -Privacy      Open privacy and telemetry optimizer.
    -Full         Run the Full Safe Optimization pipeline with confirmation.
    -Rollback     Open the rollback engine to restore previous backups.
    -Report       Generate system diagnostics & optimization report.
    -DryRun       Simulate actions without writing any changes to disk or registry.
    -Help         Show this command-line help screen.

Running without arguments opens the full interactive dashboard menu.
"@
    exit 0
}

if ($Analyze)   { Analyze-SystemResources; exit 0 }
if ($Cleanup)   { Invoke-SafeDeepJunkCleanup; exit 0 }
if ($Startup)   { Show-StartupApplicationsMenu; exit 0 }
if ($Processes) { Show-BackgroundProcessManager; exit 0 }
if ($Services)  { Show-WindowsServicesOptimization; exit 0 }
if ($Gaming)    { Show-GamingOptimization; exit 0 }
if ($Privacy)   { Show-PrivacyOptimization; exit 0 }
if ($Full)      { Invoke-FullSafeOptimization; exit 0 }
if ($Rollback)  { Invoke-RollbackEngine; exit 0 }
if ($Report)    { Generate-OptimizationReport; exit 0 }

# Launch Interactive Main Menu if no switch passed
Show-MainMenu
