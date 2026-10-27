# IntuneEntraReports

[![CI](https://github.com/ckuzu3/intune-entra-reports/actions/workflows/ci.yml/badge.svg)](https://github.com/ckuzu3/intune-entra-reports/actions/workflows/ci.yml)

A read-only PowerShell module that turns Microsoft Intune and Entra ID data into three
reports you can act on: devices that stopped checking in, devices that need attention,
and licenses that are being paid for but not used.

## Problem

In my support work the same questions come back every few weeks, and the admin centre
answers none of them in one place:

- Which managed devices have not checked in for a month? They still hold a license, they
  no longer receive policy or patches, and they still show up as managed.
- Which devices are not compliant right now, and which of them are also unencrypted?
- How many licenses are still assigned to accounts that are already blocked?

Clicking through three blades and exporting three CSVs by hand is slow, and the result
cannot be repeated or scheduled. The usual next step is a script that works once on one
machine, and a year later nobody can say what it actually checks.

## Solution

A proper PowerShell module instead of a loose script: one command per question, a shared
Graph layer underneath, and a test suite that runs without access to a tenant.

The part I would point at in a review is the Graph client. The reports do not call
`Invoke-MgGraphRequest` themselves. They take a client object with a single `Invoke`
script block, and there are two implementations of it: a live one that reads through an
existing `Connect-MgGraph` session, and a fake one that answers from JSON fixtures. That
is what lets the whole module be tested offline, and it is also honest about the
constraint I started from, since a free Microsoft 365 developer tenant is no longer
reliably available.

The module only ever reads. It issues GET requests, it never handles credentials itself,
and the only command that writes anything writes report files to a folder you name.

## Features

- `Get-StaleDeviceReport` lists devices past a configurable inactivity threshold. Devices
  that never checked in have no measurable age, so they are always included and sort
  first.
- `Get-DeviceComplianceReport` returns the devices that need attention. Only `compliant`
  and `notApplicable` count as healthy; `unknown` does not, because a state that cannot
  be determined is not evidence of compliance. Encryption is reported as its own column.
- `Get-LicenseUsageReport` reports purchased against consumed units per SKU, flags
  over-assignment, and counts how many licenses of each SKU are still held by disabled
  accounts.
- `Export-TenantReport` runs all three and writes CSV, JSON and a single self-contained
  HTML page. It supports `-WhatIf` and `-Confirm`, and the CSV delimiter is a parameter
  so the files open in a Swiss Excel without an import dialog.
- `New-FakeGraphClient` and `Get-GraphRequestUri` are exported so you can build your own
  fixtures without copying URL strings out of the source.
- 68 unit tests, 97.1 percent coverage of `src`, no tenant required.
- CI runs the linter and the tests on PowerShell 7 (Linux and Windows) and on Windows
  PowerShell 5.1, and fails the build if coverage drops below 90 percent.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7. Both are covered by CI.
- For live use: the `Microsoft.Graph.Authentication` module, and these delegated read
  scopes. `Directory.Read.All` can stand in for the last two.
  - `DeviceManagementManagedDevices.Read.All` for the device reports
  - `Organization.Read.All` for the subscribed SKUs
  - `User.Read.All` for the license assignments of disabled accounts
- For development: `Pester` 5.5 or newer and `PSScriptAnalyzer` 1.21 or newer. Nothing
  else, and no tenant.

## Setup

```powershell
git clone https://github.com/ckuzu3/intune-entra-reports.git
cd intune-entra-reports
Import-Module ./src/IntuneEntraReports/IntuneEntraReports.psd1

# Linter and tests, the same way CI runs them
./build.ps1

# Apply the formatter the linter checks against
./build.ps1 -Task Format
```

Against a real tenant:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes 'DeviceManagementManagedDevices.Read.All','Directory.Read.All'

$client = New-GraphClient
Export-TenantReport -Client $client -Path ./out -InactiveForDays 45
```

## Example

Without a tenant, using the fixtures that the test suite also runs on:

```powershell
Import-Module ./src/IntuneEntraReports/IntuneEntraReports.psd1
. ./tests/TestGraphClient.ps1

$client = New-TestGraphClient
$asOf = [datetime]::SpecifyKind([datetime]::new(2026, 10, 20, 0, 0, 0), [System.DateTimeKind]::Utc)

Get-StaleDeviceReport -Client $client -InactiveForDays 30 -ReferenceDate $asOf |
    Format-Table DeviceName, OperatingSystem, DaysSinceLastSync, HasNeverSynced, UserPrincipalName
```

```text
DeviceName OperatingSystem DaysSinceLastSync HasNeverSynced UserPrincipalName
---------- --------------- ----------------- -------------- -----------------
WS-0003    Windows                                     True carol@contoso.example
WS-0004    Windows         65                         False dave@contoso.example
WS-0002    Windows         48                         False bob@contoso.example
```

```powershell
Get-LicenseUsageReport -Client $client |
    Format-Table SkuPartNumber, EnabledUnits, ConsumedUnits, AvailableUnits, AssignedToDisabledAccounts, UtilizationPercent
```

```text
SkuPartNumber  EnabledUnits ConsumedUnits AvailableUnits AssignedToDisabledAccounts UtilizationPercent
-------------  ------------ ------------- -------------- -------------------------- ------------------
EMS                      50            52             -2                          1                104
SPE_E3                  100            95              5                          2                 95
AAD_PREMIUM_P2           10             0             10                          0                  0
```

`EMS` consumes more units than were purchased, which happens during a grace period, so
the report flags it instead of hiding it. `SPE_E3` has five units left and two of its
assigned licenses sit on blocked accounts.

Writing the files:

```powershell
Export-TenantReport -Client $client -Path ./out -Format Csv, Json, Html
```

```text
stale-devices.csv       device-compliance.csv       license-usage.csv
stale-devices.json      device-compliance.json      license-usage.json
index.html
```

## Architecture

```text
                Get-StaleDeviceReport
                Get-DeviceComplianceReport      public reports: one question each
                Get-LicenseUsageReport
                        |
                        | Get-GraphCollection       follows @odata.nextLink,
                        |                           stops after MaximumPages
                        v
                 $Client.Invoke($uri)            one script block, two implementations
                   /            \
      New-GraphClient            New-FakeGraphClient
      (GET via                   (JSON fixtures or
       Invoke-MgGraphRequest,     in-memory objects,
       live tenant)               no tenant)

      Export-TenantReport -> the three reports above
                           -> CSV / JSON / ConvertTo-TenantReportHtml
```

Supporting pieces, all private: `Get-ObjectProperty` reads a field that Graph may have
omitted, `ConvertFrom-GraphDateTime` normalises timestamps to UTC, and
`Test-GraphCommandAvailable` is the seam that makes the "SDK is missing" branch testable.

`Get-GraphRequestUri` holds every request URI including its `$select` clause, so the
reports ask for exactly the fields they use and the tests can ask the module for a URI
instead of hard-coding one.

## Tests

```powershell
./build.ps1 -Task Test          # 68 tests
./build.ps1 -Task Test -CI      # plus NUnit results, coverage, and the 90 percent gate
```

The suite never touches a network. Paging is covered by a two-page device fixture whose
first page links to the second, and the time-dependent reports take a `-ReferenceDate`
so the expected day counts are fixed numbers rather than something that changes
overnight.

## What I learned

- **An abstraction that only exists for tests is usually the wrong one.** I first hid the
  Graph call behind a private function so Pester could mock it by name. It did not work:
  `GetNewClosure` captures variables, not the module's command table, so a closure called
  from outside the module cannot resolve a module-private function at all. Making the
  transport an ordinary parameter with a sensible default solved the test problem and
  also gave callers a way to add logging or retries. The commit history shows both
  attempts.
- **`Set-StrictMode -Version Latest` changes how you read API responses.** Graph omits
  properties that were not requested, and under StrictMode touching an absent property is
  an error, not `$null`. One small helper for every field read was less work than
  debugging it later.
- **Two formatting rules in PSScriptAnalyzer contradict each other.**
  `PSUseConsistentWhitespace` with `CheckOperator` wants exactly one space around `=`,
  while `PSAlignAssignmentStatement` wants them aligned. I had 81 findings until I
  understood that I had to choose. The settings file records which one I chose and why.
- **A coverage target that nothing enforces is just a comment.** Pester reports the
  target but does not fail the run over it, so `build.ps1` compares the number itself and
  throws.
- **Dates are where locale bugs hide.** Parsing with the invariant culture and
  normalising to UTC means the same input gives the same day count on a machine set to
  German as on a CI runner set to English.

## Possible extensions

- A second time window per report, so a run can show what changed since the last one
  instead of only the current state.
- Format files (`*.format.ps1xml`) for the output types, so `Get-StaleDeviceReport`
  prints a sensible table without a `Format-Table` on every call.
- Conditional access policies and Autopilot device registrations as further reports; both
  are read-only Graph calls that fit the existing client without changes.
- Publishing to the PowerShell Gallery, which mainly means a release workflow and a
  changelog.
- A scheduled GitHub Actions run against a real tenant with a service principal, writing
  the HTML page as an artifact. I left this out on purpose: the only tenant I could point
  it at is not mine to automate against.

## License

MIT, see [LICENSE](LICENSE).
