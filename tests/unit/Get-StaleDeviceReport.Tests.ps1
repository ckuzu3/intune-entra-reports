BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../src/IntuneEntraReports/IntuneEntraReports.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath '../TestGraphClient.ps1')

    # Every expectation below is measured against this fixed point, so the numbers stay
    # the same no matter when the suite runs.
    $referenceDate = [datetime]::SpecifyKind([datetime]::new(2026, 10, 20, 0, 0, 0), [System.DateTimeKind]::Utc)
    $client = New-TestGraphClient
}

Describe 'Get-StaleDeviceReport' {
    It 'returns only devices that are past the threshold' {
        $report = Get-StaleDeviceReport -Client $client -InactiveForDays 30 -ReferenceDate $referenceDate

        $report.DeviceName | Should -Be @('WS-0003', 'WS-0004', 'WS-0002')
    }

    It 'measures the age in whole days against the reference date' {
        $report = Get-StaleDeviceReport -Client $client -InactiveForDays 30 -ReferenceDate $referenceDate

        ($report | Where-Object -Property DeviceName -EQ -Value 'WS-0002').DaysSinceLastSync | Should -Be 48
        ($report | Where-Object -Property DeviceName -EQ -Value 'WS-0004').DaysSinceLastSync | Should -Be 65
    }

    It 'keeps a device that has never synced and leaves its age empty' {
        $report = Get-StaleDeviceReport -Client $client -InactiveForDays 30 -ReferenceDate $referenceDate
        $neverSynced = $report | Where-Object -Property HasNeverSynced -EQ -Value $true

        $neverSynced.DeviceName | Should -Be 'WS-0003'
        $neverSynced.DaysSinceLastSync | Should -BeNullOrEmpty
        $neverSynced.LastSyncDateTime | Should -BeNullOrEmpty
    }

    It 'sorts the never-synced device ahead of the oldest measured one' {
        $report = Get-StaleDeviceReport -Client $client -InactiveForDays 30 -ReferenceDate $referenceDate

        $report[0].DeviceName | Should -Be 'WS-0003'
        $report[1].DeviceName | Should -Be 'WS-0004'
    }

    It 'excludes devices that synced recently' {
        $report = Get-StaleDeviceReport -Client $client -InactiveForDays 30 -ReferenceDate $referenceDate

        $report.DeviceName | Should -Not -Contain 'WS-0001'
        $report.DeviceName | Should -Not -Contain 'MAC-0001'
    }

    It 'returns fewer devices when the threshold is raised' {
        $report = Get-StaleDeviceReport -Client $client -InactiveForDays 60 -ReferenceDate $referenceDate

        $report.DeviceName | Should -Be @('WS-0003', 'WS-0004')
    }

    It 'reads devices from every page of the collection' {
        # WS-0004 only exists on the second page, so finding it proves paging was followed.
        $report = Get-StaleDeviceReport -Client $client -InactiveForDays 30 -ReferenceDate $referenceDate

        $report.DeviceName | Should -Contain 'WS-0004'
    }

    It 'carries the owner and operating system of the device' {
        $report = Get-StaleDeviceReport -Client $client -InactiveForDays 30 -ReferenceDate $referenceDate
        $device = $report | Where-Object -Property DeviceName -EQ -Value 'WS-0004'

        $device.Ownership | Should -Be 'personal'
        $device.OperatingSystem | Should -Be 'Windows'
        $device.UserPrincipalName | Should -Be 'dave@contoso.example'
    }

    It 'rejects a threshold of zero days' {
        { Get-StaleDeviceReport -Client $client -InactiveForDays 0 } | Should -Throw
    }

    It 'rejects an object that is not a Graph client' {
        { Get-StaleDeviceReport -Client ([pscustomobject]@{ Invoke = { } }) } | Should -Throw
    }
}
