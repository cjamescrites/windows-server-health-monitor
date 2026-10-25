# Windows Server Health Monitor

A beginner-friendly, read-only PowerShell project that checks selected Windows services, fixed-disk free space, and recent errors in the Windows Application event log. GitHub Actions runs syntax validation and automated tests on pull requests.

## Features

- Checks whether selected Windows services are running.
- Reports fixed disks' total size, free space, and percentage free.
- Flags disks below a configurable free-space threshold.
- Lists up to 20 recent error-level events from the Application log.
- Includes Pester tests and a GitHub Actions validation workflow.
- Does not change service states, edit configuration, patch the server, or delete data.

## Requirements

- Windows 10/11 or Windows Server with Windows PowerShell 5.1 or PowerShell 7.
- A user account allowed to query the selected services, fixed disks, and Application event log.
- Git for version control (optional if you download the repository ZIP).
- Pester 5 or newer to run the tests locally. The GitHub Actions workflow installs it automatically.

Some event log details may be restricted by local policy. Run with only the permissions your environment authorizes. Do not run this against production systems without approval.

## Run it

Open PowerShell in the project folder:

```powershell
.\HealthMonitor.ps1
```

Choose services and thresholds:

```powershell
.\HealthMonitor.ps1 -ServiceName EventLog,Schedule -DiskWarningPercentFree 20 -LookbackHours 12
```

The default service names are `EventLog` and `Schedule`. A service that is missing or cannot be queried is reported as not healthy; review the message to determine why.

## Sample output

Exact values vary by machine. Example:

```text
Windows Server Health Monitor
Computer: APP-SERVER-01
Generated: 10/25/2026 11:30:00 AM
Overall status: ATTENTION REQUIRED

Services
Name       Status   Healthy Message
----       ------   ------- -------
EventLog   Running     True Service is running.
Schedule   Running     True Service is running.

Disk space
Drive SizeGB FreeGB PercentFree Healthy Message
----- ------ ------ ----------- ------- -------
C:       80     8.0        10.0   False Low disk space.

Recent Application log errors (up to 20)
TimeCreated          Provider   EventId Message
-----------          --------   ------- -------
10/25/2026 10:42 AM  ExampleApp    1001 Example application error
```

The overall status reflects service and disk checks. Recent application errors are shown for investigation, but they do not automatically make the overall status unhealthy because the severity and impact of each event require context.

## Run the tests locally

Open PowerShell from the project directory:

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser
Invoke-Pester ./tests/HealthMonitor.Tests.ps1
```

The tests mock Windows commands, so the tests do not need to query or modify a real server. The syntax check parses the script without executing its health-check actions.

## What GitHub Actions checks

The workflow in `.github/workflows/validate.yml` runs on pull requests and pushes to `main`. It:

1. Checks out the repository.
2. Installs Pester.
3. Parses the script to catch syntax errors.
4. Runs tests for service status, disk thresholds, event formatting, and no-event behavior.

To require successful checks before merging, open **Settings → Branches** (or repository rulesets) in GitHub and require the workflow's status check. Branch protection availability depends on repository and organization settings.

## Troubleshooting

- **`running scripts is disabled on this system`:** review your organization's execution policy. Do not weaken machine-wide policy to run an unfamiliar script; ask an administrator about an approved approach.
- **Access denied reading events:** run under an authorized account or ask an administrator to confirm event-log permissions.
- **A service is `Unknown`:** verify the service name with `Get-Service` and confirm your account can query it.
- **No fixed disks are listed:** confirm the machine exposes fixed logical disks through `Win32_LogicalDisk`.
- **Pester is not recognized:** install/import Pester 5+ in the same PowerShell environment where tests run.
- **GitHub Actions fails:** open the failed workflow run, identify the first failing step, reproduce locally if possible, and fix the cause before merging.

## Suggested next steps

- Add structured JSON output for monitoring integrations.
- Add configurable service lists in a configuration file.
- Add a test for malformed or empty disk results.
- Only after a reviewed design, add scheduled execution or deployment integration.
