function ConvertFrom-GraphDateTime {
    <#
    .SYNOPSIS
        Parses a Graph timestamp into a UTC DateTime, or $null when there is none.

    .DESCRIPTION
        Graph returns ISO 8601 timestamps such as '2026-09-01T07:14:22Z'. Parsing with
        the invariant culture keeps the result identical on a machine with a German
        locale, and RoundtripKind preserves the UTC offset instead of shifting the
        value into local time.

        Devices that have never checked in carry a null or placeholder timestamp, which
        is why an unparsable value returns $null rather than throwing: the caller then
        reports the device as "never synced" instead of losing the whole report.
    #>
    [CmdletBinding()]
    [OutputType([Nullable[datetime]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    [datetime]$parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [datetime]::TryParse([string]$Value, [cultureinfo]::InvariantCulture, $styles, [ref]$parsed)) {
        Write-Verbose "Ignoring unparsable timestamp '$Value'."
        return $null
    }

    if ($parsed -le [datetime]::MinValue.AddDays(1)) {
        return $null
    }

    return $parsed
}
