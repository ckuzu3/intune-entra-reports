function Get-GraphRequestUri {
    <#
    .SYNOPSIS
        Returns the request URI the module uses for a given Graph resource.

    .DESCRIPTION
        Every report asks Graph for exactly the fields it needs, which keeps responses
        small and makes the required permissions obvious. Those URIs live here instead
        of being spread across the report functions.

        This function is exported on purpose: the fake client matches on the exact URI,
        so tests and anyone building their own fixtures can ask the module for the URI
        rather than copying the string and letting the two drift apart.

    .PARAMETER Resource
        The resource to build a URI for.

    .EXAMPLE
        Get-GraphRequestUri -Resource ManagedDevices

        Returns the managed-device URI including its $select clause.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ManagedDevices', 'SubscribedSkus', 'DisabledUsersWithLicenses')]
        [string]$Resource
    )

    $managedDeviceFields = @(
        'id'
        'deviceName'
        'operatingSystem'
        'osVersion'
        'userPrincipalName'
        'lastSyncDateTime'
        'complianceState'
        'isEncrypted'
        'managedDeviceOwnerType'
    )

    switch ($Resource) {
        'ManagedDevices' {
            return 'deviceManagement/managedDevices?$select=' + ($managedDeviceFields -join ',')
        }
        'SubscribedSkus' {
            return 'subscribedSkus'
        }
        'DisabledUsersWithLicenses' {
            return 'users?$filter=accountEnabled eq false&$select=id,userPrincipalName,assignedLicenses'
        }
    }
}
