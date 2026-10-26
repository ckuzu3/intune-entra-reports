function Get-GraphCollection {
    <#
    .SYNOPSIS
        Reads every item of a paged Graph collection.

    .DESCRIPTION
        Graph returns large collections in pages and points at the next one with
        '@odata.nextLink'. This function follows that chain and streams the items of
        each page, so callers never deal with paging themselves.

        MaximumPages is a deliberate stop: a response that links back to itself would
        otherwise loop forever against a live tenant.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('IntuneEntraReports.GraphClient')]
        $Client,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [ValidateRange(1, 10000)]
        [int]$MaximumPages = 200
    )

    $requestUri = $Uri
    $pageNumber = 0

    while (-not [string]::IsNullOrEmpty($requestUri)) {
        $pageNumber++
        if ($pageNumber -gt $MaximumPages) {
            throw "Stopped after $MaximumPages pages while reading '$Uri'. Narrow the query or raise -MaximumPages."
        }

        Write-Verbose "Reading page $pageNumber of '$Uri'."
        $response = & $Client.Invoke $requestUri

        $items = Get-ObjectProperty -InputObject $response -Name 'value'
        if ($null -ne $items) {
            $items
        }

        $requestUri = Get-ObjectProperty -InputObject $response -Name '@odata.nextLink'
    }
}
