# Walkthrough

Why this module is built the way it is, written so I can defend every decision in it.
The README says what it does; this file says why, and where the limits are.

## 1. Why a module and not a script

A single `.ps1` would have been faster to write and would have been the usual outcome:
one file, a handful of parameters, and no way to test any part of it in isolation.

The module layout is what makes the rest possible.
`src/IntuneEntraReports/IntuneEntraReports.psm1` dot-sources everything under `Private/`
and `Public/` and exports only the public names, and the manifest lists those names
explicitly. So the public surface is a decision in `IntuneEntraReports.psd1` rather than
a side effect of how the file happened to be written, and the private helpers can be
reorganised without breaking a caller.

One file per function is a deliberate constraint, not a style preference. It keeps a
function small enough to read at once, and it makes the diff of a change point at the
thing that changed.

## 2. The central decision: the Graph client is an object, not a call

Every report needs data from Microsoft Graph. The obvious implementation calls
`Invoke-MgGraphRequest` inside each report. I did not do that, and this is the decision
the whole design hangs on.

A report takes a client:

```powershell
param(
    [Parameter(Mandatory)]
    [PSTypeName('IntuneEntraReports.GraphClient')]
    $Client
)
```

A client is a plain object with a `Name` and an `Invoke` script block that takes a URI
and returns the parsed response. There are two of them:

- `New-GraphClient` sends a GET through an existing `Connect-MgGraph` session.
- `New-FakeGraphClient` answers from JSON files or in-memory objects.

`[PSTypeName(...)]` gives this a real contract: pass something that is not a client and
the call fails at parameter binding with a type error, not three frames deep with a
missing-member error. There is a test for that in
`tests/unit/Get-StaleDeviceReport.Tests.ps1`.

**What this buys.** The entire module is testable offline, which started as a constraint
and ended as the better design. The free Microsoft 365 E5 developer sandbox is no longer
reliably available to individuals: Microsoft's own documentation ties automatic renewal
to a Visual Studio Professional or Enterprise standard subscription, and direct sign-ups
get at most 90 days subject to a qualification check. Designing around that means the
suite runs on any machine and in CI, in about a second and a half, with no secrets
anywhere.

**What it costs.** Nothing in the test suite proves that the live client works against a
real tenant. The URI construction is tested, the request itself is not. I would rather
say that plainly than claim coverage I do not have. See section 9.

### The closure problem, and why `-RequestCommand` exists

My first version put the Graph call in a private function `Invoke-GraphRequest` so that
Pester could mock it by name. It failed, in two stages, and both are worth knowing.

`New-GraphClient` builds its `Invoke` script block with `.GetNewClosure()`.
`GetNewClosure` captures **variables**. It does not give the script block access to the
defining module's command table. When `Get-GraphCollection` later runs
`& $Client.Invoke $uri` from outside, the closure cannot resolve a module-private
function by name at all, so the call failed with "command not recognized".

I then captured the command object instead, with
`$sendRequest = Get-Command Invoke-GraphRequest`, and called `& $sendRequest`. That
resolved, but Pester's mock never intercepted it: a mock replaces a command *by name*,
and calling a captured `CommandInfo` bypasses name resolution entirely.

The fix was to stop working around the test framework. `New-GraphClient` now takes an
optional `-RequestCommand` script block that defaults to the real GET:

```powershell
if (-not $PSBoundParameters.ContainsKey('RequestCommand')) {
    if (-not (Test-GraphCommandAvailable)) { throw '...' }
    $RequestCommand = {
        param([string]$Uri)
        Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject
    }
}
```

The default script block only calls `Invoke-MgGraphRequest`, which is global once the
Graph module is imported, so the closure resolves it fine. A test passes a script block
that echoes the URI. And the parameter is not test-only scaffolding: it is the documented
place to add request logging or a retry policy.

The lesson I took from it: when a seam exists only so a mocking framework can reach it,
the seam is usually in the wrong place. An ordinary parameter with a sensible default was
both simpler and more useful.

`Test-GraphCommandAvailable` survived as a private one-liner for a different reason. The
"the SDK is not installed" branch has to be testable without depending on what happens to
be installed on the machine running the suite, and that branch *is* reached by name from
module scope, so `Mock -ModuleName` works on it.

## 3. Paging, and the guard that looks paranoid

`Private/Get-GraphCollection.ps1` is the only place that knows Graph returns collections
in pages:

```powershell
while (-not [string]::IsNullOrEmpty($requestUri)) {
    $pageNumber++
    if ($pageNumber -gt $MaximumPages) {
        throw "Stopped after $MaximumPages pages while reading '$Uri'. ..."
    }
    $response = & $Client.Invoke $requestUri
    $items = Get-ObjectProperty -InputObject $response -Name 'value'
    if ($null -ne $items) { $items }
    $requestUri = Get-ObjectProperty -InputObject $response -Name '@odata.nextLink'
}
```

Three things in there are on purpose:

- **Items are streamed, not accumulated.** Emitting `$items` inside the loop means a
  caller can pipe a large tenant's devices without the whole set sitting in memory twice.
- **Absolute next links work without a special case.** Graph returns a full URL in
  `@odata.nextLink`, and `New-GraphClient` passes anything starting with `http` through
  unchanged. That is the only reason paging needs no second code path.
- **`MaximumPages` stops a loop.** A response whose `@odata.nextLink` points back at
  itself would otherwise run forever against a live tenant. It costs one comparison and
  it is tested with a self-referencing fixture.

## 4. Reading Graph responses under StrictMode

The module runs under `Set-StrictMode -Version Latest`. Under StrictMode, reading a
property an object does not have is an error rather than `$null` — and Graph routinely
omits properties that were not asked for with `$select`.

So every field read goes through `Private/Get-ObjectProperty.ps1`, which inspects
`PSObject.Properties` and returns `$null` for a missing property or a null input. It is
eight lines and it removes a whole class of failure: a report degrades to an empty column
instead of throwing when a tenant returns one field less than expected.
`tests/unit/Helpers.Tests.ps1` covers all four cases.

This is the main reason the compliance report can handle a device object that carries
nothing but an `id`, which is also a test.

## 5. Time, and why `-ReferenceDate` is a parameter

`Get-StaleDeviceReport` could call `Get-Date` internally. Then the expected day counts in
its tests would change every night, and the only way to test it would be to compute the
expectations with the same code under test, which proves nothing.

`-ReferenceDate` defaults to now and is passed in by every test:

```powershell
$referenceDate = [datetime]::SpecifyKind([datetime]::new(2026, 10, 20, 0, 0, 0), [System.DateTimeKind]::Utc)
```

The fixture timestamps are then fixed distances from that point, and the assertions are
literal numbers: `WS-0002` is 48 days old, `WS-0004` is 65. If the floor-versus-round
behaviour ever changes, a test says so.

`Private/ConvertFrom-GraphDateTime.ps1` normalises every timestamp to UTC with the
invariant culture. Both halves matter: the invariant culture means a machine set to German
parses the same string the same way, and `AdjustToUniversal` means an age in days does not
shift by an hour when the clocks change. It also returns `$null` rather than throwing for
a blank, unparsable, or `0001-01-01` placeholder value, because those mean "this device
never checked in", which is information the report should show rather than an error that
kills it.

A detail I got wrong first: `RoundtripKind` cannot be combined with `AdjustToUniversal`,
and .NET throws if you try. The commit `fix(graph): parse Graph timestamps into UTC
without RoundtripKind` is that mistake and its fix.

## 6. Domain decisions in the reports

These are the judgement calls, and they are the ones worth asking me about.

**"Stale" includes devices that never synced.** They have no measurable age, so they
cannot be compared against the threshold. Dropping them would hide the worst cases, so
they are always included, `DaysSinceLastSync` is empty, `HasNeverSynced` is `$true`, and
the sort puts them first by mapping them to `[int]::MaxValue`.

**`unknown` is not healthy.** Only `compliant` and `notApplicable` count as healthy in
`Get-DeviceComplianceReport`. A device whose compliance state cannot be determined is not
evidence of compliance, and a report that treats it as fine is worse than no report. A
missing state is normalised to `unknown` for the same reason.

**Encryption is a column, not a verdict.** Whether an unencrypted device breaks policy
depends on the tenant's policies. The report states the fact and leaves the conclusion to
the reader. Folding it into `NeedsAttention` would have been a policy decision I am not
in a position to make for someone else's tenant.

**The license report's reason to exist is one column.** Purchased against consumed units
is already visible in the portal. `AssignedToDisabledAccounts` is not aggregated per SKU
anywhere, and those are the cheapest licenses to reclaim. It is computed by reading the
disabled accounts once, counting their `assignedLicenses` into a hashtable by `skuId`,
and joining that against the subscribed SKUs — one pass each, not one request per user.

**Over-assignment is reported, not hidden.** `ConsumedUnits` above `EnabledUnits` is real:
it happens while a subscription sits in its grace period. `AvailableUnits` goes negative
and `IsOverAssigned` is true. Clamping it at zero would have made the report lie.

**A SKU with zero purchased units reports no utilization.** Not `0`, which would read as
"empty", and not a division by zero. It sorts last.

## 7. The export command

`Export-TenantReport` is the one command that writes anything, and three decisions in it
are about running unattended.

**`SupportsShouldProcess`.** Every write is wrapped in `$PSCmdlet.ShouldProcess`, so
`-WhatIf` lists the files it would create and writes nothing. A test asserts that the
output folder does not exist afterwards. Anything that runs from a scheduled task should
be able to show its intentions first.

**HTML comes from `ConvertTo-Html`, not string concatenation.** Device names are
attacker-adjacent input in the sense that nobody controls them tightly: a device called
`Test & <Lab>` would break hand-written markup. `ConvertTo-Html -Fragment` encodes the
cells, and `Private/ConvertTo-TenantReportHtml.ps1` encodes the headings with
`[System.Net.WebUtility]::HtmlEncode`. The test asserts both that `&amp;` appears and that
`<Lab>` does not. Not writing my own escaping was the whole point.

**The CSV delimiter is a parameter.** `-CsvDelimiter ';'` produces files that open
directly in a German or Swiss Excel instead of landing in one column. Small thing, but it
is the difference between a report someone uses and a report someone re-exports.

The HTML page carries the reference date and the threshold in its header, so a saved page
still says what it was measuring. An empty section prints "Nothing to report" instead of
an empty table.

## 8. Testing strategy

68 tests, 97.1 percent of commands in `src`, measured on Windows PowerShell 5.1. The
suite does no network I/O and needs no tenant.

**Fixtures over mocks, where possible.** `tests/fixtures/*.json` are Graph-shaped
responses. The device fixture is deliberately split across two pages, and page one's
`@odata.nextLink` is the key under which page two is registered, so paging is exercised by
the same data every report test uses. `WS-0004` only exists on page two, so any report test
that finds it has proven that paging worked.

**No URI strings in tests.** `tests/TestGraphClient.ps1` asks the module for its URIs via
`Get-GraphRequestUri`. If a `$select` clause changes, the fake client follows
automatically and no test needs editing. That is why `Get-GraphRequestUri` is exported
rather than private.

**Pester mocks only where there is no alternative.** Exactly one function is mocked,
`Test-GraphCommandAvailable`, and only to reach the "SDK missing" branch deterministically.
Everything else is injected.

**Private functions are tested through `InModuleScope`,** with objects built outside the
module scope and passed in via `-Parameters`. `$PSScriptRoot` inside an `InModuleScope`
block resolves to the module's folder, not the test file's, which is a trap I walked into
once.

### What is not tested, and why

- **The live transport.** The two uncovered commands in `New-GraphClient` are the default
  `-RequestCommand` body. Testing it would mean installing the Graph SDK and reaching a
  tenant.
- **`Test-GraphCommandAvailable` itself** is mocked in the only test that exercises its
  caller, so its own body is uncovered. It is a single `Get-Command` call.
- **The module loader's error branch** in the `.psm1`, which only fires if a source file
  fails to parse.
- **Throttling.** Graph returns HTTP 429 with a `Retry-After` header under load. This
  module does not handle it. With `-RequestCommand` a caller can add a retry policy
  without touching the module, which is why I consider this a documented gap rather than a
  missing feature.
- **The fixtures are hand-written**, modelled on the documented shape of the Graph
  responses rather than captured from a live tenant. If a real tenant returns a field in a
  different shape, these tests would not catch it.
- **The `$filter=accountEnabled eq false` query** is not verified against a live tenant.
  Some directory queries need advanced query parameters, and that is the first thing I
  would check when running this for real.

## 9. Tooling

`build.ps1` is the only entry point: `Lint`, `Test`, `Format`, and `All` for the first
two. CI calls the same script, so a green terminal and a green pipeline mean the same
thing.

**Two analyzer settings files.** `PSScriptAnalyzerSettings.psd1` applies to `src` and
`build.ps1`. `tests/PSScriptAnalyzerSettings.psd1` additionally drops
`PSUseDeclaredVarsMoreThanAssignments`, which fires on every variable a `BeforeAll` block
shares with its `It` blocks because the analyzer cannot see runtime scoping. Excluding it
globally would have weakened a useful rule for the module itself, so the exclusion is
scoped to the place where the rule is wrong.

**Two formatting rules that contradict each other.** `PSUseConsistentWhitespace` with
`CheckOperator = $true` wants exactly one space around `=`; `PSAlignAssignmentStatement`
with `CheckHashtable = $true` wants them aligned into a column. With both on, the
formatter produced output the linter then rejected, 81 findings' worth, and
`./build.ps1 -Task Format` could never converge. `CheckOperator` is off, with a comment in
the settings file saying so. Alignment won because these files are mostly hashtable
definitions and the aligned form is easier to scan.

**The coverage gate is enforced in the build, not by Pester.** Pester accepts a
`CoveragePercentTarget` and reports against it but does not fail the run, so
`Invoke-TestTask` reads `$result.CodeCoverage.CoveragePercent` and throws below 90. A
threshold nothing checks is a comment.

**CI pins versions.** `Pester 6.2.0` and `PSScriptAnalyzer 1.25.0` with
`-RequiredVersion`, so a new release cannot turn a green build red without a commit that
says so. `build.ps1` itself only requires Pester 5.5 or newer, which is what a contributor
is likely to have.

**Three CI jobs.** PowerShell 7 on Linux and Windows, plus Windows PowerShell 5.1. The
5.1 job is there because that is what a managed Windows client runs out of the box, and
because the manifest claims `PowerShellVersion = '5.1'`. Claiming compatibility without
testing it would be the kind of detail that falls apart in an interview.

## 10. If I had to extend this tomorrow

The next report is a new file in `Public/`, a new entry in `Get-GraphRequestUri`, a
fixture, and a test file. No existing code changes. That was the point of putting the URIs
in one place and the transport behind a parameter.

The two things I would do before using this on anything that matters: handle HTTP 429 with
`Retry-After` in a `-RequestCommand` wrapper, and verify the disabled-user query against a
real tenant.
