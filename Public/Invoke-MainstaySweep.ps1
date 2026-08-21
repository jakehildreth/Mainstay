function Invoke-MainstaySweep {
    <#
    .SYNOPSIS
        Applies the canonical branch protection ruleset to every eligible repository.

    .DESCRIPTION
        Enumerates eligible repositories and creates the canonical ruleset on any
        that lack it. Repositories that already carry an active ruleset of that
        name are left untouched, so the sweep is safe to run repeatedly.

        The sweep is idempotent only. It never edits or removes an existing
        ruleset, which means a deliberate per repository exception survives.

        A failure on one repository is reported and the sweep continues.

    .PARAMETER Token
        A GitHub token with administration permission on the target repositories.
        Defaults to the MAINSTAY_TOKEN environment variable.

    .PARAMETER Owner
        The account login whose repositories are swept.

    .PARAMETER IncludeOrganization
        Organizations to sweep in addition to the owner account. No organization
        is touched unless it is named here.

    .PARAMETER ExcludeRepository
        Repository names to leave alone. Matched without regard to case.

    .PARAMETER RulesetName
        The name of the canonical ruleset. Defaults to 'Protect default branch'.

    .PARAMETER RedactPrivateName
        Replace private repository names in the output with a stable hashed
        marker. Use this when the output is written to a public log.

    .PARAMETER RedactionSalt
        A secret value mixed into the redaction hash so markers cannot be
        reproduced from a repository name alone. Defaults to the MAINSTAY_SALT
        environment variable. Redacting without one produces a warning, because
        an unsalted marker can be matched by hashing likely names.

    .EXAMPLE
        Invoke-MainstaySweep -Owner 'octocat' -WhatIf

        Reports what the sweep would create without changing anything.

    .EXAMPLE
        Invoke-MainstaySweep -Owner 'octocat' -IncludeOrganization 'octo-co' -RedactPrivateName

        Sweeps the account and one organization, keeping private names out of the output.

    .NOTES
        Requires a fine grained token with Administration write permission.
        The workflow GITHUB_TOKEN is scoped to a single repository and cannot
        administer others.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Token = $env:MAINSTAY_TOKEN,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Owner,

        [Parameter()]
        [string[]]$IncludeOrganization,

        [Parameter()]
        [string[]]$ExcludeRepository,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RulesetName = 'Protect default branch',

        [Parameter()]
        [switch]$RedactPrivateName,

        [Parameter()]
        [AllowEmptyString()]
        [string]$RedactionSalt = $env:MAINSTAY_SALT
    )

    begin {
        Write-Verbose "Starting sweep for '$Owner' using ruleset '$RulesetName'"

        if ($RedactPrivateName.IsPresent -and [string]::IsNullOrEmpty($RedactionSalt)) {
            Write-Warning ('Redacting without a salt. Repository names are short and predictable, ' +
                'so the markers can be reproduced by guessing. Set MAINSTAY_SALT or pass -RedactionSalt.')
        }
    }

    process {
        $repositoryParameters = @{
            Token = $Token
            Owner = $Owner
        }

        if ($PSBoundParameters.ContainsKey('IncludeOrganization')) {
            $repositoryParameters['IncludeOrganization'] = $IncludeOrganization
        }

        if ($PSBoundParameters.ContainsKey('ExcludeRepository')) {
            $repositoryParameters['ExcludeRepository'] = $ExcludeRepository
        }

        $repositories = Get-MainstayRepository @repositoryParameters

        foreach ($repository in $repositories) {
            $safeName = ConvertTo-MainstaySafeName -FullName $repository.FullName `
                -Visibility $repository.Visibility -Redact:$RedactPrivateName -Salt $RedactionSalt

            $action = 'Failed'
            $reason = ''

            try {
                $isProtected = Test-MainstayProtection -Token $Token `
                    -FullName $repository.FullName -RulesetName $RulesetName

                if ($isProtected) {
                    $action = 'AlreadyProtected'
                    $reason = 'Active ruleset present'
                } elseif (-not (Test-MainstayRepositoryHasBranch -Token $Token -FullName $repository.FullName)) {
                    $action = 'Skipped'
                    $reason = 'Repository has no commits yet'
                } elseif ($PSCmdlet.ShouldProcess($safeName, "Create ruleset '$RulesetName'")) {
                    New-MainstayProtection -Token $Token `
                        -FullName $repository.FullName -RulesetName $RulesetName | Out-Null
                    $action = 'Created'
                    $reason = 'Ruleset created'
                } else {
                    $action = 'Skipped'
                    $reason = 'WhatIf'
                }
            } catch {
                $action = 'Failed'
                $reason = $_.Exception.Message

                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'MainstaySweepFailed',
                    [System.Management.Automation.ErrorCategory]::NotSpecified,
                    $safeName
                )
                $PSCmdlet.WriteError($errorRecord)
            }

            [PSCustomObject]@{
                Repository = $safeName
                Visibility = $repository.Visibility
                Action     = $action
                Reason     = $reason
            }
        }
    }

    end {
        Write-Verbose 'Sweep complete'
    }
}
