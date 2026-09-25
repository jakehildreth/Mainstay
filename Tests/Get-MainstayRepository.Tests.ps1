BeforeAll {
    $ModuleRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $ModuleRoot 'Mainstay.psd1') -Force -ErrorAction Stop
}

Describe 'Get-MainstayRepository' {

    Context 'When filtering the repository list' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Invoke-MainstayApi {
                    @(
                        [PSCustomObject]@{
                            full_name = 'jakehildreth/Locksmith2'; name = 'Locksmith2'
                            fork = $false; archived = $false; private = $false
                            default_branch = 'main'; permissions = @{ admin = $true }
                        }
                        [PSCustomObject]@{
                            full_name = 'jakehildreth/Locksmith'; name = 'Locksmith'
                            fork = $false; archived = $false; private = $false
                            default_branch = 'main'; permissions = @{ admin = $true }
                        }
                        [PSCustomObject]@{
                            full_name = 'jakehildreth/sliver'; name = 'sliver'
                            fork = $true; archived = $false; private = $false
                            default_branch = 'master'; permissions = @{ admin = $true }
                        }
                        [PSCustomObject]@{
                            full_name = 'jakehildreth/OldThing'; name = 'OldThing'
                            fork = $false; archived = $true; private = $false
                            default_branch = 'main'; permissions = @{ admin = $true }
                        }
                        [PSCustomObject]@{
                            full_name = 'jakehildreth/ADCStencil'; name = 'ADCStencil'
                            fork = $false; archived = $false; private = $true
                            default_branch = ''; permissions = @{ admin = $true }
                        }
                        [PSCustomObject]@{
                            full_name = 'jakehildreth/NotMine'; name = 'NotMine'
                            fork = $false; archived = $false; private = $false
                            default_branch = 'main'; permissions = @{ admin = $false }
                        }
                    )
                } -ParameterFilter { $Path -like 'users/jakehildreth/repos*' }

                Mock Invoke-MainstayApi { @() }
            }
        }

        It 'Includes an eligible source repository' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -OwnerType User
                $result.FullName | Should -Contain 'jakehildreth/Locksmith2'
                $result.FullName | Should -Contain 'jakehildreth/Locksmith'
            }
        }

        It 'Excludes repositories named in ExcludeRepository' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -OwnerType User -ExcludeRepository 'Locksmith'
                $result.FullName | Should -Not -Contain 'jakehildreth/Locksmith'
            }
        }

        It 'Excludes forks' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -OwnerType User
                $result.FullName | Should -Not -Contain 'jakehildreth/sliver'
            }
        }

        It 'Excludes archived repositories' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -OwnerType User
                $result.FullName | Should -Not -Contain 'jakehildreth/OldThing'
            }
        }

        It 'Excludes repositories with no default branch' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -OwnerType User
                $result.FullName | Should -Not -Contain 'jakehildreth/ADCStencil'
            }
        }

        It 'Excludes repositories where the caller is not an admin' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -OwnerType User
                $result.FullName | Should -Not -Contain 'jakehildreth/NotMine'
            }
        }

        It 'Matches ExcludeRepository without regard to case' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -OwnerType User -ExcludeRepository 'locksmith'
                $result.FullName | Should -Not -Contain 'jakehildreth/Locksmith'
            }
        }

        It 'Reports visibility so downstream redaction can act on it' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -OwnerType User |
                    Where-Object { $_.Name -eq 'Locksmith2' }
                $result.Visibility | Should -Be 'public'
            }
        }
    }

    Context 'When the owner is a user account' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Invoke-MainstayApi { @() } -ParameterFilter { $Path -like 'users/jakehildreth/repos*' }
                Mock Invoke-MainstayApi { throw "unexpected path: $Path" }
            }
        }

        It 'Queries the user repos endpoint for that owner' {
            InModuleScope 'Mainstay' {
                Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -OwnerType User | Out-Null
                Should -Invoke Invoke-MainstayApi -Exactly 1 -ParameterFilter { $Path -like 'users/jakehildreth/repos*' }
            }
        }

        It 'Never queries the authenticated-user or org endpoints' {
            InModuleScope 'Mainstay' {
                Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -OwnerType User | Out-Null
                Should -Invoke Invoke-MainstayApi -Exactly 0 -ParameterFilter { $Path -like 'user/repos*' }
                Should -Invoke Invoke-MainstayApi -Exactly 0 -ParameterFilter { $Path -like 'orgs/*' }
            }
        }
    }

    Context 'When the owner is an organization' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Invoke-MainstayApi {
                    @(
                        [PSCustomObject]@{
                            full_name = 'gilmourltd/product'; name = 'product'
                            fork = $false; archived = $false; private = $false
                            default_branch = 'main'; permissions = @{ admin = $true }
                        }
                    )
                } -ParameterFilter { $Path -like 'orgs/gilmourltd/repos*' }
                Mock Invoke-MainstayApi { throw "unexpected path: $Path" }
            }
        }

        It 'Queries the org repos endpoint and returns its repositories' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'gilmourltd' -OwnerType Org
                Should -Invoke Invoke-MainstayApi -Exactly 1 -ParameterFilter { $Path -like 'orgs/gilmourltd/repos*' }
                $result.FullName | Should -Contain 'gilmourltd/product'
            }
        }

        It 'Never queries the user or authenticated-user endpoints' {
            InModuleScope 'Mainstay' {
                Get-MainstayRepository -Token 'x' -Owner 'gilmourltd' -OwnerType Org | Out-Null
                Should -Invoke Invoke-MainstayApi -Exactly 0 -ParameterFilter { $Path -like 'users/*' }
                Should -Invoke Invoke-MainstayApi -Exactly 0 -ParameterFilter { $Path -like 'user/repos*' }
            }
        }
    }
}
