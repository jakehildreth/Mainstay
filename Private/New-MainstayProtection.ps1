function New-MainstayProtection {
    <#
    .SYNOPSIS
        Creates the canonical branch protection ruleset on a repository.

    .DESCRIPTION
        Creates a branch ruleset targeting the repository default branch that
        requires a pull request, blocks force pushes, and blocks deletion.

        No approving reviews are required, and the bypass list is empty, so the
        rule applies to repository administrators as well.

        require_extra_approval_for_unattributed_changes is set to false on
        purpose. Left at its default it can demand an approval despite the
        approval count being zero, which contradicts the intent of the rule.

    .PARAMETER Token
        A GitHub token with administration permission on the repository.

    .PARAMETER FullName
        The owner/name identifier of the repository.

    .PARAMETER RulesetName
        The name to give the ruleset.

    .OUTPUTS
        System.Management.Automation.PSObject

    .EXAMPLE
        New-MainstayProtection -Token $token -FullName 'octocat/Hello' -RulesetName 'Protect default branch'
    #>
    [CmdletBinding()]
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
        $rulesetBody = @{
            name          = $RulesetName
            target        = 'branch'
            enforcement   = 'active'
            bypass_actors = @()
            conditions    = @{
                ref_name = @{
                    include = @('~DEFAULT_BRANCH')
                    exclude = @()
                }
            }
            rules         = @(
                @{ type = 'deletion' }
                @{ type = 'non_fast_forward' }
                @{
                    type       = 'pull_request'
                    parameters = @{
                        required_approving_review_count                 = 0
                        dismiss_stale_reviews_on_push                   = $false
                        require_code_owner_review                       = $false
                        require_last_push_approval                      = $false
                        required_review_thread_resolution               = $false
                        require_extra_approval_for_unattributed_changes = $false
                        allowed_merge_methods                           = @('merge', 'squash', 'rebase')
                    }
                }
            )
        }

        Invoke-MainstayApi -Token $Token -Path "repos/$FullName/rulesets" -Method 'POST' -Body $rulesetBody
    }
}
