function ConvertTo-MainstaySafeName {
    <#
    .SYNOPSIS
        Returns a repository name that is safe to write to a public log.

    .DESCRIPTION
        Public repository names are returned unchanged. When redaction is
        requested, a private repository name is replaced with a marker
        containing a short, stable hash of the name.

        The hash is deterministic, so the same repository produces the same
        marker on every run. That allows a repeatedly failing repository to be
        correlated across runs without disclosing which repository it is.

    .PARAMETER FullName
        The owner/name identifier of the repository.

    .PARAMETER Visibility
        Either 'public' or 'private'.

    .PARAMETER Redact
        Replace private repository names with a hashed marker.

    .OUTPUTS
        System.String

    .EXAMPLE
        ConvertTo-MainstaySafeName -FullName 'owner/secret' -Visibility 'private' -Redact

        Returns a marker such as <private:9f2a41c8>.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FullName,

        [Parameter(Mandatory)]
        [ValidateSet('public', 'private')]
        [string]$Visibility,

        [Parameter()]
        [switch]$Redact
    )

    process {
        if (-not $Redact.IsPresent -or $Visibility -ne 'private') {
            return $FullName
        }

        $algorithm = [System.Security.Cryptography.SHA256]::Create()
        try {
            $nameBytes = [System.Text.Encoding]::UTF8.GetBytes($FullName.ToLowerInvariant())
            $hashBytes = $algorithm.ComputeHash($nameBytes)
        } finally {
            $algorithm.Dispose()
        }

        $shortHash = -join ($hashBytes[0..3] | ForEach-Object { $_.ToString('x2') })

        return "<private:$shortHash>"
    }
}
