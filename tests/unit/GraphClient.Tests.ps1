BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../src/IntuneEntraReports/IntuneEntraReports.psd1'
    Import-Module -Name $modulePath -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath '../TestGraphClient.ps1')
}

Describe 'New-FakeGraphClient' {
    It 'returns the registered response for a known URI' {
        $client = New-FakeGraphClient -ResponseMap @{ 'ping' = [pscustomobject]@{ value = @('pong') } }

        $response = & $client.Invoke 'ping'

        $response.value | Should -Be 'pong'
    }

    It 'loads a response from a JSON fixture when the value is a path' {
        $client = New-FakeGraphClient -ResponseMap @{ 'devices' = (Get-FixturePath 'managedDevices.page1.json') }

        $response = & $client.Invoke 'devices'

        $response.value.Count | Should -Be 3
    }

    It 'fails with a helpful message when a fixture path does not exist' {
        { New-FakeGraphClient -ResponseMap @{ 'devices' = './does-not-exist.json' } } |
            Should -Throw -ExpectedMessage '*does not exist*'
    }

    It 'names the registered URIs when an unexpected URI is requested' {
        $client = New-FakeGraphClient -ResponseMap @{ 'ping' = [pscustomobject]@{ value = @() } }

        { & $client.Invoke 'pong' } | Should -Throw -ExpectedMessage '*Registered URIs: ping*'
    }

    It 'carries the type name the report functions validate against' {
        $client = New-FakeGraphClient -ResponseMap @{ 'ping' = [pscustomobject]@{ value = @() } }

        $client.PSObject.TypeNames | Should -Contain 'IntuneEntraReports.GraphClient'
    }
}

Describe 'Get-GraphRequestUri' {
    It 'asks only for the managed-device fields the reports use' {
        Get-GraphRequestUri -Resource ManagedDevices |
            Should -Be 'deviceManagement/managedDevices?$select=id,deviceName,operatingSystem,osVersion,userPrincipalName,lastSyncDateTime,complianceState,isEncrypted,managedDeviceOwnerType'
    }

    It 'filters users down to disabled accounts' {
        Get-GraphRequestUri -Resource DisabledUsersWithLicenses | Should -BeLike '*$filter=accountEnabled eq false*'
    }

    It 'rejects an unknown resource' {
        { Get-GraphRequestUri -Resource 'Mailboxes' } | Should -Throw
    }
}

Describe 'Get-GraphCollection' {
    BeforeAll {
        $pagedClient = New-TestGraphClient
        $managedDevicesUri = Get-GraphRequestUri -Resource ManagedDevices
    }

    It 'follows @odata.nextLink and returns the items of every page' {
        $devices = InModuleScope IntuneEntraReports -Parameters @{ Client = $pagedClient; Uri = $managedDevicesUri } {
            param($Client, $Uri)
            Get-GraphCollection -Client $Client -Uri $Uri
        }

        $devices.Count | Should -Be 5
        $devices[0].deviceName | Should -Be 'WS-0001'
        $devices[-1].deviceName | Should -Be 'MAC-0001'
    }

    It 'returns nothing for an empty collection' {
        $client = New-FakeGraphClient -ResponseMap @{ 'empty' = [pscustomobject]@{ value = @() } }

        $items = InModuleScope IntuneEntraReports -Parameters @{ Client = $client } {
            param($Client)
            Get-GraphCollection -Client $Client -Uri 'empty'
        }

        $items | Should -BeNullOrEmpty
    }

    It 'tolerates a response without a value property' {
        $client = New-FakeGraphClient -ResponseMap @{ 'odd' = [pscustomobject]@{ status = 'ok' } }

        {
            InModuleScope IntuneEntraReports -Parameters @{ Client = $client } {
                param($Client)
                Get-GraphCollection -Client $Client -Uri 'odd'
            }
        } | Should -Not -Throw
    }

    It 'stops instead of looping forever when a page links to itself' {
        $client = New-FakeGraphClient -ResponseMap @{
            'loop' = [pscustomobject]@{
                value             = @([pscustomobject]@{ id = 1 })
                '@odata.nextLink' = 'loop'
            }
        }

        {
            InModuleScope IntuneEntraReports -Parameters @{ Client = $client } {
                param($Client)
                Get-GraphCollection -Client $Client -Uri 'loop' -MaximumPages 5
            }
        } | Should -Throw -ExpectedMessage '*Stopped after 5 pages*'
    }
}
