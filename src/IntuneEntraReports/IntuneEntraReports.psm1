Set-StrictMode -Version Latest

$privateFunctions = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$publicFunctions = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($privateFunctions + $publicFunctions)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to load '$($file.FullName)': $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $publicFunctions.BaseName
