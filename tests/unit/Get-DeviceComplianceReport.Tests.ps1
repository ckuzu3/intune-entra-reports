BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../src/IntuneEntraReports/IntuneEntraReports.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath '../TestGraphClient.ps1')

    $client = New-TestGraphClient
}

Describe 'Get-DeviceComplianceReport' {
    It 'returns only the devices that need attention by default' {
        $report = Get-DeviceComplianceReport -Client $client

        $report.DeviceName | Should -Be @('WS-0004', 'WS-0002', 'WS-0003')
    }

    It 'treats an unknown compliance state as needing attention' {
        $report = Get-DeviceComplianceReport -Client $client
        $device = $report | Where-Object -Property DeviceName -EQ -Value 'WS-0003'

        $device.ComplianceState | Should -Be 'unknown'
        $device.NeedsAttention | Should -BeTrue
    }

    It 'treats notApplicable as healthy and leaves it out of the worklist' {
        $report = Get-DeviceComplianceReport -Client $client

        $report.DeviceName | Should -Not -Contain 'MAC-0001'
    }

    It 'returns every device when IncludeCompliant is set' {
        $report = Get-DeviceComplianceReport -Client $client -IncludeCompliant

        $report.Count | Should -Be 5
        ($report | Where-Object -Property NeedsAttention -EQ -Value $false).DeviceName |
            Should -Be @('WS-0001', 'MAC-0001')
    }

    It 'sorts the devices that need attention to the top' {
        $report = Get-DeviceComplianceReport -Client $client -IncludeCompliant

        $report[0].NeedsAttention | Should -BeTrue
        $report[-1].NeedsAttention | Should -BeFalse
    }

    It 'reports encryption separately from the compliance state' {
        $report = Get-DeviceComplianceReport -Client $client -IncludeCompliant

        ($report | Where-Object -Property DeviceName -EQ -Value 'WS-0002').IsEncrypted | Should -BeFalse
        ($report | Where-Object -Property DeviceName -EQ -Value 'WS-0004').IsEncrypted | Should -BeTrue
    }

    It 'falls back to unknown when Graph returns no compliance state' {
        $client = New-FakeGraphClient -ResponseMap @{
            (Get-GraphRequestUri -Resource ManagedDevices) = [pscustomobject]@{
                value = @([pscustomobject]@{ id = '1'; deviceName = 'WS-9999' })
            }
        }

        $report = Get-DeviceComplianceReport -Client $client

        $report.ComplianceState | Should -Be 'unknown'
        $report.NeedsAttention | Should -BeTrue
        $report.IsEncrypted | Should -BeFalse
    }

    It 'returns nothing when the tenant has no managed devices' {
        $client = New-FakeGraphClient -ResponseMap @{
            (Get-GraphRequestUri -Resource ManagedDevices) = [pscustomobject]@{ value = @() }
        }

        Get-DeviceComplianceReport -Client $client | Should -BeNullOrEmpty
    }
}
