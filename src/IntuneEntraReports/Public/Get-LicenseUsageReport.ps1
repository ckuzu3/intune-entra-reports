function Get-LicenseUsageReport {
    <#
    .SYNOPSIS
        Reports license consumption per SKU, including licenses held by disabled accounts.

    .DESCRIPTION
        Consumed against purchased units is the number the subscription page already shows.
        The column that makes this report worth running is AssignedToDisabledAccounts:
        licenses still attached to blocked accounts are the cheapest ones to reclaim, and
        they are not summed up per SKU anywhere in the portal.

        Over-assignment is reported instead of hidden, because consumed units can exceed
        purchased units while a subscription sits in its grace period.

    .PARAMETER Client
        A Graph client from New-GraphClient or New-FakeGraphClient.

    .EXAMPLE
        Get-LicenseUsageReport -Client $client |
            Where-Object -Property AssignedToDisabledAccounts -GT -Value 0

        Shows only the SKUs that have licenses to reclaim.

    .OUTPUTS
        IntuneEntraReports.LicenseUsage
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('IntuneEntraReports.GraphClient')]
        $Client
    )

    $subscribedSkus = Get-GraphCollection -Client $Client -Uri (Get-GraphRequestUri -Resource SubscribedSkus)
    $disabledUsers = Get-GraphCollection -Client $Client -Uri (Get-GraphRequestUri -Resource DisabledUsersWithLicenses)

    $disabledAssignmentsPerSku = @{}
    foreach ($user in $disabledUsers) {
        $assignedLicenses = Get-ObjectProperty -InputObject $user -Name 'assignedLicenses'
        if ($null -eq $assignedLicenses) {
            continue
        }

        foreach ($license in $assignedLicenses) {
            $assignedSkuId = [string](Get-ObjectProperty -InputObject $license -Name 'skuId')
            if ([string]::IsNullOrWhiteSpace($assignedSkuId)) {
                continue
            }

            if ($disabledAssignmentsPerSku.ContainsKey($assignedSkuId)) {
                $disabledAssignmentsPerSku[$assignedSkuId]++
            }
            else {
                $disabledAssignmentsPerSku[$assignedSkuId] = 1
            }
        }
    }

    $results = foreach ($sku in $subscribedSkus) {
        $skuId = [string](Get-ObjectProperty -InputObject $sku -Name 'skuId')
        $prepaidUnits = Get-ObjectProperty -InputObject $sku -Name 'prepaidUnits'
        $enabledUnits = [int](Get-ObjectProperty -InputObject $prepaidUnits -Name 'enabled')
        $consumedUnits = [int](Get-ObjectProperty -InputObject $sku -Name 'consumedUnits')

        if ($enabledUnits -gt 0) {
            $utilizationPercent = [math]::Round(($consumedUnits / $enabledUnits) * 100, 1)
        }
        else {
            $utilizationPercent = $null
        }

        $assignedToDisabledAccounts = 0
        if ($disabledAssignmentsPerSku.ContainsKey($skuId)) {
            $assignedToDisabledAccounts = $disabledAssignmentsPerSku[$skuId]
        }

        [pscustomobject]@{
            PSTypeName                 = 'IntuneEntraReports.LicenseUsage'
            SkuPartNumber              = Get-ObjectProperty -InputObject $sku -Name 'skuPartNumber'
            SkuId                      = $skuId
            EnabledUnits               = $enabledUnits
            ConsumedUnits              = $consumedUnits
            AvailableUnits             = $enabledUnits - $consumedUnits
            AssignedToDisabledAccounts = $assignedToDisabledAccounts
            UtilizationPercent         = $utilizationPercent
            IsOverAssigned             = $consumedUnits -gt $enabledUnits
        }
    }

    # A SKU without purchased units has no utilization, so it sorts last instead of first.
    $sortByUtilization = @{
        Expression = { if ($null -eq $_.UtilizationPercent) { -1 } else { $_.UtilizationPercent } }
        Descending = $true
    }

    return $results | Sort-Object -Property $sortByUtilization, 'SkuPartNumber'
}
