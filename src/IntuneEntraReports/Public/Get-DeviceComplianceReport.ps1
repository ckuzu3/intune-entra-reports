function Get-DeviceComplianceReport {
    <#
    .SYNOPSIS
        Reports the compliance state of managed devices.

    .DESCRIPTION
        By default the report only returns devices that need attention, because that is the
        list someone has to act on. 'compliant' and 'notApplicable' count as healthy, every
        other state does not, including 'unknown': a device whose state cannot be determined
        is not evidence of compliance.

        Encryption is reported as its own column rather than folded into the compliance
        state. Whether an unencrypted device breaks policy depends on the tenant, so the
        report shows the fact and leaves that judgement to the reader.

    .PARAMETER Client
        A Graph client from New-GraphClient or New-FakeGraphClient.

    .PARAMETER IncludeCompliant
        Also return healthy devices, for a full inventory instead of a worklist.

    .EXAMPLE
        Get-DeviceComplianceReport -Client $client

        Returns only the devices that need attention.

    .EXAMPLE
        Get-DeviceComplianceReport -Client $client -IncludeCompliant |
            Group-Object -Property ComplianceState |
            Select-Object -Property Name, Count

        Turns the full inventory into a count per compliance state.

    .OUTPUTS
        IntuneEntraReports.DeviceCompliance
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('IntuneEntraReports.GraphClient')]
        $Client,

        [switch]$IncludeCompliant
    )

    $healthyStates = @('compliant', 'notApplicable')
    $devices = Get-GraphCollection -Client $Client -Uri (Get-GraphRequestUri -Resource ManagedDevices)

    $results = foreach ($device in $devices) {
        $complianceState = [string](Get-ObjectProperty -InputObject $device -Name 'complianceState')
        if ([string]::IsNullOrWhiteSpace($complianceState)) {
            $complianceState = 'unknown'
        }

        $needsAttention = $healthyStates -notcontains $complianceState
        if (-not $needsAttention -and -not $IncludeCompliant) {
            continue
        }

        [pscustomobject]@{
            PSTypeName        = 'IntuneEntraReports.DeviceCompliance'
            DeviceName        = Get-ObjectProperty -InputObject $device -Name 'deviceName'
            UserPrincipalName = Get-ObjectProperty -InputObject $device -Name 'userPrincipalName'
            OperatingSystem   = Get-ObjectProperty -InputObject $device -Name 'operatingSystem'
            OsVersion         = Get-ObjectProperty -InputObject $device -Name 'osVersion'
            ComplianceState   = $complianceState
            NeedsAttention    = $needsAttention
            IsEncrypted       = [bool](Get-ObjectProperty -InputObject $device -Name 'isEncrypted')
            LastSyncDateTime  = ConvertFrom-GraphDateTime -Value (Get-ObjectProperty -InputObject $device -Name 'lastSyncDateTime')
            DeviceId          = Get-ObjectProperty -InputObject $device -Name 'id'
        }
    }

    $sortByAttention = @{
        Expression = 'NeedsAttention'
        Descending = $true
    }

    return $results | Sort-Object -Property $sortByAttention, 'ComplianceState', 'DeviceName'
}
