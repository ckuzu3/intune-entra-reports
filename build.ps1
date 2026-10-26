<#
.SYNOPSIS
    Runs the checks for this repository: the linter, the unit tests, or both.

.DESCRIPTION
    The same entry point runs locally and in CI, so a green pipeline and a green
    terminal mean the same thing. CI mode additionally writes a test result file and
    enforces the code coverage target.

    The module and the test suite are linted with their own settings file. The tests
    drop the two rules that misfire on Pester's structure, which keeps the module under
    the full rule set instead of weakening it for everything.

.PARAMETER Task
    Which checks to run. Defaults to Lint and Test. 'Format' is not part of 'All'
    because it rewrites files instead of only reporting on them.

.PARAMETER CI
    Write a NUnit test result file and measure code coverage.

.PARAMETER MinimumCoverage
    The coverage percentage the module is expected to keep in CI mode.

.EXAMPLE
    ./build.ps1

    Runs the linter and the tests.

.EXAMPLE
    ./build.ps1 -Task Test -CI

    Runs the tests the way the pipeline does.
#>
[CmdletBinding()]
param(
    [ValidateSet('Lint', 'Test', 'Format', 'All')]
    [string[]]$Task = @('All'),

    [switch]$CI,

    [ValidateRange(0, 100)]
    [int]$MinimumCoverage = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-TaskSelected {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$SelectedTasks
    )

    return ($SelectedTasks -contains 'All') -or ($SelectedTasks -contains $Name)
}

function Get-AnalyzerSettingsPath {
    <#
        Test code and module code are held to different rule sets, and both the linter
        and the formatter have to agree on which file applies to which path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $testRoot = Join-Path -Path $RepositoryRoot -ChildPath 'tests'
    if ($FilePath.StartsWith($testRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return (Join-Path -Path $testRoot -ChildPath 'PSScriptAnalyzerSettings.psd1')
    }

    return (Join-Path -Path $RepositoryRoot -ChildPath 'PSScriptAnalyzerSettings.psd1')
}

function Invoke-FormatTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Import-Module -Name PSScriptAnalyzer -MinimumVersion 1.21.0 -ErrorAction Stop

    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    $files = Get-ChildItem -Path $RepositoryRoot -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File |
        Where-Object -FilterScript { $_.FullName -notmatch '[\\/]testresults[\\/]' }

    $changedCount = 0
    foreach ($file in $files) {
        $original = Get-Content -LiteralPath $file.FullName -Raw
        $settingsPath = Get-AnalyzerSettingsPath -RepositoryRoot $RepositoryRoot -FilePath $file.FullName
        $formatted = Invoke-Formatter -ScriptDefinition $original -Settings $settingsPath

        if ($formatted -ne $original) {
            [System.IO.File]::WriteAllText($file.FullName, $formatted, $utf8WithoutBom)
            Write-Information -MessageData "Formatted $($file.Name)." -InformationAction Continue
            $changedCount++
        }
    }

    Write-Information -MessageData "Formatter: $changedCount file(s) changed." -InformationAction Continue
}

function Invoke-LintTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Import-Module -Name PSScriptAnalyzer -MinimumVersion 1.21.0 -ErrorAction Stop

    $targets = @(
        @{
            Path     = @(
                (Join-Path -Path $RepositoryRoot -ChildPath 'src'),
                (Join-Path -Path $RepositoryRoot -ChildPath 'build.ps1')
            )
            Settings = Join-Path -Path $RepositoryRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
        }
        @{
            Path     = @((Join-Path -Path $RepositoryRoot -ChildPath 'tests'))
            Settings = Join-Path -Path $RepositoryRoot -ChildPath 'tests/PSScriptAnalyzerSettings.psd1'
        }
    )

    $findings = foreach ($target in $targets) {
        foreach ($path in $target.Path) {
            Invoke-ScriptAnalyzer -Path $path -Recurse -Settings $target.Settings
        }
    }

    $findings = @($findings)
    if ($findings.Count -gt 0) {
        $summary = $findings |
            Sort-Object -Property Severity, ScriptName, Line |
            Format-Table -Property Severity, ScriptName, Line, RuleName, Message -AutoSize -Wrap |
            Out-String

        Write-Information -MessageData $summary -InformationAction Continue
        throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
    }

    Write-Information -MessageData 'PSScriptAnalyzer: no findings.' -InformationAction Continue
}

function Invoke-TestTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [switch]$CollectResults,

        [ValidateRange(0, 100)]
        [int]$CoverageTarget = 90
    )

    Import-Module -Name Pester -MinimumVersion 5.5.0 -ErrorAction Stop

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = Join-Path -Path $RepositoryRoot -ChildPath 'tests'
    $configuration.Run.Throw = $true
    $configuration.Output.Verbosity = 'Detailed'

    if ($CollectResults) {
        $resultPath = Join-Path -Path $RepositoryRoot -ChildPath 'testresults'
        if (-not (Test-Path -LiteralPath $resultPath)) {
            New-Item -Path $resultPath -ItemType Directory -Force | Out-Null
        }

        $configuration.TestResult.Enabled = $true
        $configuration.TestResult.OutputPath = Join-Path -Path $resultPath -ChildPath 'pester.xml'

        $configuration.CodeCoverage.Enabled = $true
        $configuration.CodeCoverage.Path = Join-Path -Path $RepositoryRoot -ChildPath 'src'
        $configuration.CodeCoverage.OutputPath = Join-Path -Path $resultPath -ChildPath 'coverage.xml'
        $configuration.CodeCoverage.CoveragePercentTarget = $CoverageTarget
        $configuration.Run.PassThru = $true
    }

    $result = Invoke-Pester -Configuration $configuration

    if (-not $CollectResults) {
        return
    }

    # Pester reports the coverage target but does not fail the run over it, so the
    # threshold is enforced here. Without this the number in the README would be a
    # description rather than a promise.
    $coverage = [math]::Round($result.CodeCoverage.CoveragePercent, 1)
    Write-Information -MessageData "Code coverage: $coverage percent." -InformationAction Continue

    if ($coverage -lt $CoverageTarget) {
        throw "Code coverage $coverage percent is below the required $CoverageTarget percent."
    }
}

if ($Task -contains 'Format') {
    Invoke-FormatTask -RepositoryRoot $PSScriptRoot
}

if (Test-TaskSelected -Name 'Lint' -SelectedTasks $Task) {
    Invoke-LintTask -RepositoryRoot $PSScriptRoot
}

if (Test-TaskSelected -Name 'Test' -SelectedTasks $Task) {
    Invoke-TestTask -RepositoryRoot $PSScriptRoot -CollectResults:$CI -CoverageTarget $MinimumCoverage
}
