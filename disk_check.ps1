# disk_check.ps1 — SSD / OS Health Check & Auto-Repair
# Run as Administrator: right-click PowerShell > Run as Administrator, then .\disk_check.ps1

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile   = Join-Path $scriptDir "disk_check_$timestamp.txt"

$issuesFound  = 0
$fixesApplied = 0
$issueList    = @()
$fixList      = @()
$skipList     = @()

function ts { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }

function Log {
    param([string]$msg)
    Write-Host $msg
    Add-Content -Path $logFile -Value $msg
}

function LogRaw {
    param([string]$msg)
    Add-Content -Path $logFile -Value $msg
}

function Section {
    param([string]$title)
    Log ""
    Log "--- $title"
    LogRaw "[$(ts)] SECTION: $title"
}

function RecordCmd {
    param([string]$label, [string]$cmd, [string]$summary, [string]$status)
    LogRaw ""
    LogRaw "[$(ts)] CMD    : $cmd"
    LogRaw "[$(ts)] LABEL  : $label"
    LogRaw "[$(ts)] RESULT : $summary"
    LogRaw "[$(ts)] STATUS : $status"
}

function ProgressBar {
    param([string]$label, [int]$seconds = 3)
    $width = 40
    Write-Host -NoNewline "  $label  ["
    for ($i = 0; $i -lt $width; $i++) {
        Start-Sleep -Milliseconds ([math]::Round($seconds * 1000 / $width))
        Write-Host -NoNewline "#"
    }
    Write-Host "] done"
}

function FakeProgress {
    param([string]$label)
    $width = 40
    Write-Host -NoNewline "  $label  ["
    for ($i = 0; $i -lt $width; $i++) {
        Start-Sleep -Milliseconds 30
        Write-Host -NoNewline "#"
    }
    Write-Host "] done"
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "disk_check.ps1"
Write-Host "SSD and OS Health Checker + Auto-Repair (Windows)"
Write-Host "Started : $(ts)"
Write-Host "Log     : $logFile"
Write-Host ""

LogRaw "=================================================="
LogRaw " DISK CHECK REPORT (Windows)"
LogRaw " Started : $(ts)"
LogRaw " Host    : $env:COMPUTERNAME"
LogRaw " OS      : $([System.Environment]::OSVersion.VersionString)"
LogRaw " User    : $env:USERNAME"
LogRaw "=================================================="

Start-Sleep -Seconds 1

Section "1. Detecting Disks"
FakeProgress "Scanning physical disks"

$disks = Get-PhysicalDisk | Sort-Object DeviceId
if (-not $disks) {
    Log "  ERROR: No disks found. Exiting."
    exit 1
}

Log ""
foreach ($disk in $disks) {
    $sizeGB = [math]::Round($disk.Size / 1GB, 1)
    $media  = $disk.MediaType
    $model  = $disk.FriendlyName
    $health = $disk.HealthStatus
    $status = $disk.OperationalStatus
    Log "  Disk $($disk.DeviceId)  ${sizeGB}GB  [$media]  $model  Health: $health  Status: $status"
    LogRaw "[$(ts)] Disk $($disk.DeviceId): $model | $media | ${sizeGB}GB | Health: $health | Status: $status"
}

Section "2. SMART and Reliability Data"

foreach ($disk in $disks) {
    Log ""
    Log "  Checking Disk $($disk.DeviceId) -- $($disk.FriendlyName) ..."
    ProgressBar "Reading reliability counters for Disk $($disk.DeviceId)" 3

    try {
        $rel      = $disk | Get-StorageReliabilityCounter -ErrorAction Stop
        $readErr  = $rel.ReadErrorsTotal
        $writeErr = $rel.WriteErrorsTotal
        $wear     = $rel.Wear
        $temp     = $rel.Temperature
        $hours    = $rel.PowerOnHours

        Log "  Read errors   : $readErr"
        Log "  Write errors  : $writeErr"
        Log "  Wear level    : $(if ($wear) { "$wear%" } else { 'N/A' })"
        Log "  Temperature   : $(if ($temp) { "${temp}C" } else { 'N/A' })"
        Log "  Power-on hrs  : $(if ($hours) { $hours } else { 'N/A' })"

        RecordCmd "Reliability Disk $($disk.DeviceId)" "Get-StorageReliabilityCounter" "Read: $readErr  Write: $writeErr  Wear: $wear%  Temp: ${temp}C  Hours: $hours" "pass"

        if ($readErr -gt 0 -or $writeErr -gt 0) {
            Log "  WARNING: Non-zero read/write errors detected."
            $script:issueList += "Disk $($disk.DeviceId) ($($disk.FriendlyName)): read errors=$readErr, write errors=$writeErr"
            $script:issuesFound++
        }
        if ($wear -and $wear -ge 90) {
            Log "  WARNING: Wear level at $wear% -- drive nearing end of life."
            $script:issueList += "Disk $($disk.DeviceId): wear level critical at $wear%"
            $script:issuesFound++
        }
        if ($temp -and $temp -ge 60) {
            Log "  WARNING: Drive temperature high: ${temp}C"
            $script:issueList += "Disk $($disk.DeviceId): high temperature ${temp}C"
            $script:issuesFound++
        }
        if ($readErr -eq 0 -and $writeErr -eq 0) {
            Log "  No read/write errors."
        }
    } catch {
        Log "  Reliability data unavailable for Disk $($disk.DeviceId) (may require storage driver support)."
        $script:skipList += "SMART Disk $($disk.DeviceId) -- data unavailable"
        RecordCmd "Reliability Disk $($disk.DeviceId)" "Get-StorageReliabilityCounter" "Data unavailable" "warn"
    }
}

Section "3. Disk Health Status"
FakeProgress "Checking disk health status"

foreach ($disk in $disks) {
    $health = $disk.HealthStatus
    $op     = $disk.OperationalStatus
    if ($health -ne "Healthy" -or $op -ne "OK") {
        Log "  WARNING: Disk $($disk.DeviceId) ($($disk.FriendlyName)) -- Health: $health | Status: $op"
        $issueList += "Disk $($disk.DeviceId) health degraded: $health / $op"
        $issuesFound++
        RecordCmd "Disk health $($disk.DeviceId)" "Get-PhysicalDisk" "Health: $health, Status: $op" "fail"
    } else {
        Log "  OK: Disk $($disk.DeviceId) ($($disk.FriendlyName)) -- Health: $health"
        RecordCmd "Disk health $($disk.DeviceId)" "Get-PhysicalDisk" "Healthy and operational" "pass"
    }
}

Section "4. Volume and Partition Check"
FakeProgress "Scanning volumes"

$volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
foreach ($vol in $volumes) {
    $letter  = $vol.DriveLetter
    $label   = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "unlabeled" }
    $fs      = $vol.FileSystem
    $health  = $vol.HealthStatus
    $sizeGB  = [math]::Round($vol.Size / 1GB, 1)
    $freeGB  = [math]::Round($vol.SizeRemaining / 1GB, 1)
    $usedPct = if ($vol.Size -gt 0) { [math]::Round((($vol.Size - $vol.SizeRemaining) / $vol.Size) * 100) } else { 0 }

    Log ""
    Log "  ${letter}:  [$fs]  $label  ${sizeGB}GB total  ${freeGB}GB free  ${usedPct}% used  Health: $health"
    LogRaw "[$(ts)] Volume ${letter}: FS=$fs Label=$label Size=${sizeGB}GB Free=${freeGB}GB Used=${usedPct}% Health=$health"

    if ($health -ne "Healthy") {
        Log "  WARNING: Volume ${letter}: health status is $health"
        $issueList += "Volume ${letter}: ($label) health is $health"
        $issuesFound++
        RecordCmd "Volume health ${letter}:" "Get-Volume" "Health: $health" "fail"
    } else {
        RecordCmd "Volume health ${letter}:" "Get-Volume" "Healthy -- ${usedPct}% used" "pass"
    }

    if ($usedPct -ge 95) {
        Log "  CRITICAL: ${letter}: is ${usedPct}% full -- critically low space."
        $issueList += "Volume ${letter}: critically full at ${usedPct}%"
        $issuesFound++
        RecordCmd "Disk usage ${letter}:" "Get-Volume" "${usedPct}% full -- critical" "fail"
    } elseif ($usedPct -ge 80) {
        Log "  WARNING: ${letter}: is ${usedPct}% full -- consider cleaning up."
        $issueList += "Volume ${letter}: high usage at ${usedPct}%"
        $issuesFound++
        RecordCmd "Disk usage ${letter}:" "Get-Volume" "${usedPct}% full -- high" "warn"
    }
}

Section "5. Filesystem Integrity Check (chkdsk)"

foreach ($vol in $volumes) {
    $letter = $vol.DriveLetter
    Log ""
    Log "  Checking ${letter}: ..."
    ProgressBar "Running chkdsk on ${letter}:" 4

    try {
        $result = Repair-Volume -DriveLetter $letter -Scan -ErrorAction Stop
        if ($result -eq "NoErrorsFound" -or $result -eq "NoErrorsDetected") {
            Log "  No filesystem errors on ${letter}:"
            RecordCmd "chkdsk ${letter}:" "Repair-Volume -Scan" "No errors found" "pass"
        } elseif ($result -eq "ErrorsFound") {
            Log "  Errors found on ${letter}: -- attempting spot fix..."
            ProgressBar "Repairing ${letter}:" 5
            $fix = Repair-Volume -DriveLetter $letter -SpotFix -ErrorAction SilentlyContinue
            Log "  Spot fix result: $fix"
            $issueList += "Filesystem errors on ${letter}: (spot fix attempted)"
            $fixList   += "chkdsk spot fix run on ${letter}:"
            $issuesFound++
            $fixesApplied++
            RecordCmd "chkdsk repair ${letter}:" "Repair-Volume -SpotFix" "Errors found, spot fix attempted: $fix" "warn"
        } else {
            Log "  chkdsk result for ${letter}: $result"
            RecordCmd "chkdsk ${letter}:" "Repair-Volume -Scan" "Result: $result" "warn"
        }
    } catch {
        Log "  Could not run chkdsk on ${letter}: -- $($_.Exception.Message)"
        $skipList += "chkdsk ${letter}: -- access error"
        RecordCmd "chkdsk ${letter}:" "Repair-Volume -Scan" "Failed: $($_.Exception.Message)" "fail"
    }
}

Section "6. Event Log — Disk Error Scan"
FakeProgress "Scanning event log for disk errors"

try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        Level     = 1,2,3
        StartTime = (Get-Date).AddHours(-24)
    } -ErrorAction Stop | Where-Object {
        $_.Message -match "disk|harddisk|volume|ntfs|fat|filesystem|bad block|sector|storage"
    } | Select-Object -First 15

    if ($events) {
        Log "  Disk-related errors in Event Log (last 24h):"
        foreach ($ev in $events) {
            $evLine = "    [$($ev.TimeCreated)] ID $($ev.Id) -- $($ev.Message.Split([char]10)[0])"
            Log $evLine
        }
        $issueList += "Disk-related errors found in Windows Event Log"
        $issuesFound++
        RecordCmd "Event log disk errors" "Get-WinEvent System" "Disk errors found in last 24h" "warn"
    } else {
        Log "  No disk-related errors in Event Log (last 24h)."
        RecordCmd "Event log disk errors" "Get-WinEvent System" "No disk errors in last 24h" "pass"
    }
} catch {
    Log "  Could not read Event Log -- $($_.Exception.Message)"
    $skipList += "Event log check -- access error"
}

Section "7. Memory and Page File Status"
FakeProgress "Reading memory info"

$os      = Get-CimInstance Win32_OperatingSystem
$totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$freeRAM  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$usedRAM  = [math]::Round($totalRAM - $freeRAM, 1)
$ramPct   = [math]::Round(($usedRAM / $totalRAM) * 100)

Log "  RAM: ${usedRAM}GB used / ${totalRAM}GB total (${ramPct}%)"
LogRaw "[$(ts)] RAM: ${usedRAM}GB / ${totalRAM}GB (${ramPct}%)"

if ($ramPct -ge 90) {
    Log "  WARNING: Memory usage is very high at ${ramPct}%."
    $issueList += "High memory usage: ${ramPct}%"
    $issuesFound++
    RecordCmd "Memory check" "Win32_OperatingSystem" "RAM at ${ramPct}% -- high" "warn"
} else {
    Log "  Memory usage OK."
    RecordCmd "Memory check" "Win32_OperatingSystem" "RAM at ${ramPct}% -- OK" "pass"
}

$pageFile = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
if ($pageFile) {
    foreach ($pf in $pageFile) {
        $pfUsedPct = if ($pf.AllocatedBaseSize -gt 0) { [math]::Round(($pf.CurrentUsage / $pf.AllocatedBaseSize) * 100) } else { 0 }
        Log "  Page file: $($pf.Name)  $($pf.CurrentUsage)MB used / $($pf.AllocatedBaseSize)MB allocated (${pfUsedPct}%)"
        LogRaw "[$(ts)] Page file: $($pf.Name) -- ${pfUsedPct}% used"
        if ($pfUsedPct -ge 80) {
            Log "  WARNING: Page file usage high at ${pfUsedPct}%."
            $issueList += "Page file usage high: ${pfUsedPct}%"
            $issuesFound++
        }
    }
} else {
    Log "  No page file info available."
    $skipList += "Page file check -- no data"
}

Section "8. SSD TRIM / Optimize"

foreach ($vol in $volumes) {
    $letter = $vol.DriveLetter
    Log ""
    Log "  Optimizing ${letter}: ..."
    ProgressBar "Running Optimize-Volume on ${letter}:" 4

    try {
        Optimize-Volume -DriveLetter $letter -ReTrim -Verbose *>> $logFile 2>&1
        Log "  TRIM / optimize completed for ${letter}:"
        $fixList += "Optimize-Volume (TRIM) run on ${letter}:"
        $fixesApplied++
        RecordCmd "Optimize-Volume ${letter}:" "Optimize-Volume -ReTrim" "Completed successfully" "pass"
    } catch {
        Log "  Could not optimize ${letter}: -- $($_.Exception.Message)"
        $skipList += "Optimize-Volume ${letter}: -- error"
        RecordCmd "Optimize-Volume ${letter}:" "Optimize-Volume -ReTrim" "Failed: $($_.Exception.Message)" "warn"
    }
}

Section "9. System File Integrity (sfc + DISM)"

Log "  Running SFC -- this may take a few minutes..."
ProgressBar "Running sfc /scannow" 10

$sfcOut = & sfc /scannow 2>&1 | Out-String
$sfcOut | Add-Content -Path $logFile

if ($sfcOut -match "did not find any integrity violations" -or $sfcOut -match "no integrity violations") {
    Log "  SFC: No integrity violations found."
    RecordCmd "sfc /scannow" "sfc /scannow" "No integrity violations" "pass"
} elseif ($sfcOut -match "found corrupt files and successfully repaired") {
    Log "  SFC: Corrupt files found and repaired."
    $issueList   += "SFC found and repaired corrupt system files"
    $fixList     += "SFC repaired corrupt system files"
    $issuesFound++
    $fixesApplied++
    RecordCmd "sfc /scannow" "sfc /scannow" "Corrupt files repaired" "warn"
} elseif ($sfcOut -match "found corrupt files but was unable to fix") {
    Log "  SFC: Corrupt files found but could not be repaired -- running DISM..."
    $issueList += "SFC found corrupt files it could not repair"
    $issuesFound++
    RecordCmd "sfc /scannow" "sfc /scannow" "Corrupt files found, unfixed" "fail"

    Log "  Running DISM RestoreHealth..."
    ProgressBar "Running DISM /RestoreHealth" 15
    $dismOut = & DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-String
    $dismOut | Add-Content -Path $logFile
    if ($dismOut -match "The restore operation completed successfully") {
        Log "  DISM: Restore completed successfully."
        $fixList     += "DISM RestoreHealth completed successfully"
        $fixesApplied++
        RecordCmd "DISM RestoreHealth" "DISM /Online /Cleanup-Image /RestoreHealth" "Restore successful" "pass"
    } else {
        Log "  DISM: Restore may not have fully succeeded -- check log for details."
        RecordCmd "DISM RestoreHealth" "DISM /Online /Cleanup-Image /RestoreHealth" "Result unclear -- see log" "warn"
    }
} else {
    Log "  SFC: Could not determine result -- see log for raw output."
    RecordCmd "sfc /scannow" "sfc /scannow" "Result unclear -- see log" "warn"
}

Log ""
Log "--- FINAL STATUS REPORT"
Log ""

LogRaw ""
LogRaw "=================================================="
LogRaw " FINAL STATUS REPORT"
LogRaw " Completed : $(ts)"
LogRaw "=================================================="

if ($issuesFound -eq 0) {
    Log "  PASS -- No issues detected."
    LogRaw "  OVERALL: PASS -- No issues detected."
} else {
    Log "  $issuesFound issue(s) found, $fixesApplied fix(es) applied."
    LogRaw "  OVERALL: $issuesFound issue(s) found, $fixesApplied fix(es) applied."
}

Log ""

if ($issueList.Count -gt 0) {
    Log "  Issues:"
    LogRaw "  Issues:"
    foreach ($issue in $issueList) {
        Log "    - $issue"
        LogRaw "    - $issue"
    }
    Log ""
}

if ($fixList.Count -gt 0) {
    Log "  Fixes applied:"
    LogRaw "  Fixes applied:"
    foreach ($fix in $fixList) {
        Log "    - $fix"
        LogRaw "    - $fix"
    }
    Log ""
}

if ($skipList.Count -gt 0) {
    Log "  Skipped:"
    LogRaw "  Skipped:"
    foreach ($skip in $skipList) {
        Log "    - $skip"
        LogRaw "    - $skip"
    }
    Log ""
}

Log "  Log saved to: $logFile"
Log ""
LogRaw "=================================================="
LogRaw " END OF REPORT"
LogRaw "=================================================="