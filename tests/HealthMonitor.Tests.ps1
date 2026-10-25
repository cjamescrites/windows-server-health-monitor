BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\HealthMonitor.ps1"
    . $scriptPath -NoRun
}

Describe "HealthMonitor syntax" {
    It "parses without syntax errors" {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path $scriptPath),
            [ref]$tokens,
            [ref]$parseErrors
        ) | Out-Null
        $parseErrors.Count | Should -Be 0
    }
}

Describe "Get-ServiceHealth" {
    It "marks a running service healthy" {
        Mock Get-Service { [pscustomobject]@{ Name = $Name; Status = "Running" } }
        $result = Get-ServiceHealth -Name "ExampleService"
        $result.Healthy | Should -BeTrue
        $result.Status | Should -Be "Running"
    }

    It "reports a service query failure without crashing" {
        Mock Get-Service { throw "service unavailable" }
        $result = Get-ServiceHealth -Name "MissingService"
        $result.Found | Should -BeFalse
        $result.Healthy | Should -BeFalse
        $result.Message | Should -Match "Could not query service"
    }
}

Describe "Get-DiskHealth" {
    It "warns when free space is below the configured threshold" {
        Mock Get-CimInstance {
            [pscustomobject]@{ DeviceID = "C:"; Size = 100GB; FreeSpace = 10GB }
        }
        $result = Get-DiskHealth -WarningPercentFree 15
        $result.PercentFree | Should -Be 10
        $result.Healthy | Should -BeFalse
    }

    It "marks disk space healthy when it meets the threshold" {
        Mock Get-CimInstance {
            [pscustomobject]@{ DeviceID = "C:"; Size = 100GB; FreeSpace = 25GB }
        }
        $result = Get-DiskHealth -WarningPercentFree 15
        $result.Healthy | Should -BeTrue
    }
}

Describe "Get-RecentApplicationErrors" {
    It "returns selected event details" {
        Mock Get-WinEvent {
            @([pscustomobject]@{
                TimeCreated = [datetime]"2026-01-01T12:00:00"
                ProviderName = "ExampleApp"
                Id = 1001
                Message = "  Example   application error  "
            })
        }
        $result = @(Get-RecentApplicationErrors -Hours 24)
        $result.Count | Should -Be 1
        $result[0].Provider | Should -Be "ExampleApp"
        $result[0].EventId | Should -Be 1001
        $result[0].Message | Should -Be "Example application error"
    }

    It "returns no records when the log has no matching events" {
        Mock Get-WinEvent { throw "No events were found that match the specified selection criteria." }
        $result = @(Get-RecentApplicationErrors -Hours 24)
        $result.Count | Should -Be 0
    }
}
