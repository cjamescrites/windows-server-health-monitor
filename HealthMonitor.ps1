[CmdletBinding()]
param(
    [string[]]$ServiceName = @("EventLog", "Schedule"),
    [ValidateRange(1, 100)] [int]$DiskWarningPercentFree = 20,
    [ValidateRange(1, 168)] [int]$LookbackHours = 24,
    [switch]$NoRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ServiceHealth {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Name)

    foreach ($serviceNameItem in $Name) {
        try {
            $service = Get-Service -Name $serviceNameItem -ErrorAction Stop
            [pscustomobject]@{
                Name        = $serviceNameItem
                Status      = [string]$service.Status
                Found       = $true
                Healthy     = ([string]$service.Status -eq "Running")
                Message     = if ([string]$service.Status -eq "Running") { "Service is running." } else { "Service is not running." }
            }
        }
        catch {
            [pscustomobject]@{
                Name        = $serviceNameItem
                Status      = "Unknown"
                Found       = $false
                Healthy     = $false
                Message     = "Could not query service: $($_.Exception.Message)"
            }
        }
    }
}

function Get-DiskHealth {
    [CmdletBinding()]
    param([ValidateRange(1, 100)][int]$WarningPercentFree = 20)

    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
        foreach ($disk in $disks) {
            if (-not $disk.Size -or $disk.Size -le 0) { continue }

            $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
            [pscustomobject]@{
                Drive            = $disk.DeviceID
                SizeGB           = [math]::Round($disk.Size / 1GB, 2)
                FreeGB           = [math]::Round($disk.FreeSpace / 1GB, 2)
                PercentFree      = $freePercent
                Healthy          = ($freePercent -ge $WarningPercentFree)
                WarningThreshold = $WarningPercentFree
                Message           = if ($freePercent -lt $WarningPercentFree) { "Low disk space." } else { "Disk space is within threshold." }
            }
        }
    }
    catch {
        [pscustomobject]@{
            Drive = "Unknown"; SizeGB = $null; FreeGB = $null; PercentFree = $null
            Healthy = $false; WarningThreshold = $WarningPercentFree
            Message = "Could not query disk space: $($_.Exception.Message)"
        }
    }
}

function Get-RecentApplicationErrors {
    [CmdletBinding()]
    param([ValidateRange(1, 168)][int]$Hours = 24)

    $startTime = (Get-Date).AddHours(-$Hours)
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = "Application"
            Level     = 2
            StartTime = $startTime
        } -MaxEvents 20 -ErrorAction Stop

        foreach ($event in $events) {
            [pscustomobject]@{
                TimeCreated = $event.TimeCreated
                Provider    = $event.ProviderName
                EventId     = $event.Id
                Message     = (($event.Message -replace '\s+', ' ').Trim())
            }
        }
    }
    catch {
        # Get-WinEvent throws when no matching events exist. Treat that as an empty result;
        # other access/query errors are surfaced as a single diagnostic record.
        if ($_.Exception.Message -match "No events were found|No events found") {
            return
        }
        [pscustomobject]@{
            TimeCreated = $null; Provider = "Unknown"; EventId = $null
            Message = "Could not query Application log: $($_.Exception.Message)"
        }
    }
}

function Invoke-HealthCheck {
    [CmdletBinding()]
    param(
        [string[]]$Services = @("EventLog", "Schedule"),
        [ValidateRange(1, 100)][int]$WarningPercentFree = 20,
        [ValidateRange(1, 168)][int]$Hours = 24
    )

    $serviceResults = @(Get-ServiceHealth -Name $Services)
    $diskResults = @(Get-DiskHealth -WarningPercentFree $WarningPercentFree)
    $errorResults = @(Get-RecentApplicationErrors -Hours $Hours)

    [pscustomobject]@{
        GeneratedAt      = Get-Date
        ComputerName     = $env:COMPUTERNAME
        Services         = $serviceResults
        Disks            = $diskResults
        RecentAppErrors  = $errorResults
        Healthy          = (
            (@($serviceResults | Where-Object { -not $_.Healthy }).Count -eq 0) -and
            (@($diskResults | Where-Object { -not $_.Healthy }).Count -eq 0)
        )
    }
}

if (-not $NoRun) {
    $report = Invoke-HealthCheck -Services $ServiceName -WarningPercentFree $DiskWarningPercentFree -Hours $LookbackHours

    Write-Host "`nWindows Server Health Monitor"
    Write-Host "Computer: $($report.ComputerName)"
    Write-Host "Generated: $($report.GeneratedAt)"
    Write-Host "Overall status: $(if ($report.Healthy) { 'HEALTHY' } else { 'ATTENTION REQUIRED' })"

    Write-Host "`nServices"
    if ($report.Services.Count -eq 0) { Write-Host "  No services selected." }
    $report.Services | Format-Table Name, Status, Healthy, Message -AutoSize | Out-Host

    Write-Host "Disk space"
    if ($report.Disks.Count -eq 0) { Write-Host "  No fixed disks found." }
    $report.Disks | Format-Table Drive, SizeGB, FreeGB, PercentFree, Healthy, Message -AutoSize | Out-Host

    Write-Host "Recent Application log errors (up to 20)"
    if ($report.RecentAppErrors.Count -eq 0) {
        Write-Host "  No matching errors found in the selected time window."
    } else {
        $report.RecentAppErrors | Format-Table TimeCreated, Provider, EventId, Message -Wrap -AutoSize | Out-Host
    }
}
