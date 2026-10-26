BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../src/IntuneEntraReports/IntuneEntraReports.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath '../TestGraphClient.ps1')

    $referenceDate = [datetime]::SpecifyKind([datetime]::new(2026, 10, 20, 0, 0, 0), [System.DateTimeKind]::Utc)
    $client = New-TestGraphClient
}

Describe 'Export-TenantReport' {
    BeforeEach {
        $outputPath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
    }

    It 'creates the output folder when it does not exist yet' {
        Export-TenantReport -Client $client -Path $outputPath -ReferenceDate $referenceDate | Out-Null

        Test-Path -LiteralPath $outputPath | Should -BeTrue
    }

    It 'writes one CSV per report and one HTML page by default' {
        Export-TenantReport -Client $client -Path $outputPath -ReferenceDate $referenceDate | Out-Null

        $written = Get-ChildItem -LiteralPath $outputPath | Select-Object -ExpandProperty Name | Sort-Object

        $written | Should -Be @('device-compliance.csv', 'index.html', 'license-usage.csv', 'stale-devices.csv')
    }

    It 'returns the files it wrote' {
        $result = Export-TenantReport -Client $client -Path $outputPath -Format Csv -ReferenceDate $referenceDate

        $result.Count | Should -Be 3
        $result | ForEach-Object { $_ | Should -BeOfType [System.IO.FileInfo] }
    }

    It 'writes nothing when called with WhatIf' {
        $result = Export-TenantReport -Client $client -Path $outputPath -ReferenceDate $referenceDate -WhatIf

        $result | Should -BeNullOrEmpty
        Test-Path -LiteralPath $outputPath | Should -BeFalse
    }

    It 'writes JSON that parses back into an array' {
        Export-TenantReport -Client $client -Path $outputPath -Format Json -ReferenceDate $referenceDate | Out-Null

        $json = Get-Content -LiteralPath (Join-Path $outputPath 'stale-devices.json') -Raw | ConvertFrom-Json

        @($json).Count | Should -Be 3
        @($json).DeviceName | Should -Contain 'WS-0003'
    }

    It 'honours the requested CSV delimiter' {
        Export-TenantReport -Client $client -Path $outputPath -Format Csv -CsvDelimiter ';' -ReferenceDate $referenceDate | Out-Null

        $header = Get-Content -LiteralPath (Join-Path $outputPath 'license-usage.csv') -TotalCount 1

        $header | Should -BeLike '*;*'
        $header | Should -Not -BeLike '*,*'
    }

    It 'carries the reference date and the threshold into the HTML page' {
        Export-TenantReport -Client $client -Path $outputPath -Format Html -InactiveForDays 45 -ReferenceDate $referenceDate | Out-Null

        $html = Get-Content -LiteralPath (Join-Path $outputPath 'index.html') -Raw

        $html | Should -BeLike '*2026-10-20 00:00:00 UTC*'
        $html | Should -BeLike '*stale after 45 days*'
    }

    It 'encodes device names that contain HTML characters' {
        $hostileClient = New-FakeGraphClient -ResponseMap @{
            (Get-GraphRequestUri -Resource ManagedDevices)            = [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        id               = '1'
                        deviceName       = 'Test & <Lab>'
                        complianceState  = 'noncompliant'
                        lastSyncDateTime = '2026-01-01T00:00:00Z'
                    }
                )
            }
            (Get-GraphRequestUri -Resource SubscribedSkus)            = [pscustomobject]@{ value = @() }
            (Get-GraphRequestUri -Resource DisabledUsersWithLicenses) = [pscustomobject]@{ value = @() }
        }

        Export-TenantReport -Client $hostileClient -Path $outputPath -Format Html -ReferenceDate $referenceDate | Out-Null
        $html = Get-Content -LiteralPath (Join-Path $outputPath 'index.html') -Raw

        $html | Should -BeLike '*Test &amp; &lt;Lab&gt;*'
        $html | Should -Not -BeLike '*<Lab>*'
    }

    It 'reports an empty section instead of an empty table' {
        $emptyClient = New-FakeGraphClient -ResponseMap @{
            (Get-GraphRequestUri -Resource ManagedDevices)            = [pscustomobject]@{ value = @() }
            (Get-GraphRequestUri -Resource SubscribedSkus)            = [pscustomobject]@{ value = @() }
            (Get-GraphRequestUri -Resource DisabledUsersWithLicenses) = [pscustomobject]@{ value = @() }
        }

        Export-TenantReport -Client $emptyClient -Path $outputPath -Format Html -ReferenceDate $referenceDate | Out-Null
        $html = Get-Content -LiteralPath (Join-Path $outputPath 'index.html') -Raw

        $html | Should -BeLike '*Nothing to report*'
    }

    It 'rejects a format it cannot write' {
        { Export-TenantReport -Client $client -Path $outputPath -Format 'Pdf' } | Should -Throw
    }
}
