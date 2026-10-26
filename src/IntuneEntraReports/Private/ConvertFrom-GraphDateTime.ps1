function ConvertFrom-GraphDateTime {
    <#
    .SYNOPSIS
        Parses a Graph timestamp into a UTC DateTime, or $null when there is none.

    .DESCRIPTION
        Graph returns ISO 8601 timestamps such as '2026-09-01T07:14:22Z'. Parsing with the
        invariant culture keeps the result identical on a machine with a German locale,
        and the result is normalised to UTC so that an age in days never depends on the
        time zone the report happened to run in.

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
    # AssumeUniversal covers the rare timestamp that arrives without a 'Z', and
    # AdjustToUniversal makes sure the result is UTC rather than the machine's local time.
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [datetime]::TryParse([string]$Value, [cultureinfo]::InvariantCulture, $styles, [ref]$parsed)) {
        Write-Verbose "Ignoring unparsable timestamp '$Value'."
        return $null
    }

    if ($parsed -le [datetime]::MinValue.AddDays(1)) {
        return $null
    }

    return $parsed
}
