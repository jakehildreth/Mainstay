function Test-MainstayProtection {
    <#
    .SYNOPSIS
        Reports whether a repository already carries the canonical ruleset.

    .DESCRIPTION
        Returns true when the repository has an active ruleset with the given
        name. The check is by name and enforcement only. A ruleset that exists
        but has been disabled is treated as absent, because a disabled ruleset
        enforces nothing.

    .PARAMETER Token
        A GitHub token with permission to read repository rulesets.

    .PARAMETER FullName
        The owner/name identifier of the repository.

    .PARAMETER RulesetName
        The name of the canonical ruleset.

    .OUTPUTS
        System.Boolean

    .EXAMPLE
        Test-MainstayProtection -Token $token -FullName 'octocat/Hello' -RulesetName 'Protect default branch'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FullName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RulesetName
    )

    process {
        $rulesets = Invoke-MainstayApi -Token $Token -Path "repos/$FullName/rulesets"

        foreach ($ruleset in $rulesets) {
            if ($ruleset.name -eq $RulesetName -and $ruleset.enforcement -eq 'active') {
                return $true
            }
        }

        return $false
    }
}
