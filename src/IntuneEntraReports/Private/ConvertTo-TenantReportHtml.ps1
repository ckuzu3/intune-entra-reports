function ConvertTo-TenantReportHtml {
    <#
    .SYNOPSIS
        Renders the report sections as a single self-contained HTML page.

    .DESCRIPTION
        The tables come from ConvertTo-Html -Fragment, which encodes the values for me.
        A device named 'Test & <Lab>' therefore shows up as text instead of breaking the
        page, and there is no hand-written escaping to get wrong.

        The page carries no external stylesheet or script so that it can be attached to
        a mail or opened from a file share and still look the same.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary]$Sections,

        [Parameter(Mandatory)]
        [datetime]$ReferenceDate,

        [Parameter(Mandatory)]
        [int]$InactiveForDays
    )

    $sectionHtml = foreach ($section in $Sections.Values) {
        $heading = '<h2>{0}</h2>' -f [System.Net.WebUtility]::HtmlEncode($section.Title)
        $rows = @($section.Rows)

        if ($rows.Count -eq 0) {
            $heading + '<p class="empty">Nothing to report.</p>'
        }
        else {
            $table = ($rows | ConvertTo-Html -Fragment) -join [Environment]::NewLine
            $heading + ('<p class="count">{0} row(s)</p>' -f $rows.Count) + [Environment]::NewLine + $table
        }
    }

    $asOf = $ReferenceDate.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
    $body = ($sectionHtml -join [Environment]::NewLine)

    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Tenant report</title>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 2rem; color: #1b1b1b; }
  h1 { font-size: 1.4rem; }
  h2 { font-size: 1.1rem; margin-top: 2rem; }
  p.meta, p.count, p.empty { color: #555; font-size: 0.9rem; }
  table { border-collapse: collapse; margin-top: 0.5rem; font-size: 0.85rem; }
  th, td { border: 1px solid #d0d0d0; padding: 0.3rem 0.6rem; text-align: left; }
  th { background: #f2f2f2; }
</style>
</head>
<body>
<h1>Tenant report</h1>
<p class="meta">As of $asOf UTC. Devices count as stale after $InactiveForDays days without a check-in.</p>
$body
</body>
</html>
"@
}
