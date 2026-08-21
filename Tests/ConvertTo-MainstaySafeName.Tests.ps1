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

        It 'Ignores the salt' {
            InModuleScope 'Mainstay' {
                ConvertTo-MainstaySafeName -FullName 'jakehildreth/Locksmith2' -Visibility 'public' -Redact -Salt 'pepper' |
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

    Context 'When a salt is supplied' {

        It 'Still returns a well formed marker' {
            InModuleScope 'Mainstay' {
                ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact -Salt 'pepper' |
                    Should -Match '^<private:[0-9a-f]{8}>$'
            }
        }

        It 'Produces a stable hash across calls so runs can be correlated' {
            InModuleScope 'Mainstay' {
                $first = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact -Salt 'pepper'
                $second = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact -Salt 'pepper'
                $first | Should -Be $second
            }
        }

        It 'Produces a different hash than the unsalted form' {
            InModuleScope 'Mainstay' {
                $salted = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact -Salt 'pepper'
                $unsalted = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact
                $salted | Should -Not -Be $unsalted
            }
        }

        It 'Produces a different hash for a different salt' {
            InModuleScope 'Mainstay' {
                $first = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact -Salt 'pepper'
                $second = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact -Salt 'oregano'
                $first | Should -Not -Be $second
            }
        }

        It 'Still distinguishes between repositories' {
            InModuleScope 'Mainstay' {
                $first = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact -Salt 'pepper'
                $second = ConvertTo-MainstaySafeName -FullName 'jakehildreth/Tierdrop' -Visibility 'private' -Redact -Salt 'pepper'
                $first | Should -Not -Be $second
            }
        }

        It 'Defeats a guess made without the salt' {
            InModuleScope 'Mainstay' {
                $published = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact -Salt 'pepper'
                $guess = ConvertTo-MainstaySafeName -FullName 'jakehildreth/LocksmithPro' -Visibility 'private' -Redact
                $guess | Should -Not -Be $published
            }
        }
    }
}
