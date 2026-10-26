function New-GraphClient {
    <#
    .SYNOPSIS
        Creates a client that reads from Microsoft Graph through an existing session.

    .DESCRIPTION
        The client is a thin wrapper around Invoke-MgGraphRequest. It only reads,
        and it expects that Connect-MgGraph has already been called, so this module
        never handles credentials itself.

        Relative URIs are resolved against the base URI, absolute ones are passed
        through unchanged. That is what lets paging follow an '@odata.nextLink'
        without special cases.

    .PARAMETER BaseUri
        The Graph endpoint that relative request URIs are resolved against.

    .EXAMPLE
        Connect-MgGraph -Scopes 'DeviceManagementManagedDevices.Read.All','Directory.Read.All'
        $client = New-GraphClient

        Signs in with read-only scopes and creates a live client.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUri = 'https://graph.microsoft.com/v1.0'
    )

    if (-not (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue)) {
        throw 'Invoke-MgGraphRequest was not found. Install the Microsoft.Graph.Authentication module and run Connect-MgGraph first.'
    }

    $endpoint = $BaseUri.TrimEnd('/')

    $invoke = {
        param([string]$Uri)

        $requestUri = if ($Uri -match '^https?://') { $Uri } else { '{0}/{1}' -f $endpoint, $Uri.TrimStart('/') }
        return Invoke-MgGraphRequest -Method GET -Uri $requestUri -OutputType PSObject
    }.GetNewClosure()

    return [pscustomobject]@{
        PSTypeName = 'IntuneEntraReports.GraphClient'
        Name       = $endpoint
        Invoke     = $invoke
    }
}
