function Get-MainstayRepository {
    <#
    .SYNOPSIS
        Returns the repositories eligible for branch protection for one owner.

    .DESCRIPTION
        Enumerates the repositories of a single account — a user or an
        organization — and removes the ones that cannot or should not be
        protected.

        A repository is excluded when it is a fork, is archived, has no default
        branch, is named in ExcludeRepository, or the caller does not hold admin
        permission on it.

        One owner is enumerated per call, because the GitHub App installation
        token used by the sweep is scoped to a single account. A user owner is
        read from users/{owner}/repos, an organization from orgs/{owner}/repos.

    .PARAMETER Token
        A GitHub token with permission to read the owner's repository list.

    .PARAMETER Owner
        The account login whose repositories are enumerated.

    .PARAMETER OwnerType
        Whether Owner is a user account or an organization. This selects the API
        endpoint, because the two are listed from different paths.

    .PARAMETER ExcludeRepository
        Repository names to leave alone. Matched without regard to case.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .EXAMPLE
        Get-MainstayRepository -Token $token -Owner 'octocat' -OwnerType User

    .EXAMPLE
        Get-MainstayRepository -Token $token -Owner 'octo-co' -OwnerType Org -ExcludeRepository 'Legacy'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Owner,

        [Parameter(Mandatory)]
        [ValidateSet('User', 'Org')]
        [string]$OwnerType,

        [Parameter()]
        [string[]]$ExcludeRepository
    )

    process {
        $source = switch ($OwnerType) {
            'User' { "users/$Owner/repos?per_page=100" }
            'Org'  { "orgs/$Owner/repos?per_page=100" }
        }

        $excluded = @{}
        foreach ($name in $ExcludeRepository) {
            $excluded[$name.ToLowerInvariant()] = $true
        }

        $repositories = Invoke-MainstayApi -Token $Token -Path $source -Paginate

        foreach ($repository in $repositories) {
            if ($repository.fork) {
                Write-Verbose "Skipping $($repository.full_name): fork"
                continue
            }

            if ($repository.archived) {
                Write-Verbose "Skipping $($repository.full_name): archived"
                continue
            }

            if ([string]::IsNullOrWhiteSpace($repository.default_branch)) {
                Write-Verbose "Skipping $($repository.full_name): no default branch"
                continue
            }

            if (-not $repository.permissions.admin) {
                Write-Verbose "Skipping $($repository.full_name): not an admin"
                continue
            }

            if ($excluded.ContainsKey($repository.name.ToLowerInvariant())) {
                Write-Verbose "Skipping $($repository.full_name): excluded by name"
                continue
            }

            $visibility = 'public'
            if ($repository.private) {
                $visibility = 'private'
            }

            [PSCustomObject]@{
                FullName      = $repository.full_name
                Name          = $repository.name
                Visibility    = $visibility
                DefaultBranch = $repository.default_branch
            }
        }
    }
}
