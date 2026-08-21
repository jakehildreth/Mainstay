$privateFunctions = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$publicFunctions = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($functionFile in @($privateFunctions + $publicFunctions)) {
    try {
        . $functionFile.FullName
    } catch {
        Write-Error -Message "Failed to import '$($functionFile.FullName)': $_"
    }
}

Export-ModuleMember -Function $publicFunctions.BaseName
