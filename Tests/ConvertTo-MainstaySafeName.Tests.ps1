BeforeAll {
    $ModuleRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $ModuleRoot 'Mainstay.psd1') -Force -ErrorAction Stop
}

Describe 'ConvertTo-MainstaySafeName' {

    Context 'When the repository is public' {

        It 'Returns the full name unchanged' {
            InModuleScope 'Mainstay' {
                ConvertTo-MainstaySafeName -FullName 'jakehildreth/Locksmith2' -Visibility 'public' |
                    Should -Be 'jakehildreth/Locksmith2'
            }
        }

        It 'Returns the full name even when redaction is requested' {
            InModuleScope 'Mainstay' {
                ConvertTo-MainstaySafeName -FullName 'jakehildreth/Locksmith2' -Visibility 'public' -Redact |
                    Should -Be 'jakehildreth/Locksmith2'
            }
        }
    }

    Context 'When the repository is private and redaction is not requested' {

        It 'Returns the full name unchanged' {
            InModuleScope 'Mainstay' {
                ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' |
                    Should -Be 'jakehildreth/LocksmithPro'
            }
        }
    }

    Context 'When the repository is private and redaction is requested' {

        It 'Does not leak the repository name' {
            InModuleScope 'Mainstay' {
                ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact |
                    Should -Not -Match 'LocksmithPro'
            }
        }

        It 'Returns a private marker with an eight character hash' {
            InModuleScope 'Mainstay' {
                ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact |
                    Should -Match '^<private:[0-9a-f]{8}>$'
            }
        }

        It 'Produces the same hash for the same repository across calls' {
            InModuleScope 'Mainstay' {
                $first = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact
                $second = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact
                $first | Should -Be $second
            }
        }

        It 'Produces different hashes for different repositories' {
            InModuleScope 'Mainstay' {
                $first = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact
                $second = ConvertTo-MainstaySafeName -FullName 'jakehildreth/Tierdrop' -Visibility 'private' -Redact
                $first | Should -Not -Be $second
            }
        }
    }
}
