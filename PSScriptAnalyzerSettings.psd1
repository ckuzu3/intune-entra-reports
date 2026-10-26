@{
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning')

    ExcludeRules        = @(
        # The module targets Windows PowerShell 5.1 and PowerShell 7 and is checked
        # against both in CI, which is a stronger signal than this rule's static guess
        # about cmdlet availability.
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
