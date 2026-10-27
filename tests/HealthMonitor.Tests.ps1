# Automated tests for HealthMonitor.ps1.
# Windows commands are mocked so these tests do not depend on the current machine's
# actual services, disk capacity, or event log and do not change system state.

BeforeAll {
    # Resolve the script path relative to this test file, not the current directory.
    $script:scriptPath = Join-Path $PSScriptRoot "..\HealthMonitor.ps1"

    # Dot-source the script with -NoRun to load functions without running a report.
    . $script:scriptPath -NoRun
}

Describe "HealthMonitor syntax" {
    It "parses without syntax errors" {
        # Parse the file as PowerShell code without executing the health checks.
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path $script:scriptPath),
            [ref]$tokens,
            [ref]$parseErrors
        ) | Out-Null

        # The parser should report zero errors for a syntactically valid script.
        $parseErrors.Count | Should -Be 0
    }
}

Describe "Get-ServiceHealth" {
    It "marks a running service healthy" {
        # Replace Get-Service with a predictable response for this test only.
        Mock Get-Service {
            [pscustomobject]@{ Name = $Name; Status = "Running" }
        }

        # Call the function and assert its returned status fields.
        $result = Get-ServiceHealth -Name "ExampleService"
        $result.Healthy | Should -BeTrue
        $result.Status | Should -Be "Running"
        $result.Found | Should -BeTrue
    }

    It "reports a service query failure without crashing" {
        # Simulate a missing service or a query failure.
        Mock Get-Service { throw "service unavailable" }

        # The function should report the failure as an unhealthy result.
        $result = Get-ServiceHealth -Name "MissingService"
        $result.Found | Should -BeFalse
        $result.Healthy | Should -BeFalse
        $result.Message | Should -Match "Could not query service"
    }
}

Describe "Get-DiskHealth" {
    It "warns when free space is below the configured threshold" {
        # Simulate a 100 GB disk with 10 GB free (10 percent).
        Mock Get-CimInstance {
            [pscustomobject]@{ DeviceID = "C:"; Size = 100GB; FreeSpace = 10GB }
        }

        # With a 15 percent threshold, 10 percent free must be flagged.
        $result = Get-DiskHealth -WarningPercentFree 15
        $result.PercentFree | Should -Be 10
        $result.Healthy | Should -BeFalse
        $result.Message | Should -Be "Low disk space."
    }

    It "marks disk space healthy when it meets the threshold" {
        # Simulate a 100 GB disk with 25 GB free (25 percent).
        Mock Get-CimInstance {
            [pscustomobject]@{ DeviceID = "C:"; Size = 100GB; FreeSpace = 25GB }
        }

        # A disk with 25 percent free meets a 15 percent threshold.
        $result = Get-DiskHealth -WarningPercentFree 15
        $result.Healthy | Should -BeTrue
        $result.PercentFree | Should -Be 25
    }
}

Describe "Get-RecentApplicationErrors" {
    It "returns event details and normalizes whitespace" {
        # Fake one Application log event to make the test deterministic.
        Mock Get-WinEvent {
            @([pscustomobject]@{
                TimeCreated  = [datetime]"2026-01-01T12:00:00"
                ProviderName = "ExampleApp"
                Id           = 1001
                Message      = "  Example   application error  "
            })
        }

        # Check that the function returns the expected fields and cleaned message.
        $result = @(Get-RecentApplicationErrors -Hours 24)
        $result.Count | Should -Be 1
        $result[0].Provider | Should -Be "ExampleApp"
        $result[0].EventId | Should -Be 1001
        $result[0].Message | Should -Be "Example application error"
    }

    It "returns no records when no events match" {
        # Get-WinEvent throws if no events match; simulate that Windows behavior.
        Mock Get-WinEvent {
            throw "No events were found that match the specified selection criteria."
        }

        # The no-events case should be an empty result, not an error record.
        $result = @(Get-RecentApplicationErrors -Hours 24)
        $result.Count | Should -Be 0
    }
}
