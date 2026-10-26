function Export-TenantReport {
    <#
    .SYNOPSIS
        Runs every report once and writes the results to a folder.

    .DESCRIPTION
        This is the entry point I would put behind a scheduled task: one call collects
        the stale devices, the compliance worklist and the license usage, then writes
        them as CSV for further processing, JSON for other tools and a single HTML page
        for people who just want to look at it.

        The HTML page is built with ConvertTo-Html rather than string concatenation, so
        a device name containing '&' or '<' cannot break the markup.

        Nothing is written without -Confirm support, and -WhatIf lists the files that
        would be created, which is the behaviour I want from anything that runs
        unattended.

    .PARAMETER Client
        A Graph client from New-GraphClient or New-FakeGraphClient.

    .PARAMETER Path
        The output folder. It is created if it does not exist.

    .PARAMETER Format
        Which formats to write. Defaults to CSV and HTML.

    .PARAMETER InactiveForDays
        How many days without a check-in make a device stale. Defaults to 30.

    .PARAMETER ReferenceDate
        The point in time the device ages are measured against, and the "as of" date
        shown on the HTML page. Defaults to now.

    .PARAMETER CsvDelimiter
        The CSV field separator. Defaults to a comma; a semicolon opens directly in a
        German or Swiss Excel without an import dialog.

    .EXAMPLE
        Export-TenantReport -Client $client -Path ./out

        Writes three CSV files and one HTML page into ./out.

    .EXAMPLE
        Export-TenantReport -Client $client -Path ./out -Format Json -WhatIf

        Shows which JSON files would be written without creating anything.

    .OUTPUTS
        System.IO.FileInfo
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('IntuneEntraReports.GraphClient')]
        $Client,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [ValidateSet('Csv', 'Json', 'Html')]
        [string[]]$Format = @('Csv', 'Html'),

        [ValidateRange(1, 3650)]
        [int]$InactiveForDays = 30,

        [datetime]$ReferenceDate = (Get-Date),

        [ValidateSet(',', ';')]
        [string]$CsvDelimiter = ','
    )

    $sections = [ordered]@{
        'stale-devices'     = @{
            Title = "Devices with no check-in for $InactiveForDays days or more"
            Rows  = @(Get-StaleDeviceReport -Client $Client -InactiveForDays $InactiveForDays -ReferenceDate $ReferenceDate)
        }
        'device-compliance' = @{
            Title = 'Devices that need attention'
            Rows  = @(Get-DeviceComplianceReport -Client $Client)
        }
        'license-usage'     = @{
            Title = 'License usage per SKU'
            Rows  = @(Get-LicenseUsageReport -Client $Client)
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, 'Create output folder')) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
    }

    $writtenFiles = [System.Collections.Generic.List[string]]::new()

    foreach ($name in $sections.Keys) {
        $rows = $sections[$name].Rows

        if ($Format -contains 'Csv') {
            $csvPath = Join-Path -Path $Path -ChildPath "$name.csv"
            if ($PSCmdlet.ShouldProcess($csvPath, 'Write CSV report')) {
                $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -Delimiter $CsvDelimiter
                $writtenFiles.Add($csvPath)
            }
        }

        if ($Format -contains 'Json') {
            $jsonPath = Join-Path -Path $Path -ChildPath "$name.json"
            if ($PSCmdlet.ShouldProcess($jsonPath, 'Write JSON report')) {
                # ConvertTo-Json flattens a single object into an object rather than an
                # array, so the depth and the array wrapper are both explicit here.
                ConvertTo-Json -InputObject @($rows) -Depth 4 |
                    Set-Content -LiteralPath $jsonPath -Encoding UTF8
                $writtenFiles.Add($jsonPath)
            }
        }
    }

    if ($Format -contains 'Html') {
        $htmlPath = Join-Path -Path $Path -ChildPath 'index.html'
        if ($PSCmdlet.ShouldProcess($htmlPath, 'Write HTML summary')) {
            $html = ConvertTo-TenantReportHtml -Sections $sections -ReferenceDate $ReferenceDate -InactiveForDays $InactiveForDays
            Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8
            $writtenFiles.Add($htmlPath)
        }
    }

    foreach ($file in $writtenFiles) {
        Get-Item -LiteralPath $file
    }
}
