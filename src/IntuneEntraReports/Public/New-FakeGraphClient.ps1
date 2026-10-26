function New-FakeGraphClient {
    <#
    .SYNOPSIS
        Creates an offline Graph client that answers from a fixed set of responses.

    .DESCRIPTION
        The fake client implements the same contract as New-GraphClient but serves
        pre-recorded responses instead of calling Microsoft Graph. It is what the
        unit tests run against, and it lets anyone try the reports out without a
        tenant.

        A response is either a JSON file path or an object that is returned as-is.
        Lookup is an exact match on the request URI, so paging can be modelled by
        pointing the '@odata.nextLink' of one response at the key of the next.

    .PARAMETER ResponseMap
        Maps a request URI to either the path of a JSON fixture file or an object.

    .EXAMPLE
        $client = New-FakeGraphClient -ResponseMap @{
            'deviceManagement/managedDevices' = './tests/fixtures/managedDevices.page1.json'
        }

        Builds a client that answers a single managed-device request from disk.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory object and changes no state.')]
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResponseMap
    )

    $responses = @{}
    foreach ($uri in $ResponseMap.Keys) {
        $response = $ResponseMap[$uri]
        if ($response -is [string]) {
            if (-not (Test-Path -LiteralPath $response)) {
                throw "Fixture '$response' registered for URI '$uri' does not exist."
            }
            $responses[$uri] = Get-Content -LiteralPath $response -Raw | ConvertFrom-Json
        }
        else {
            $responses[$uri] = $response
        }
    }

    $invoke = {
        param([string]$Uri)

        if (-not $responses.ContainsKey($Uri)) {
            $known = ($responses.Keys | Sort-Object) -join ', '
            throw "The fake Graph client has no response for '$Uri'. Registered URIs: $known"
        }

        return $responses[$Uri]
    }.GetNewClosure()

    return [pscustomobject]@{
        PSTypeName = 'IntuneEntraReports.GraphClient'
        Name       = 'fake'
        Invoke     = $invoke
    }
}
