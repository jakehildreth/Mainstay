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
                } -ParameterFilter { $Path -like 'user/repos*' }

                Mock Invoke-MainstayApi { @() }
            }
        }

        It 'Includes an eligible source repository' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth'
                $result.FullName | Should -Contain 'jakehildreth/Locksmith2'
            }
        }

        It 'Excludes repositories named in ExcludeRepository' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -ExcludeRepository 'Locksmith'
                $result.FullName | Should -Not -Contain 'jakehildreth/Locksmith'
            }
        }

        It 'Excludes forks' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth'
                $result.FullName | Should -Not -Contain 'jakehildreth/sliver'
            }
        }

        It 'Excludes archived repositories' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth'
                $result.FullName | Should -Not -Contain 'jakehildreth/OldThing'
            }
        }

        It 'Excludes repositories with no default branch' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth'
                $result.FullName | Should -Not -Contain 'jakehildreth/ADCStencil'
            }
        }

        It 'Excludes repositories where the caller is not an admin' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth'
                $result.FullName | Should -Not -Contain 'jakehildreth/NotMine'
            }
        }

        It 'Matches ExcludeRepository without regard to case' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -ExcludeRepository 'locksmith'
                $result.FullName | Should -Not -Contain 'jakehildreth/Locksmith'
            }
        }

        It 'Reports visibility so downstream redaction can act on it' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth'
                ($result | Where-Object { $_.FullName -eq 'jakehildreth/Locksmith2' }).Visibility |
                    Should -Be 'public'
            }
        }
    }

    Context 'When organizations are requested' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Invoke-MainstayApi { @() } -ParameterFilter { $Path -like 'user/repos*' }
                Mock Invoke-MainstayApi {
                    @(
                        [PSCustomObject]@{
                            full_name = 'gilmourltd/product'; name = 'product'
                            fork = $false; archived = $false; private = $false
                            default_branch = 'main'; permissions = @{ admin = $true }
                        }
                    )
                } -ParameterFilter { $Path -like 'orgs/gilmourltd/repos*' }
                Mock Invoke-MainstayApi { @() }
            }
        }

        It 'Includes repositories from a requested organization' {
            InModuleScope 'Mainstay' {
                $result = Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' -IncludeOrganization 'gilmourltd'
                $result.FullName | Should -Contain 'gilmourltd/product'
            }
        }

        It 'Does not query organizations that were not requested' {
            InModuleScope 'Mainstay' {
                Get-MainstayRepository -Token 'x' -Owner 'jakehildreth' | Out-Null
                Should -Invoke Invoke-MainstayApi -Exactly 0 -ParameterFilter { $Path -like 'orgs/*' }
            }
        }
    }
}
