function Get-StaleDeviceReport {
    <#
    .SYNOPSIS
        Lists managed devices that have not checked in for a given number of days.

    .DESCRIPTION
        A device that stopped syncing is not a harmless row in a console: it keeps a
        license, it no longer receives policy or patches, and it still counts as managed.
        This report is the list I would work through before a license review or an audit.

        Devices that have never checked in are always included, because a device that was
        enrolled and never reported is at least as interesting as an old one.

    .PARAMETER Client
        A Graph client from New-GraphClient or New-FakeGraphClient.

    .PARAMETER InactiveForDays
        How many days without a check-in make a device stale. Defaults to 30.

    .PARAMETER ReferenceDate
        The point in time the age is measured against. It defaults to now and exists so
        that tests and repeated runs produce the same numbers.

    .EXAMPLE
        Get-StaleDeviceReport -Client $client -InactiveForDays 60

        Lists devices that have been silent for at least 60 days, worst first.

    .OUTPUTS
        IntuneEntraReports.StaleDevice
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('IntuneEntraReports.GraphClient')]
        $Client,

        [ValidateRange(1, 3650)]
        [int]$InactiveForDays = 30,

        [datetime]$ReferenceDate = (Get-Date)
    )

    $reference = $ReferenceDate.ToUniversalTime()
    $devices = Get-GraphCollection -Client $Client -Uri (Get-GraphRequestUri -Resource ManagedDevices)

    $staleDevices = foreach ($device in $devices) {
        $lastSync = ConvertFrom-GraphDateTime -Value (Get-ObjectProperty -InputObject $device -Name 'lastSyncDateTime')
        $hasNeverSynced = $null -eq $lastSync

        if ($hasNeverSynced) {
            $daysSinceLastSync = $null
        }
        else {
            $daysSinceLastSync = [int][math]::Floor(($reference - $lastSync).TotalDays)
            if ($daysSinceLastSync -lt $InactiveForDays) {
                continue
            }
        }

        [pscustomobject]@{
            PSTypeName        = 'IntuneEntraReports.StaleDevice'
            DeviceName        = Get-ObjectProperty -InputObject $device -Name 'deviceName'
            UserPrincipalName = Get-ObjectProperty -InputObject $device -Name 'userPrincipalName'
            OperatingSystem   = Get-ObjectProperty -InputObject $device -Name 'operatingSystem'
            OsVersion         = Get-ObjectProperty -InputObject $device -Name 'osVersion'
            Ownership         = Get-ObjectProperty -InputObject $device -Name 'managedDeviceOwnerType'
            LastSyncDateTime  = $lastSync
            DaysSinceLastSync = $daysSinceLastSync
            HasNeverSynced    = $hasNeverSynced
            DeviceId          = Get-ObjectProperty -InputObject $device -Name 'id'
        }
    }

    # A device that never synced has no measurable age, so it sorts ahead of every other one.
    $sortByAge = @{
        Expression = { if ($null -eq $_.DaysSinceLastSync) { [int]::MaxValue } else { $_.DaysSinceLastSync } }
        Descending = $true
    }

    return $staleDevices | Sort-Object -Property $sortByAge, 'DeviceName'
}
