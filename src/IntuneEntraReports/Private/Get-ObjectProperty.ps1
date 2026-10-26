function Get-ObjectProperty {
    <#
    .SYNOPSIS
        Reads a property that may be absent and returns $null instead of failing.

    .DESCRIPTION
        Graph omits properties that were not requested with $select, and the module
        runs under Set-StrictMode -Version Latest, where touching an absent property
        is an error. Every read of a Graph field goes through this function so that a
        missing field stays a missing value instead of becoming an exception.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}
