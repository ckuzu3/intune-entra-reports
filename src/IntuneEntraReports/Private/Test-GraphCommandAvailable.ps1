function Test-GraphCommandAvailable {
    <#
    .SYNOPSIS
        Tells whether Invoke-MgGraphRequest can be called in this session.

    .DESCRIPTION
        This is a seam, not a convenience wrapper. New-GraphClient has to refuse to build
        a live client when the Microsoft Graph module is missing, and that branch can only
        be tested if the lookup itself can be replaced in a test. A direct Get-Command
        call inside New-GraphClient would make the failure path depend on whatever happens
        to be installed on the machine running the suite.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return $null -ne (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue)
}
