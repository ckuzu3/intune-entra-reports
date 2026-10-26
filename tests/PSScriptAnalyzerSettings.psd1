@{
    # The test suite is checked with the same rules as the module, minus the ones that
    # misfire on Pester's own structure. The module itself keeps the full rule set.
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning')

    ExcludeRules        = @(
        # Variables assigned in BeforeAll are read inside It blocks at run time, which
        # the analyzer cannot see, so every shared fixture looks unused to it.
        'PSUseDeclaredVarsMoreThanAssignments'

        # Same reason as in the module: PSScriptAnalyzer's static guess about cmdlet
        # availability is weaker than running the suite on both editions in CI.
        'PSUseCompatibleCmdlets'
    )

    Rules               = @{
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $true
        }
        PSUseConsistentIndentation = @{
            Enable          = $true
            Kind            = 'space'
            IndentationSize = 4
        }
        PSUseConsistentWhitespace  = @{
            Enable          = $true
            CheckInnerBrace = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            # CheckOperator insists on exactly one space around '=', which contradicts
            # PSAlignAssignmentStatement below. Alignment wins here because it is what
            # makes the hashtable-heavy report definitions readable.
            CheckOperator   = $false
            CheckSeparator  = $true
        }
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }
    }
}
