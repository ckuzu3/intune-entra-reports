function New-GraphClient {
    <#
    .SYNOPSIS
        Creates a client that reads from Microsoft Graph through an existing session.

    .DESCRIPTION
        The client only reads, and it expects that Connect-MgGraph has already been
        called, so this module never handles credentials itself.

        Relative URIs are resolved against the base URI, absolute ones are passed through
        unchanged. That is what lets paging follow an '@odata.nextLink' without a special
        case.

    .PARAMETER BaseUri
        The Graph endpoint that relative request URIs are resolved against.

    .PARAMETER RequestCommand
        The transport: a script block that takes a full URI and returns the parsed
        response. It defaults to a GET through Invoke-MgGraphRequest. Replacing it routes
        requests through something else, which is how the tests check the URI handling
        without installing the Graph SDK, and what a caller would use to add retries or
        request logging.

    .EXAMPLE
        Connect-MgGraph -Scopes 'DeviceManagementManagedDevices.Read.All','Directory.Read.All'
        $client = New-GraphClient

        Signs in with read-only scopes and creates a live client.

    .EXAMPLE
        $client = New-GraphClient -RequestCommand {
            param([string]$Uri)
            Write-Host "GET $Uri"
            Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject
        }

        Creates a client that logs every request before sending it.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory object and changes no state.')]
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUri = 'https://graph.microsoft.com/v1.0',

        [ValidateNotNull()]
        [scriptblock]$RequestCommand
    )

    if (-not $PSBoundParameters.ContainsKey('RequestCommand')) {
        if (-not (Test-GraphCommandAvailable)) {
            throw 'Invoke-MgGraphRequest was not found. Install the Microsoft.Graph.Authentication module and run Connect-MgGraph first.'
        }

        $RequestCommand = {
            param([string]$Uri)
            Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject
        }
    }

    $endpoint = $BaseUri.TrimEnd('/')

    # GetNewClosure captures variables, not the module's command table, so a closure
    # called from outside the module cannot resolve a module-private function by name.
    # Both things the client needs are therefore captured variables.
    $invoke = {
        param([string]$Uri)

        $requestUri = if ($Uri -match '^https?://') { $Uri } else { '{0}/{1}' -f $endpoint, $Uri.TrimStart('/') }
        return & $RequestCommand $requestUri
    }.GetNewClosure()

    return [pscustomobject]@{
        PSTypeName = 'IntuneEntraReports.GraphClient'
        Name       = $endpoint
        Invoke     = $invoke
    }
}
