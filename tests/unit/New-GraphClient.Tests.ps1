BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../src/IntuneEntraReports/IntuneEntraReports.psd1'
    Import-Module -Name $modulePath -Force

    # A transport that answers with the URI it was asked for. That makes the URI handling
    # observable without installing the Graph SDK.
    $echoUri = {
        param([string]$Uri)
        return [pscustomobject]@{ value = @($Uri) }
    }
}

Describe 'New-GraphClient' {
    Context 'when the Microsoft Graph module is missing' {
        It 'refuses to build a client and says what to install' {
            Mock -CommandName Test-GraphCommandAvailable -ModuleName IntuneEntraReports -MockWith { $false }

            { New-GraphClient } | Should -Throw -ExpectedMessage '*Microsoft.Graph.Authentication*'
        }

        It 'still builds a client when the caller brings its own transport' {
            Mock -CommandName Test-GraphCommandAvailable -ModuleName IntuneEntraReports -MockWith { $false }

            { New-GraphClient -RequestCommand $echoUri } | Should -Not -Throw
        }
    }

    Context 'URI handling' {
        It 'resolves a relative URI against the default endpoint' {
            $client = New-GraphClient -RequestCommand $echoUri

            (& $client.Invoke 'users').value | Should -Be 'https://graph.microsoft.com/v1.0/users'
        }

        It 'passes an absolute URI through unchanged, which is what paging needs' {
            $client = New-GraphClient -RequestCommand $echoUri
            $nextLink = 'https://graph.microsoft.com/v1.0/users?$skiptoken=abc'

            (& $client.Invoke $nextLink).value | Should -Be $nextLink
        }

        It 'does not produce a double slash when the base URI ends in one' {
            $client = New-GraphClient -BaseUri 'https://graph.microsoft.com/beta/' -RequestCommand $echoUri

            (& $client.Invoke '/users').value | Should -Be 'https://graph.microsoft.com/beta/users'
        }
    }

    Context 'the returned object' {
        It 'reports the endpoint it was built for' {
            $client = New-GraphClient -BaseUri 'https://graph.microsoft.com/beta' -RequestCommand $echoUri

            $client.Name | Should -Be 'https://graph.microsoft.com/beta'
        }

        It 'carries the type name the reports validate against' {
            $client = New-GraphClient -RequestCommand $echoUri

            $client.PSObject.TypeNames | Should -Contain 'IntuneEntraReports.GraphClient'
        }

        It 'works as the client for a real report' {
            $devices = [pscustomobject]@{
                value = @([pscustomobject]@{ id = '1'; deviceName = 'WS-0001'; complianceState = 'noncompliant' })
            }
            $client = New-GraphClient -RequestCommand {
                param([string]$Uri)
                if ($Uri -notlike '*deviceManagement/managedDevices*') {
                    throw "The report asked for an unexpected resource: $Uri"
                }
                return $devices
            }.GetNewClosure()

            (Get-DeviceComplianceReport -Client $client).DeviceName | Should -Be 'WS-0001'
        }

        It 'rejects an empty base URI' {
            { New-GraphClient -BaseUri '' -RequestCommand $echoUri } | Should -Throw
        }
    }
}
