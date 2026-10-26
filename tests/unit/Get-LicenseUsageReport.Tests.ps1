BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../src/IntuneEntraReports/IntuneEntraReports.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath '../TestGraphClient.ps1')

    $client = New-TestGraphClient
}

Describe 'Get-LicenseUsageReport' {
    It 'reports one row per subscribed SKU' {
        $report = Get-LicenseUsageReport -Client $client

        $report.Count | Should -Be 3
        $report.SkuPartNumber | Should -Contain 'SPE_E3'
    }

    It 'calculates available units and utilization from the prepaid units' {
        $report = Get-LicenseUsageReport -Client $client
        $sku = $report | Where-Object -Property SkuPartNumber -EQ -Value 'SPE_E3'

        $sku.EnabledUnits | Should -Be 100
        $sku.ConsumedUnits | Should -Be 95
        $sku.AvailableUnits | Should -Be 5
        $sku.UtilizationPercent | Should -Be 95
        $sku.IsOverAssigned | Should -BeFalse
    }

    It 'flags a SKU that consumes more units than were purchased' {
        $report = Get-LicenseUsageReport -Client $client
        $sku = $report | Where-Object -Property SkuPartNumber -EQ -Value 'EMS'

        $sku.IsOverAssigned | Should -BeTrue
        $sku.AvailableUnits | Should -Be -2
        $sku.UtilizationPercent | Should -Be 104
    }

    It 'counts how many licenses of each SKU are held by disabled accounts' {
        $report = Get-LicenseUsageReport -Client $client

        ($report | Where-Object -Property SkuPartNumber -EQ -Value 'SPE_E3').AssignedToDisabledAccounts | Should -Be 2
        ($report | Where-Object -Property SkuPartNumber -EQ -Value 'EMS').AssignedToDisabledAccounts | Should -Be 1
        ($report | Where-Object -Property SkuPartNumber -EQ -Value 'AAD_PREMIUM_P2').AssignedToDisabledAccounts | Should -Be 0
    }

    It 'ignores disabled accounts that hold no license at all' {
        # The third disabled user in the fixture has an empty assignedLicenses array.
        $report = Get-LicenseUsageReport -Client $client

        ($report | Measure-Object -Property AssignedToDisabledAccounts -Sum).Sum | Should -Be 3
    }

    It 'skips a license assignment that carries no SKU id' {
        $client = New-FakeGraphClient -ResponseMap @{
            (Get-GraphRequestUri -Resource SubscribedSkus)            = [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        skuId         = '00000000-0000-0000-0000-000000000001'
                        skuPartNumber = 'SPE_E3'
                        consumedUnits = 1
                        prepaidUnits  = [pscustomobject]@{ enabled = 10 }
                    }
                )
            }
            (Get-GraphRequestUri -Resource DisabledUsersWithLicenses) = [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        userPrincipalName = 'broken@contoso.example'
                        assignedLicenses  = @([pscustomobject]@{ disabledPlans = @() })
                    }
                )
            }
        }

        $report = Get-LicenseUsageReport -Client $client

        $report.AssignedToDisabledAccounts | Should -Be 0
    }

    It 'sorts the fullest SKU first' {
        $report = Get-LicenseUsageReport -Client $client

        $report.SkuPartNumber | Should -Be @('EMS', 'SPE_E3', 'AAD_PREMIUM_P2')
    }

    It 'leaves utilization empty for a SKU without purchased units instead of dividing by zero' {
        $client = New-FakeGraphClient -ResponseMap @{
            (Get-GraphRequestUri -Resource SubscribedSkus)            = [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        skuId         = '00000000-0000-0000-0000-000000000001'
                        skuPartNumber = 'TRIAL_SKU'
                        consumedUnits = 0
                        prepaidUnits  = [pscustomobject]@{ enabled = 0 }
                    }
                )
            }
            (Get-GraphRequestUri -Resource DisabledUsersWithLicenses) = [pscustomobject]@{ value = @() }
        }

        $report = Get-LicenseUsageReport -Client $client

        $report.UtilizationPercent | Should -BeNullOrEmpty
        $report.IsOverAssigned | Should -BeFalse
    }
}
