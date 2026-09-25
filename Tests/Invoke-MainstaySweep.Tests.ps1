BeforeAll {
    $ModuleRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $ModuleRoot 'Mainstay.psd1') -Force -ErrorAction Stop
}

Describe 'Invoke-MainstaySweep' {

    Context 'When sweeping one owner' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Get-MainstayRepository { @() }
                Mock Test-MainstayProtection { $true }
                Mock Test-MainstayRepositoryHasBranch { $true }
                Mock New-MainstayProtection { }
            }
        }

        It 'Passes Owner and OwnerType through to enumeration' {
            InModuleScope 'Mainstay' {
                Invoke-MainstaySweep -Token 'x' -Owner 'gilmourltd' -OwnerType Org | Out-Null
                Should -Invoke Get-MainstayRepository -Exactly 1 -ParameterFilter {
                    $Owner -eq 'gilmourltd' -and $OwnerType -eq 'Org'
                }
            }
        }
    }

    Context 'When a repository already has the canonical ruleset' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Get-MainstayRepository {
                    @([PSCustomObject]@{ FullName = 'jakehildreth/Locksmith2'; Visibility = 'public' })
                }
                Mock Test-MainstayProtection { $true }
                Mock Test-MainstayRepositoryHasBranch { $true }
                Mock New-MainstayProtection { }
            }
        }

        It 'Does not create a second ruleset' {
            InModuleScope 'Mainstay' {
                Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User | Out-Null
                Should -Invoke New-MainstayProtection -Exactly 0
            }
        }

        It 'Reports the repository as already protected' {
            InModuleScope 'Mainstay' {
                $result = Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User
                $result.Action | Should -Be 'AlreadyProtected'
            }
        }

        It 'Does not spend an API call checking for branches' {
            InModuleScope 'Mainstay' {
                Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User | Out-Null
                Should -Invoke Test-MainstayRepositoryHasBranch -Exactly 0
            }
        }
    }

    Context 'When a repository is missing the canonical ruleset' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Get-MainstayRepository {
                    @([PSCustomObject]@{ FullName = 'jakehildreth/NewRepo'; Visibility = 'public' })
                }
                Mock Test-MainstayProtection { $false }
                Mock Test-MainstayRepositoryHasBranch { $true }
                Mock New-MainstayProtection { }
            }
        }

        It 'Creates the ruleset exactly once' {
            InModuleScope 'Mainstay' {
                Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User | Out-Null
                Should -Invoke New-MainstayProtection -Exactly 1
            }
        }

        It 'Reports the repository as created' {
            InModuleScope 'Mainstay' {
                $result = Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User
                $result.Action | Should -Be 'Created'
            }
        }
    }

    Context 'When the repository has no commits yet' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Get-MainstayRepository {
                    @([PSCustomObject]@{ FullName = 'jakehildreth/ADCStencil'; Visibility = 'private' })
                }
                Mock Test-MainstayProtection { $false }
                Mock Test-MainstayRepositoryHasBranch { $false }
                Mock New-MainstayProtection { }
            }
        }

        It 'Does not create a ruleset that would obstruct the first push' {
            InModuleScope 'Mainstay' {
                Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User | Out-Null
                Should -Invoke New-MainstayProtection -Exactly 0
            }
        }

        It 'Reports the repository as skipped' {
            InModuleScope 'Mainstay' {
                $result = Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User
                $result.Action | Should -Be 'Skipped'
            }
        }

        It 'Gives the empty repository as the reason' {
            InModuleScope 'Mainstay' {
                $result = Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User
                $result.Reason | Should -Match 'no commits'
            }
        }
    }

    Context 'When WhatIf is supplied' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Get-MainstayRepository {
                    @([PSCustomObject]@{ FullName = 'jakehildreth/NewRepo'; Visibility = 'public' })
                }
                Mock Test-MainstayProtection { $false }
                Mock Test-MainstayRepositoryHasBranch { $true }
                Mock New-MainstayProtection { }
            }
        }

        It 'Does not create the ruleset' {
            InModuleScope 'Mainstay' {
                Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User -WhatIf | Out-Null
                Should -Invoke New-MainstayProtection -Exactly 0
            }
        }
    }

    Context 'When creation fails' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Get-MainstayRepository {
                    @([PSCustomObject]@{ FullName = 'gilmourltd/gilmour.ltd'; Visibility = 'private' })
                }
                Mock Test-MainstayProtection { $false }
                Mock Test-MainstayRepositoryHasBranch { $true }
                Mock New-MainstayProtection { throw 'Upgrade to GitHub Pro' }
            }
        }

        It 'Reports the failure rather than terminating the sweep' {
            InModuleScope 'Mainstay' {
                $result = Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User -ErrorAction SilentlyContinue
                $result.Action | Should -Be 'Failed'
            }
        }

        It 'Captures the failure reason' {
            InModuleScope 'Mainstay' {
                $result = Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User -ErrorAction SilentlyContinue
                $result.Reason | Should -Match 'Upgrade to GitHub Pro'
            }
        }

        It 'Continues past a failure to the next repository' {
            InModuleScope 'Mainstay' {
                Mock Get-MainstayRepository {
                    @(
                        [PSCustomObject]@{ FullName = 'gilmourltd/gilmour.ltd'; Visibility = 'private' }
                        [PSCustomObject]@{ FullName = 'jakehildreth/Other'; Visibility = 'public' }
                    )
                }
                $result = @(Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User -ErrorAction SilentlyContinue)
                $result | Should -HaveCount 2
            }
        }
    }

    Context 'When redaction is requested' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Get-MainstayRepository {
                    @(
                        [PSCustomObject]@{ FullName = 'jakehildreth/LocksmithPro'; Visibility = 'private' }
                        [PSCustomObject]@{ FullName = 'jakehildreth/Locksmith2'; Visibility = 'public' }
                    )
                }
                Mock Test-MainstayProtection { $true }
                Mock Test-MainstayRepositoryHasBranch { $true }
                Mock New-MainstayProtection { }
            }
        }

        It 'Does not emit the name of a private repository' {
            InModuleScope 'Mainstay' {
                $result = Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User -RedactPrivateName
                ($result | ForEach-Object { $_.Repository }) -join ' ' | Should -Not -Match 'LocksmithPro'
            }
        }

        It 'Still emits the name of a public repository' {
            InModuleScope 'Mainstay' {
                $result = Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User -RedactPrivateName
                ($result | ForEach-Object { $_.Repository }) | Should -Contain 'jakehildreth/Locksmith2'
            }
        }
    }

    Context 'When redaction is requested with a salt' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Get-MainstayRepository {
                    @([PSCustomObject]@{ FullName = 'jakehildreth/LocksmithPro'; Visibility = 'private' })
                }
                Mock Test-MainstayProtection { $true }
                Mock Test-MainstayRepositoryHasBranch { $true }
                Mock New-MainstayProtection { }
            }
        }

        It 'Produces a marker that differs from the unsalted form' {
            InModuleScope 'Mainstay' {
                $salted = Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User -RedactPrivateName -RedactionSalt 'pepper'
                $unsalted = Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User -RedactPrivateName -WarningAction SilentlyContinue
                $salted.Repository | Should -Not -Be $unsalted.Repository
            }
        }

        It 'Does not warn when a salt is supplied' {
            InModuleScope 'Mainstay' {
                $warnings = @()
                Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User -RedactPrivateName -RedactionSalt 'pepper' -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
                $warnings | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When redaction is requested without a salt' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Get-MainstayRepository {
                    @([PSCustomObject]@{ FullName = 'jakehildreth/LocksmithPro'; Visibility = 'private' })
                }
                Mock Test-MainstayProtection { $true }
                Mock Test-MainstayRepositoryHasBranch { $true }
                Mock New-MainstayProtection { }
            }
        }

        It 'Warns that the markers can be guessed' {
            InModuleScope 'Mainstay' {
                $warnings = @()
                Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User -RedactPrivateName -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
                ($warnings -join ' ') | Should -Match 'salt'
            }
        }

        It 'Does not warn when redaction is not requested' {
            InModuleScope 'Mainstay' {
                $warnings = @()
                Invoke-MainstaySweep -Token 'x' -Owner 'jakehildreth' -OwnerType User -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
                $warnings | Should -BeNullOrEmpty
            }
        }
    }
}
