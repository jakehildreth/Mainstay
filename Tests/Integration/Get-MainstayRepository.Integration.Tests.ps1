# Integration tests. Unlike the unit tests, these call the live GitHub API as
# the Mainstay App installation, proving the endpoints the module uses are ones
# a GitHub App token is actually allowed to call.
#
# They are gated behind the MAINSTAY_INTEGRATION environment variable so a bare
# local Invoke-Pester does not touch the network or need credentials. The CI
# workflow sets it and provides the App credentials.

BeforeAll {
    $ModuleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $ModuleRoot 'Mainstay.psd1') -Force -ErrorAction Stop

    $script:Enabled = $env:MAINSTAY_INTEGRATION -eq '1'
    $script:AppClientId = $env:MAINSTAY_APP_CLIENT_ID
    $script:AppPrivateKey = $env:MAINSTAY_APP_PRIVATE_KEY
    $VerbosePreference = 'Continue'

    # Exchange the App credentials for an installation access token for one
    # account. Mirrors what actions/create-github-app-token does in the sweep.
    function Get-MainstayInstallationToken {
        param(
            [Parameter(Mandatory)][string]$ClientId,
            [Parameter(Mandatory)][string]$PrivateKeyPem,
            [Parameter(Mandatory)][string]$Owner
        )

        $now = [DateTimeOffset]::UtcNow
        $headerJson = '{"alg":"RS256","typ":"JWT"}'
        $header = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($headerJson))
        $payloadObject = @{
            iat = $now.ToUnixTimeSeconds() - 60
            exp = $now.ToUnixTimeSeconds() + 540
            iss = $ClientId
        }
        $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($payloadObject | ConvertTo-Json -Compress)))
        $unsigned = "$header.$payload" -replace '\+', '-' -replace '/', '_' -replace '='

        $keyPem = $PrivateKeyPem
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $rsa.ImportFromPem($keyPem)
        $signature = $rsa.SignData(
            [Text.Encoding]::UTF8.GetBytes($unsigned),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $rsa.Dispose()
        $jwt = "$unsigned.$([Convert]::ToBase64String($signature) -replace '\+', '-' -replace '/', '_' -replace '=')"

        $appHeaders = @{
            Authorization          = "Bearer $jwt"
            Accept                 = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
            'User-Agent'           = 'Mainstay-IntegrationTest'
        }

        $installations = Invoke-RestMethod -Method GET -Uri 'https://api.github.com/app/installations' `
            -Headers $appHeaders -ErrorAction Stop

        # Match by account login, case-insensitively. The payload may be a single
        # object or an array, so iterate explicitly rather than rely on Where-Object
        # pipeline semantics, which differ when only one installation is returned.
        $installation = $null
        foreach ($candidate in @($installations)) {
            if ($candidate.account.login -ieq $Owner) {
                $installation = $candidate
                break
            }
        }

        if (-not $installation) {
            throw "App is not installed on '$Owner'."
        }

        Write-Verbose "Minting installation token for $Owner (installation id $($installation.id))"

        $tokenResponse = Invoke-RestMethod -Method POST `
            -Uri "https://api.github.com/app/installations/$($installation.id)/access_tokens" `
            -Headers $appHeaders -Body '{}' -ContentType 'application/json' -ErrorAction Stop

        return $tokenResponse.token
    }
}

Describe 'Get-MainstayRepository integration' -Skip:($env:MAINSTAY_INTEGRATION -ne '1') {

    Context 'Against the live GitHub API as the App' {

        It 'Enumerates a user account through the installation endpoint, private repos included' {
            $token = Get-MainstayInstallationToken -ClientId $script:AppClientId `
                -PrivateKeyPem $script:AppPrivateKey -Owner 'jakehildreth'

            $repositories = @(InModuleScope 'Mainstay' -Parameters @{ t = $token } {
                param($t)
                Get-MainstayRepository -Token $t -Owner 'jakehildreth' -OwnerType User
            })

            # The point of the regression this guards: a private repo the App owns
            # must be visible. Vixel is the repo that exposed the bug.
            $repositories.FullName | Should -Contain 'jakehildreth/Vixel'
            $repositories.Count | Should -BeGreaterThan 0
        }

        It 'Enumerates an organization account' {
            $token = Get-MainstayInstallationToken -ClientId $script:AppClientId `
                -PrivateKeyPem $script:AppPrivateKey -Owner 'gilmourltd'

            $repositories = @(InModuleScope 'Mainstay' -Parameters @{ t = $token } {
                param($t)
                Get-MainstayRepository -Token $t -Owner 'gilmourltd' -OwnerType Org
            })

            $repositories.FullName | Should -Contain 'gilmourltd/product'
        }
    }
}
