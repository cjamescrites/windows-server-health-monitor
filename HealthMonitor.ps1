<#
.SYNOPSIS
    Performs read-only checks of Windows services, fixed-disk capacity, and recent Application log errors.
.DESCRIPTION
    Reports diagnostic information only. It does not restart services, change settings,
    patch the computer, or modify files. Run only on systems you are authorized to inspect.
.EXAMPLE
    .\HealthMonitor.ps1
.EXAMPLE
    .\HealthMonitor.ps1 -ServiceName EventLog,Schedule -DiskWarningPercentFree 20 -LookbackHours 12
#>

[CmdletBinding()]
param(
    # Windows service names to inspect; these are common built-in services.
    [string[]]$ServiceName = @("EventLog", "Schedule"),

    # Warn when a fixed disk has less than this percentage of space free.
    [ValidateRange(1, 100)]
    [int]$DiskWarningPercentFree = 20,

    # Number of hours to search backward in the Application event log.
    [ValidateRange(1, 168)]
    [int]$LookbackHours = 24,

    # Used by tests to load the functions without automatically running the report.
    [switch]$NoRun
)

# Catch common scripting mistakes and stop on unexpected errors.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ServiceHealth {
    <# Query each requested service and return a consistent result object. #>
    [CmdletBinding()]
    param(
        # One or more service names to query.
        [Parameter(Mandatory)]
        [string[]]$Name
    )

    # Check services one by one so a missing service does not stop other checks.
    foreach ($serviceNameItem in $Name) {
        try {
            # Get-Service only reads status; it does not start or stop the service.
            $service = Get-Service -Name $serviceNameItem -ErrorAction Stop

            # Return fields that are easy to display and test.
            [pscustomobject]@{
                Name    = $serviceNameItem
                Status  = [string]$service.Status
                Found   = $true
                Healthy = ([string]$service.Status -eq "Running")
                Message = if ([string]$service.Status -eq "Running") {
                    "Service is running."
                } else {
                    "Service is not running."
                }
            }
        }
        catch {
            # Record the failure and continue rather than terminating the whole report.
            [pscustomobject]@{
                Name    = $serviceNameItem
                Status  = "Unknown"
                Found   = $false
                Healthy = $false
                Message = "Could not query service: $($_.Exception.Message)"
            }
        }
    }
}

function Get-DiskHealth {
    <# Report fixed-disk capacity and flag disks below the free-space threshold. #>
    [CmdletBinding()]
    param(
        # Minimum acceptable percentage of free disk space.
        [ValidateRange(1, 100)]
        [int]$WarningPercentFree = 20
    )

    try {
        # DriveType=3 selects local fixed disks, not network or removable drives.
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop

        # Calculate the free percentage for each valid disk returned by Windows.
        foreach ($disk in $disks) {
            # Skip invalid capacity values to avoid dividing by zero or null.
            if (-not $disk.Size -or $disk.Size -le 0) {
                continue
            }

            $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)

            # Return disk measurements plus a threshold-based health result.
            [pscustomobject]@{
                Drive            = $disk.DeviceID
                SizeGB           = [math]::Round($disk.Size / 1GB, 2)
                FreeGB           = [math]::Round($disk.FreeSpace / 1GB, 2)
                PercentFree      = $freePercent
                Healthy          = ($freePercent -ge $WarningPercentFree)
                WarningThreshold = $WarningPercentFree
                Message          = if ($freePercent -lt $WarningPercentFree) {
                    "Low disk space."
                } else {
                    "Disk space is within threshold."
                }
            }
        }
    }
    catch {
        # Return a diagnostic record if Windows cannot provide disk information.
        [pscustomobject]@{
            Drive            = "Unknown"
            SizeGB           = $null
            FreeGB           = $null
            PercentFree      = $null
            Healthy          = $false
            WarningThreshold = $WarningPercentFree
            Message          = "Could not query disk space: $($_.Exception.Message)"
        }
    }
}

function Get-RecentApplicationErrors {
    <# Return up to 20 error-level events from the Application log. #>
    [CmdletBinding()]
    param(
        # Number of hours to include in the event search.
        [ValidateRange(1, 168)]
        [int]$Hours = 24
    )

    # Establish the earliest timestamp to include in the query.
    $startTime = (Get-Date).AddHours(-$Hours)

    try {
        # Windows event level 2 means Error; MaxEvents limits the report size.
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = "Application"
            Level     = 2
            StartTime = $startTime
        } -MaxEvents 20 -ErrorAction Stop

        # Select relevant fields and compress whitespace in event messages.
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
        # Get-WinEvent throws when no events match. Treat that as an empty result;
        # surface other query or access errors as a diagnostic record.
        if ($_.Exception.Message -match "No events were found|No events found") {
            return
        }

        [pscustomobject]@{
            TimeCreated = $null
            Provider    = "Unknown"
            EventId     = $null
            Message     = "Could not query Application log: $($_.Exception.Message)"
        }
    }
}

function Invoke-HealthCheck {
    <# Run all checks and collect their results into a single report object. #>
    [CmdletBinding()]
    param(
        # Services to include in the report.
        [string[]]$Services = @("EventLog", "Schedule"),

        # Free-space threshold passed to the disk check.
        [ValidateRange(1, 100)]
        [int]$WarningPercentFree = 20,

        # Time window passed to the event-log check.
        [ValidateRange(1, 168)]
        [int]$Hours = 24
    )

    # Wrap results in arrays so empty results are handled consistently.
    $serviceResults = @(Get-ServiceHealth -Name $Services)
    $diskResults = @(Get-DiskHealth -WarningPercentFree $WarningPercentFree)
    $errorResults = @(Get-RecentApplicationErrors -Hours $Hours)

    # Overall health uses service and disk checks. Event errors are displayed for
    # investigation because event severity alone does not establish business impact.
    [pscustomobject]@{
        GeneratedAt     = Get-Date
        ComputerName    = $env:COMPUTERNAME
        Services        = $serviceResults
        Disks           = $diskResults
        RecentAppErrors = $errorResults
        Healthy         = (
            (@($serviceResults | Where-Object { -not $_.Healthy }).Count -eq 0) -and
            (@($diskResults | Where-Object { -not $_.Healthy }).Count -eq 0)
        )
    }
}

# Run the report by default. Tests pass -NoRun to import functions without querying the host.
if (-not $NoRun) {
    # Collect results using the values supplied on the command line or the defaults above.
    $report = Invoke-HealthCheck `
        -Services $ServiceName `
        -WarningPercentFree $DiskWarningPercentFree `
        -Hours $LookbackHours

    # Print report metadata and the overall status.
    Write-Host "`nWindows Server Health Monitor"
    Write-Host "Computer: $($report.ComputerName)"
    Write-Host "Generated: $($report.GeneratedAt)"
    Write-Host "Overall status: $(if ($report.Healthy) { 'HEALTHY' } else { 'ATTENTION REQUIRED' })"

    # Print service results in a readable table.
    Write-Host "`nServices"
    if ($report.Services.Count -eq 0) {
        Write-Host "  No services selected."
    } else {
        $report.Services | Format-Table Name, Status, Healthy, Message -AutoSize | Out-Host
    }

    # Print fixed-disk capacity results.
    Write-Host "Disk space"
    if ($report.Disks.Count -eq 0) {
        Write-Host "  No fixed disks found."
    } else {
        $report.Disks | Format-Table Drive, SizeGB, FreeGB, PercentFree, Healthy, Message -AutoSize | Out-Host
    }

    # Print recent event errors or a clear message when there are none.
    Write-Host "Recent Application log errors (up to 20)"
    if ($report.RecentAppErrors.Count -eq 0) {
        Write-Host "  No matching errors found in the selected time window."
    } else {
        $report.RecentAppErrors | Format-Table TimeCreated, Provider, EventId, Message -Wrap -AutoSize | Out-Host
    }
}
