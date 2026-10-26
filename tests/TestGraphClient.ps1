# Builds the fake Graph client the unit tests share. Keeping it here means a change to
# a fixture file or a request URI is made in one place instead of in every test file.

function Get-FixturePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return (Join-Path -Path $PSScriptRoot -ChildPath "fixtures/$Name")
}

function New-TestGraphClient {
    [CmdletBinding()]
    [OutputType([psobject])]
    param()

    $managedDevicesUri = Get-GraphRequestUri -Resource ManagedDevices
    $firstPage = Get-Content -LiteralPath (Get-FixturePath 'managedDevices.page1.json') -Raw | ConvertFrom-Json
    $secondPageUri = $firstPage.'@odata.nextLink'

    return New-FakeGraphClient -ResponseMap @{
        $managedDevicesUri                                            = Get-FixturePath 'managedDevices.page1.json'
        $secondPageUri                                                = Get-FixturePath 'managedDevices.page2.json'
        (Get-GraphRequestUri -Resource SubscribedSkus)                = Get-FixturePath 'subscribedSkus.json'
        (Get-GraphRequestUri -Resource DisabledUsersWithLicenses)     = Get-FixturePath 'disabledUsers.json'
    }
}
