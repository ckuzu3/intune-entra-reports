BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../src/IntuneEntraReports/IntuneEntraReports.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'Get-ObjectProperty' {
    It 'returns the value when the property exists' {
        InModuleScope IntuneEntraReports {
            Get-ObjectProperty -InputObject ([pscustomobject]@{ deviceName = 'WS-0001' }) -Name 'deviceName' |
                Should -Be 'WS-0001'
        }
    }

    It 'returns nothing when the property was not selected' {
        InModuleScope IntuneEntraReports {
            Get-ObjectProperty -InputObject ([pscustomobject]@{ id = '1' }) -Name 'deviceName' |
                Should -BeNullOrEmpty
        }
    }

    It 'returns nothing for a null object' {
        InModuleScope IntuneEntraReports {
            Get-ObjectProperty -InputObject $null -Name 'deviceName' | Should -BeNullOrEmpty
        }
    }

    It 'returns a null property value without failing under StrictMode' {
        InModuleScope IntuneEntraReports {
            Get-ObjectProperty -InputObject ([pscustomobject]@{ lastSyncDateTime = $null }) -Name 'lastSyncDateTime' |
                Should -BeNullOrEmpty
        }
    }
}

Describe 'ConvertFrom-GraphDateTime' {
    It 'parses an ISO 8601 timestamp into UTC' {
        InModuleScope IntuneEntraReports {
            $parsed = ConvertFrom-GraphDateTime -Value '2026-09-01T07:14:22Z'

            $parsed.Kind | Should -Be 'Utc'
            $parsed.ToString('yyyy-MM-dd HH:mm:ss') | Should -Be '2026-09-01 07:14:22'
        }
    }

    It 'treats a timestamp without a zone as UTC rather than local time' {
        InModuleScope IntuneEntraReports {
            $parsed = ConvertFrom-GraphDateTime -Value '2026-09-01T07:14:22'

            $parsed.ToString('yyyy-MM-dd HH:mm:ss') | Should -Be '2026-09-01 07:14:22'
        }
    }

    It 'returns nothing for a value that is missing or blank' -ForEach @(
        @{ Value = $null }
        @{ Value = '' }
        @{ Value = '   ' }
    ) {
        InModuleScope IntuneEntraReports -Parameters @{ Value = $Value } {
            param($Value)
            ConvertFrom-GraphDateTime -Value $Value | Should -BeNullOrEmpty
        }
    }

    It 'returns nothing instead of throwing on an unparsable value' {
        InModuleScope IntuneEntraReports {
            ConvertFrom-GraphDateTime -Value 'never' | Should -BeNullOrEmpty
        }
    }

    It 'treats the placeholder date Graph uses for "never" as no date at all' {
        InModuleScope IntuneEntraReports {
            ConvertFrom-GraphDateTime -Value '0001-01-01T00:00:00Z' | Should -BeNullOrEmpty
        }
    }
}
