BeforeAll {
    $ModuleRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $ModuleRoot 'Mainstay.psd1') -Force -ErrorAction Stop
}

Describe 'Test-MainstayRepositoryHasBranch' {

    Context 'When the repository has at least one branch' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Invoke-MainstayApi { @([PSCustomObject]@{ name = 'main' }) }
            }
        }

        It 'Returns true' {
            InModuleScope 'Mainstay' {
                Test-MainstayRepositoryHasBranch -Token 'x' -FullName 'owner/repo' | Should -BeTrue
            }
        }

        It 'Asks for only one branch' {
            InModuleScope 'Mainstay' {
                Test-MainstayRepositoryHasBranch -Token 'x' -FullName 'owner/repo' | Out-Null
                Should -Invoke Invoke-MainstayApi -Exactly 1 -ParameterFilter { $Path -like '*per_page=1*' }
            }
        }
    }

    Context 'When the repository has no branches' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Invoke-MainstayApi { @() }
            }
        }

        It 'Returns false' {
            InModuleScope 'Mainstay' {
                Test-MainstayRepositoryHasBranch -Token 'x' -FullName 'owner/repo' | Should -BeFalse
            }
        }
    }

    Context 'When the branch listing returns nothing at all' {

        BeforeAll {
            InModuleScope 'Mainstay' {
                Mock Invoke-MainstayApi { $null }
            }
        }

        It 'Returns false rather than throwing' {
            InModuleScope 'Mainstay' {
                Test-MainstayRepositoryHasBranch -Token 'x' -FullName 'owner/repo' | Should -BeFalse
            }
        }
    }
}
