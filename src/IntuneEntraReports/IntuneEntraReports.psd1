@{
    RootModule            = 'IntuneEntraReports.psm1'
    ModuleVersion         = '0.1.0'
    GUID                  = 'c2a7f0d4-6b1e-4f3a-9c2d-5e8b7a1d4f60'
    Author                = 'ckuzu3'
    Description           = 'Read-only reports over Microsoft Intune and Entra ID: stale devices, device compliance and license usage.'
    PowerShellVersion     = '5.1'
    CompatiblePSEditions  = @('Desktop', 'Core')

    FunctionsToExport     = @(
        'New-GraphClient',
        'New-FakeGraphClient',
        'Get-GraphRequestUri',
        'Get-StaleDeviceReport',
        'Get-DeviceComplianceReport',
        'Get-LicenseUsageReport',
        'Export-TenantReport'
    )
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Intune', 'EntraID', 'MicrosoftGraph', 'Reporting', 'Compliance')
            LicenseUri = 'https://github.com/ckuzu3/intune-entra-reports/blob/main/LICENSE'
            ProjectUri = 'https://github.com/ckuzu3/intune-entra-reports'
        }
    }
}
