function Invoke-MainstayApi {
    <#
    .SYNOPSIS
        Sends a request to the GitHub REST API.

    .DESCRIPTION
        Wraps Invoke-RestMethod with the headers GitHub requires, and optionally
        walks all pages of a paginated collection endpoint.

    .PARAMETER Token
        A GitHub token with permission for the requested operation.

    .PARAMETER Path
        The API path relative to the API root, for example 'user/repos?per_page=100'.

    .PARAMETER Method
        The HTTP method to use. Defaults to GET.

    .PARAMETER Body
        A hashtable serialised to JSON and sent as the request body.

    .PARAMETER Paginate
        Walk every page of a collection endpoint and return the combined result.

    .OUTPUTS
        System.Management.Automation.PSObject

    .NOTES
        Paging is done by incrementing the page parameter rather than following
        Link headers, because response header capture is not available in
        Windows PowerShell 5.1.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter()]
        [hashtable]$Body,

        [Parameter()]
        [switch]$Paginate
    )

    begin {
        $requestHeaders = @{
            'Authorization'        = "Bearer $Token"
            'Accept'               = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
            'User-Agent'           = 'Mainstay'
        }
    }

    process {
        $pageSize = 100
        $pageNumber = 1
        $collected = [System.Collections.Generic.List[object]]::new()

        while ($true) {
            $requestPath = $Path
            if ($Paginate.IsPresent) {
                $separator = '?'
                if ($Path.Contains('?')) {
                    $separator = '&'
                }
                $requestPath = "$Path$separator" + "page=$pageNumber"
            }

            $parameters = @{
                Uri         = "https://api.github.com/$requestPath"
                Method      = $Method
                Headers     = $requestHeaders
                ErrorAction = 'Stop'
            }

            if ($PSBoundParameters.ContainsKey('Body')) {
                $parameters['Body'] = $Body | ConvertTo-Json -Depth 10
                $parameters['ContentType'] = 'application/json'
            }

            $response = Invoke-RestMethod @parameters

            if (-not $Paginate.IsPresent) {
                return $response
            }

            # installation/repositories wraps its items in a 'repositories' member
            # and reports the total; plain collection endpoints return the page as a
            # bare array. Detect the wrapped shape so both paginate correctly.
            $items = $response
            $total = $null
            if ($response -and $response.PSObject.Properties['repositories'] -and $response.PSObject.Properties['total_count']) {
                $items = $response.repositories
                $total = $response.total_count
            }

            $batch = @($items)
            foreach ($item in $batch) {
                $collected.Add($item)
            }

            if ($null -ne $total) {
                if ($collected.Count -ge $total) {
                    break
                }
            } elseif ($batch.Count -lt $pageSize) {
                break
            }

            $pageNumber++
        }

        return $collected.ToArray()
    }
}
