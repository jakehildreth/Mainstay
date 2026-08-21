function Get-MainstayRepository {
    <#
    .SYNOPSIS
        Returns the repositories eligible for branch protection.

    .DESCRIPTION
        Enumerates repositories owned by the account, plus any organizations
        explicitly requested, and removes the ones that cannot or should not be
        protected.

        A repository is excluded when it is a fork, is archived, has no default
        branch, is named in ExcludeRepository, or the caller does not hold admin
        permission on it.

    .PARAMETER Token
        A GitHub token with permission to read the repository list.

    .PARAMETER Owner
        The account login whose repositories are enumerated.

    .PARAMETER IncludeOrganization
        Organizations to enumerate in addition to the owner account. No
        organization is touched unless it is named here.

    .PARAMETER ExcludeRepository
        Repository names to leave alone. Matched without regard to case.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .EXAMPLE
        Get-MainstayRepository -Token $token -Owner 'octocat' -ExcludeRepository 'Legacy'
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

        [Parameter()]
        [string[]]$IncludeOrganization,

        [Parameter()]
        [string[]]$ExcludeRepository
    )

    process {
        $sources = [System.Collections.Generic.List[string]]::new()
        $sources.Add("user/repos?affiliation=owner&per_page=100")

        foreach ($organization in $IncludeOrganization) {
            $sources.Add("orgs/$organization/repos?per_page=100")
        }

        $excluded = @{}
        foreach ($name in $ExcludeRepository) {
            $excluded[$name.ToLowerInvariant()] = $true
        }

        foreach ($source in $sources) {
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
}
