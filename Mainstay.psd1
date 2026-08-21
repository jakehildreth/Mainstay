@{
    RootModule        = 'Mainstay.psm1'
    ModuleVersion     = '2026.8.210627'
    GUID              = 'f4b2c9d1-5e73-4a86-9c0f-2d81ab3e6547'
    Author            = 'Jake Hildreth'
    CompanyName       = 'Gilmour Technologies Ltd'
    Copyright         = '(c) 2026 Jake Hildreth, Gilmour Technologies Ltd. All rights reserved.'
    Description       = 'Keeps branch protection consistent across every repository you own.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Invoke-MainstaySweep')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('GitHub', 'BranchProtection', 'Rulesets', 'Automation')
            LicenseUri = 'https://github.com/jakehildreth/Mainstay/blob/main/LICENSE'
            ProjectUri = 'https://github.com/jakehildreth/Mainstay'
        }
    }
}
