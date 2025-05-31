<#
.SYNOPSIS
    This script provides a class for interacting with the Tenable REST API.

.DESCRIPTION
    The PSTenableIE class allows you to interact with the Tenable REST API, providing methods to retrieve paginated results and specific deviances from the API.
    It includes properties for the API key, tenant FQDN, content type, profile ID, infrastructure ID, and directory ID. The class also includes a static method
    to create an instance with default values.
    The script includes PowerShell functions that instantiate the class and call the class methods so you don't need to interact with the class directly.
    If you want to use the class directly, you can import it as a module and create an instance of the class using the static method or the constructor.

.EXAMPLE
    Import-Module PSTenableIE
    using module PSTenableIE
    $tapi = [PSTenableIE]::ConstructWithDefaults("your_api_key", "your_tenant_fqdn")

.EXAMPLE
    Import-Module PSTenableIE
    using module PSTenableIE
    $tapi = [PSTenableIE]::new("your_api_key", "your_tenant_fqdn", "application/json", 1, 1, 1)

.EXAMPLE
    $deviances = $tapi.GetAllDirectoryDeviances("infrastructure_id", "directory_id")
    $specificDeviances = $tapi.GetSpecificCheckerDeviances("checker_id", "profile_id", "infrastructure_id", "directory_id")

.EXAMPLE
    Import-Module PSTenableIE
    $tapi = New-PSTenableIE -ApiKey "your_api_key" -TenantFqdn "your_tenant_fqdn" -ContentType "application/json" -ProfileId 1 -InfrastructureId 1 -DirectoryId 1
    $PasswordWeaknesses = Get-SpecificCheckerDeviances -Tapi $tapi -CheckerId 50

.NOTES
    Version     Date        Author          Comments
    -------     ----------  -------------- ----------------
    1.0         2025-04-04  Ray Storer     Initial
    1.1         2025-04-05  Ray Storer     Added GetAllDirectoryDeviances method
    1.2         2025-04-05  Ray Storer     Added GetSpecificCheckerDeviances method
    1.3         2025-04-05  Ray Storer     Added error handling for API requests
    1.4         2025-04-05  Ray Storer     Added static method ConstructWithDefaults
    1.5         2025-04-05  Ray Storer     Added New-PSTenableIE function for easier instantiation
    1.6         2025-04-05  Ray Storer     Added Get-AllDirectoryDeviances and Get-SpecificCheckerDeviances functions
    1.7         2025-04-05  Ray Storer     Added usage examples for the class and functions
    1.8         2025-04-05  Ray Storer     Added Update-ADObjectByCheckerId function
    1.8.1       2025-04-20  Ray Storer     Added GetCheckerReasons function and Get-PSTIECheckerReasons function and updated the module manifest
    1.8.2       2025-04-27  Ray Storer     Updated GetCheckerReasons function to return a hashtable of reasons instead of an array list
    1.8.3       2025-05-01  Ray Storer     Added GetADObjectById function to the Class and Get-PSTIEADObjectById function and updated the module manifest
    1.8.4       2025-05-14  Ray Storer     Added Get-PSTIEAllCheckerInstances function

TODO:
    - Implement additional error handling for API requests
    - Add more methods and PowerShell functions for other Tenable APIs
    - Consider implementing a retry mechanism for failed requests
    - Add support for other HTTP methods (POST, PUT, DELETE) as needed
    - Consider adding logging functionality for API requests and responses
    - Implement a method to refresh the API key if needed
#>
class PSTenableIE {
    #region Properties
    [string]$ApiKey
    [string]$TenantFqdn
    [string]$ContentType
    [string]$ProfileId
    [string]$InfrastructureId
    [string]$DirectoryId
    [string]$Version = "1.8.4"
    [string]$Author = "Ray Storer"
    [string]$Copyright = "Copyright © 2025 Ray Storer. All rights reserved."
    [string]$License = "This script is licensed under the Apache 2.0 License (https://www.apache.org/licenses/LICENSE-2.0)."
    [string]$Description = "Class for interacting with the Tenable REST API."
    #endregion

    PSTenableIE(
        [string]$apiKey,
        [string]$tenantFqdn,
        [string]$contentType,
        [int]$profileId,
        [int]$infrastructureId,
        [int]$directoryId) {
        # Constructor to initialize the API key and base URL
        if (-not $apiKey) {
            throw "API key is required."
        }
        if (-not $tenantFqdn) {
            throw "Tenant FQDN is required."
        }

        $this.ApiKey = $apiKey
        $this.TenantFqdn = $tenantFqdn
        if (-not $contentType) {
            $this.ContentType = "application/json"
        } else {
            $this.ContentType = $contentType
        }
        if (-not $profileId) {
            $this.ProfileId = "1"
        } else {
            $this.ProfileId = $profileId.ToString()
        }
        if (-not $infrastructureId) {
            $this.InfrastructureId = "1"
        } else {
            $this.InfrastructureId = $infrastructureId.ToString()
        }
        if (-not $directoryId) {
            $this.DirectoryId = "1"
        } else {
            $this.DirectoryId = $directoryId.ToString()
        }
    }

    static [PSTenableIE] ConstructWithDefaults(
        [string]$apiKey,
        [string]$tenantFqdn) {
        # Static method to create an instance of the class with default values
        return [PSTenableIE]::new($apiKey, $tenantFqdn, "application/json", 1, 1, 1)
    }

    [string]About() {
        <#
        .SYNOPSIS
            Returns a string describing the PSTenableIE class.
        #>
        return "Version: $($this.Version)`nAuthor: $($this.Author)`nCopyright: $($this.Copyright)`nDescription: $($this.Description)`n"
    }

    [System.Collections.ArrayList]GetPagedResults(
        [string]$url,
        [System.Collections.Hashtable]$headers,
        [string]$method) {
        <#
        .SYNOPSIS
            This method retrieves paginated results from the Tenable REST API.
        #>
        if (-not $url) {
            throw "URL is required."
        }
        if (-not $headers) {
            throw "Headers are required."
        }
        if (-not $method) {
            throw "HTTP method is required."
        }

        $results = New-Object System.Collections.ArrayList
        
        $wrp = @{
            Method = $method
            UseBasicParsing = $true
            Uri = $url
            Headers = $headers
            ContentType = $this.ContentType
        }

        $response = Invoke-WebRequest @wrp
        if ($response.StatusCode -ne 200) {
            Write-Error "Failed to retrieve data from Tenable API. Status code: $($response.StatusCode)"
            return $null
        }
        # Check if the response contains pagination headers
        if (-not $response.Headers.'x-pagination-total-count') {
            $jsonResponse = $response.Content | ConvertFrom-Json

            if ($jsonResponse.Count -gt 1) {
                $results.AddRange( $jsonResponse ) | Out-Null
            } elseif ($jsonResponse) {
                $results.Add( $jsonResponse ) | Out-Null                
            }
            return $results
        } # else
        [int]$totalResults = $response.Headers.'x-pagination-total-count'
        [int]$pageSize = $response.Headers.'x-pagination-per-page'
        [int]$numberOfPages = [math]::Ceiling($totalResults / $pageSize)
    
        $results.AddRange( ($response.Content | ConvertFrom-Json) ) | Out-Null
        if ($totalResults -gt $pageSize) {
            for ($i = 2; $i -le $numberOfPages; $i++) {
                $pageUrl = $url + "?page=$i"
                $wrp2 = @{
                    Method = $method
                    UseBasicParsing = $true
                    Uri = $pageUrl
                    Headers = $headers
                    ContentType = $this.ContentType
                }
                $response = Invoke-WebRequest @wrp2
                if ($response.StatusCode -ne 200) {
                    Write-Error "Failed to retrieve data from Tenable API. Status code: $($response.StatusCode)"
                    return $null
                }
                
                $results.AddRange( ($response.Content | ConvertFrom-Json) ) | Out-Null
            }
        }
    
        return $results   
    }

    [System.Collections.ArrayList]GetAllDirectoryDeviances() {
        <#
        .SYNOPSIS
            Retrieves all deviances from the Tenable REST API for the specified directory infrastructure.
        .LINK https://developer.tenable.com/reference/get_api-infrastructures-infrastructureid-directories-directoryid-deviances
        .NOTES
            TODO:
                1. Possibly implement the following query parameters:
                    - perPage [string]
                    - batchSize [string]
                    - lastIdentifierSeen [string]
                    - resolved [string]
        #>
        [string]$url = "https://$($this.TenantFqdn)/api/infrastructures/$($this.InfrastructureId)/directories/$($this.DirectoryId)/deviances"
        return $this.GetPagedResults($url, @{'accept'=$this.ContentType; 'x-api-key'=$this.ApiKey}, 'GET')
    }

    [System.Collections.ArrayList]GetSpecificCheckerDeviances([string]$checkerId) {
        <#
        .SYNOPSIS
            Retrieves all deviances from the Tenable REST API for the specified checker id, profile id, directory id, and infrastructure id.
        .LINK https://developer.tenable.com/reference/get_api-profiles-profileid-infrastructures-infrastructureid-directories-directoryid-checkers-checkerid-deviances
        .NOTES
            TODO:
                1. Possibly implement the following query parameters:
                    - perPage [string]
                    - page [string]
        #>
        if (-not $checkerId) {
            throw "Checker ID is required."
        }

        [string]$url = "https://$($this.TenantFqdn)/api/profiles/$($this.ProfileId)/infrastructures/$($this.InfrastructureId)/directories/$($this.DirectoryId)/checkers/$($checkerId)/deviances"
        return $this.GetPagedResults($url, @{'accept'=$this.ContentType; 'x-api-key'=$this.ApiKey}, 'GET')
    }

    [System.Collections.Hashtable]GetCheckerReasons([string]$checkerId) {
        <#
        .SYNOPSIS
            Retrieves all reasons from the Tenable REST API for the specified checker id, profile id, directory id, and infrastructure id.
        .LINK https://developer.tenable.com/reference/get_api-profiles-profileid-infrastructures-infrastructureid-directories-directoryid-checkers-checkerid-reasons
        #>
        if (-not $checkerId) {
            throw "Checker ID is required."
        }

        [string]$url = "https://$($this.TenantFqdn)/api/profiles/$($this.ProfileId)/checkers/$($checkerId)/reasons"
        [System.Collections.ArrayList]$alReasons = $this.GetPagedResults($url, @{'accept'=$this.ContentType; 'x-api-key'=$this.ApiKey}, 'GET')
        [System.Collections.Hashtable]$hashtable = @{}
        foreach ($reason in $alReasons) {
            if ($hashtable.ContainsKey($reason.id)) {
                Write-Verbose "Duplicate reason ID found: $($reason.id) - skipping."
                continue
            }
            $hashtable[$reason.id] = $reason
        }
        return $hashtable
    }


    [PSCustomObject]GetADObjectById([string]$adObjectId) {
        <#
        .SYNOPSIS
            Retrieves an ADObject from the Tenable API for the specified AD Object id.
        .LINK https://developer.tenable.com/reference/get_api-directories-directoryid-ad-objects-id
        .PARAMETER ADObjectId
            The ID of the ADObject as a string.
        #>
        if (-not $adObjectId) {
            throw "ADObject ID is required."
        }

        [string]$url = "https://$($this.TenantFqdn)/api/directories/$($this.DirectoryId)/ad-objects/$($adObjectId)"
        return ($this.GetPagedResults($url, @{'accept'=$this.ContentType; 'x-api-key'=$this.ApiKey}, 'GET'))[0]
    }

    [PSCustomObject[]]UpdateADObjectByCheckerId(
        [string]$ADObjectId,
        [string]$CheckerId,
        [string]$IgnoreUntil
    ) {
        <#
        .SYNOPSIS
            Updates a ignoreUntil date of the specific ADObject for the specified checker in the Tenable API.
        .PARAMETER CheckerId
            The ID of the deviances to update.
        .PARAMETER ADObjectId
            The ID of the ADObject to update.
        .PARAMETER IgnoreUntil
            The UTC date to ignore this ADObject for this check in the form of 2025-01-31T23:59:59Z
        #>
        if (-not $ADObjectId) {
            throw "ADObject ID is required."
        }
        if (-not $CheckerId) {
            throw "Checker ID is required."
        }
        if (-not $IgnoreUntil) {
            throw "IgnoreUntil date is required."
        }
        $url = "https://$($this.TenantFqdn)/api/profiles/$($this.ProfileId)/checkers/$($CheckerId)/ad-objects//$($ADObjectId)/deviances"
        $body = @{
            ignoreUntil = $IgnoreUntil
        } | ConvertTo-Json

        $response = Invoke-WebRequest -Method Patch -UseBasicParsing -Uri $url `
            -Headers @{'accept'=$this.ContentType; 'x-api-key'=$this.ApiKey} `
            -ContentType $this.ContentType -Body $body

        if ($response.StatusCode -ne 200) {
            Write-Error "Failed to update deviances. Status code: $($response.StatusCode)"
            return $null
        }

        return ($response.Content | ConvertFrom-Json)
    }

    [PSCustomObject[]]GetAllCheckerInstances() {
        <#
        .SYNOPSIS
            Retrieves all checker instances from the Tenable API.
        .LINK https://developer.tenable.com/reference/get_api-checkers
        #>
        [string]$url = "https://$($this.TenantFqdn)/api/checkers"
        return $this.GetPagedResults($url, @{'accept'=$this.ContentType; 'x-api-key'=$this.ApiKey}, 'GET')
    }
}


function New-PSTenableIE {
    <#
    .SYNOPSIS
        Creates a new instance of the PSTenableIE class.
    .PARAMETER ApiKey
        The API key for authentication.
    .PARAMETER TenantFqdn
        The FQDN of the Tenable tenant.
    .PARAMETER ContentType
        The content type for the API requests. Defaults to "application/json".
    .PARAMETER ProfileId
        The profile ID for the API requests. Defaults to 1.
    .PARAMETER InfrastructureId
        The infrastructure ID for the API requests. Defaults to 1.
    .PARAMETER DirectoryId
        The directory ID for the API requests. Defaults to 1.
    #>
    param (
        [Parameter(Mandatory=$true,HelpMessage="API key is required.")]
        [ValidateNotNullOrEmpty()]
        [string]$ApiKey,
        [Parameter(Mandatory=$true,HelpMessage="Tenant FQDN is required.")]
        [ValidateNotNullOrEmpty()]
        [string]$TenantFqdn,
        [Parameter(Mandatory=$false,HelpMessage="Content type for API requests. Defaults to 'application/json'.")]
        [string]$ContentType = "application/json",
        [Parameter(Mandatory=$false,HelpMessage="Profile ID for API requests. Defaults to 1.")]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ProfileId = 1,
        [Parameter(Mandatory=$false,HelpMessage="Infrastructure ID for API requests. Defaults to 1.")]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$InfrastructureId = 1,
        [Parameter(Mandatory=$false,HelpMessage="Directory ID for API requests. Defaults to 1.")]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$DirectoryId = 1
    )

    return [PSTenableIE]::new($ApiKey, $TenantFqdn, $ContentType, $ProfileId, $InfrastructureId, $DirectoryId)
}

function Get-PSTIEAllDirectoryDeviances {
    <#
    .SYNOPSIS
        Retrieves all directory deviances from the Tenable API.
    .PARAMETER Tapi
        The PSTenableIE object.
    #>
    param (
        [Parameter(Mandatory=$true,HelpMessage="PSTenableIE object is required.")]
        [PSTenableIE]$Tapi
    )

    return $Tapi.GetAllDirectoryDeviances($Tapi.InfrastructureId, $Tapi.DirectoryId)
}

function Get-PSTIEAllCheckerInstances {
    <#
    .SYNOPSIS
        Retrieves all checker instances from the Tenable API.
    .PARAMETER Tapi
        The PSTenableIE object.
    #>
    param (
        [Parameter(Mandatory=$true,HelpMessage="PSTenableIE object is required.")]
        [PSTenableIE]$Tapi
    )

    return $Tapi.GetAllCheckerInstances()
}

function Get-PSTIECheckerReasons {
    <#
    .SYNOPSIS
        Retrieves checker reasons from the Tenable API.
    .PARAMETER Tapi
        The PSTenableIE object.
    .PARAMETER CheckerId
        The ID of the checker.
    #>
    param (
        [Parameter(Mandatory=$true,HelpMessage="PSTenableIE object is required.")]
        [PSTenableIE]$Tapi,
        [Parameter(Mandatory=$true,HelpMessage="Checker ID is required and needs a value greater than 0.")]
        [ValidateRange(1, [int]::MaxValue)]
        [uint32]$CheckerId
    )

    return $Tapi.GetCheckerReasons($CheckerId.ToString())
}

function Get-PSTIESpecificCheckerDeviances {
    <#
    .SYNOPSIS
        Retrieves specific checker deviances from the Tenable API.
    .PARAMETER Tapi
        The PSTenableIE object.
    .PARAMETER CheckerId
        The ID of the checker.
    #>
    param (
        [Parameter(Mandatory=$true,HelpMessage="PSTenableIE object is required.")]
        [PSTenableIE]$Tapi,
        [Parameter(Mandatory=$true,HelpMessage="Checker ID is required and needs a value greater than 0.")]
        [ValidateRange(1, [int]::MaxValue)]
        [uint32]$CheckerId
    )

    return $Tapi.GetSpecificCheckerDeviances($CheckerId.ToString())
}

function Get-PSTIEPagedData {
    <#
    .SYNOPSIS
        Get paged data from the Tenable IE API
    .PARAMETER Tapi
       The PSTenableIE object
    .PARAMETER UrlPath
        The Tenable API URL path and query string (after https://customer.tenable.ad/)
    .PARAMETER ContentType
        Defaults to 'application/json'
    .PARAMETER Method
        Defaults to 'GET'
     .PARAMETER Headers
        Defaults to @{'accept'=$Tapi.ContentType; 'x-api-key'=$Tapi.ApiKey}
    #>
    param (
        [Parameter(Mandatory=$true,HelpMessage="PSTenableIE object is required.")]
        [PSTenableIE]$Tapi,
        [Parameter(Mandatory=$true,HelpMessage="The Tenable API URL path and query string (after https://customer.tenable.ad/")]
        [string]$UrlPath,
        [Parameter(Mandatory=$false,HelpMessage="defaults to 'application/json'")]
        [string]$ContentType,
        [Parameter(Mandatory=$false,HelpMessage="defaults to 'GET'")]
        [string]$Method='GET',
        [Parameter(Mandatory=$false,HelpMessage="Headers, if different from default")]
        [System.Collections.Hashtable]$headers
    )
    if (-not $headers) {
        $headers = @{'accept'=$Tapi.ContentType; 'x-api-key'=$Tapi.ApiKey}
    }
    if (-not $ContentType) {
        $ContentType=$Tapi.ContentType
    }
    else {
        $Tapi.ContentType = $ContentType
    }
    $Tapi.GetPagedResults("https://$($tapi.TenantFQDN)/$($UrlPath)", $headers, $method)
}

function Get-PSTIEADObjectById {
    <#
    .SYNOPSIS
        Retrieves an ADObject from the Tenable API for the specified AD Object id.
    .PARAMETER Tapi
        The PSTenableIE object.
    .PARAMETER ADObjectId
        The ID of the ADObject as a string.
    #>
    param (
        [Parameter(Mandatory=$true,HelpMessage="PSTenableIE object is required.")]
        [PSTenableIE]$Tapi,
        [Parameter(Mandatory=$true,HelpMessage="ADObject ID is required.")]
        [string]$ADObjectId
    )

    return $Tapi.GetADObjectById($ADObjectId)
}

function Update-PSTIEADObjectByCheckerId {
    <#
    .SYNOPSIS
        Updates the ignoreUntil date of a specific ADObject for the specified checker in the Tenable API.
    .PARAMETER Tapi
        The PSTenableIE object.
    .PARAMETER CheckerId
        The ID of the checker.
    .PARAMETER ADObjectId
        The ID of the ADObject to update.
    .PARAMETER IgnoreUntil
        The UTC date to ignore this ADObject for this check in the form of 2025-01-31T23:59:59Z
    #>
    param (
        [Parameter(Mandatory=$true,HelpMessage="PSTenableIE object is required.")]
        [PSTenableIE]$Tapi,
        [Parameter(Mandatory=$true,HelpMessage="Checker ID is required and needs a value greater than 0.")]
        [ValidateRange(1, [int]::MaxValue)]
        [uint32]$CheckerId,
        [Parameter(Mandatory=$true,HelpMessage="ADObject ID is required and needs a value greater than 0.")]
        [ValidateRange(1, [int]::MaxValue)]
        [uint32]$ADObjectId,
        [Parameter(Mandatory=$true,HelpMessage="IgnoreUntil date is required.")]
        [ValidateScript({[DateTime]::Now.AddDays(1) -le $_ -and $_ -lt [DateTime]::Now.AddYears(1)})]
        [datetime]$IgnoreUntil
    )

    [string]$StrIgnoreUntil = $IgnoreUntil.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    return $Tapi.UpdateADObjectByCheckerId($ADObjectId.ToString(), $CheckerId.ToString(), $StrIgnoreUntil) 
}