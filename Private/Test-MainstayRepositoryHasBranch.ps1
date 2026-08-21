function Test-MainstayRepositoryHasBranch {
    <#
    .SYNOPSIS
        Reports whether a repository contains at least one branch.

    .DESCRIPTION
        A repository with no commits has no branches, and a ruleset requiring a
        pull request on its default branch would stand in the way of the first
        push. This check identifies that case.

        The repository object returned by the REST API cannot answer this. Its
        default_branch field holds the configured branch name and is populated
        even when the branch does not exist yet, so the branch list has to be
        asked for directly.

    .PARAMETER Token
        A GitHub token with permission to read the repository.

    .PARAMETER FullName
        The owner/name identifier of the repository.

    .OUTPUTS
        System.Boolean

    .EXAMPLE
        Test-MainstayRepositoryHasBranch -Token $token -FullName 'octocat/Hello'

    .NOTES
        Only one branch is requested, because the count is irrelevant. Call this
        only when a repository is about to be changed, to avoid spending a
        request on every repository in the account.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FullName
    )

    process {
        $branches = Invoke-MainstayApi -Token $Token -Path "repos/$FullName/branches?per_page=1"

        # @($null) yields a one element array holding null, so a null response
        # has to be rejected before the count is taken.
        if ($null -eq $branches) {
            return $false
        }

        return (@($branches).Count -gt 0)
    }
}
