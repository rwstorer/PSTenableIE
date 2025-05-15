<#
.SYNOPSIS
    Get unlinked, disabled, or orphaned GPOs from Tenable Identity Exposure REST API.
.DESCRIPTION
    This script retrieves unlinked, disabled, or orphaned GPOs from Tenable Identity Exposure using the REST API.
    It processes the results and outputs them in a structured format.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [int]$CheckerId=2,
    [Parameter(Mandatory=$false)]
    [bool]$UseLocalDatetime=$false,
    [Parameter(Mandatory=$false)]
    [string]$ApiKey=$env:TENABLE_API_KEY,
    [Parameter(Mandatory=$false)]
    [string]$TenantFqdn=$env:TENABLE_API_FQDN,
    [Parameter(Mandatory=$false)]
    [string]$ContentType="application/json",
    [Parameter(Mandatory=$false)]
    [int]$ProfileId=1,
    [Parameter(Mandatory=$false)]
    [int]$InfrastructureId=1,
    [Parameter(Mandatory=$false)]
    [int]$DirectoryId=1,
    [Parameter(Mandatory=$false)]
    [bool]$WantAdObjectType=$true,
    [Parameter(Mandatory=$false)]
    [string]$ADObjectCsvPath=$null
)

Import-Module .\PSTenableIE.psd1

function Get-UnlinkedDisabledOrphanGPO {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList]$deviances
    )

    [Int64]$R_DISABLED_GPO = 131
    [Int64]$R_ORPHAN_GPO = 128
    [Int64]$R_MORPHED_GPO = 127
    [Int64]$R_UNLINKED_GPO = 126

    $dt = New-Object System.Data.DataTable
    $dt.TableName = 'Deviances'
    $dt.Columns.Add('ID', [int]) | Out-Null
    $dt.Columns.Add('EventDate', [datetime]) | Out-Null
    $dt.Columns.Add('reason', [string]) | Out-Null
    $dt.Columns.Add('adObjectId', [int]) | Out-Null
    $dt.Columns.Add('ADObjectType', [string]) | Out-Null   # computer, user
    $dt.Columns.Add('GpoPath', [string]) | Out-Null        # 126, 127, 128, 131
    $dt.Columns.Add('RemainingPart', [string]) | Out-Null  # 128
    $dt.Columns.Add('DuplicatedFile', [string]) | Out-Null # 127
    # TODO: Add more columns as needed
    # resolvedEventId, resolvedAt, ignoreUntil, createdEventId

    [System.Collections.Hashtable]$reasons = Get-PSTIECheckerReasons -Tapi $tapi -CheckerId $CHECKER_ID

    [int]$i = 0
    [int]$idx = -1
    [int]$idx2 = -1
    foreach ($deviance in $deviances) {
        $i++
        $idx = -1
        $idx2 = -1
        [System.Data.DataRow]$row = $dt.NewRow()
        $row.ID = $i
        if ($UseLocalDatetime) {
            $row.EventDate = (Get-Date -Date $deviance.eventDate).ToLocalTime()
        } else {
            $row.EventDate = $deviance.eventDate
        }

        $row.ADObjectType = [DBNull]::Value
        $row.GpoPath = [DBNull]::Value
        $row.RemainingPart = [DBNull]::Value
        $row.DuplicatedFile = [DBNull]::Value

        switch ($deviance.reasonId) {
            $R_UNLINKED_GPO {
                $idx = [Array]::IndexOf($deviance.attributes.name, 'GpoPath')
                $row.GpoPath = $deviance.attributes[$idx].value
            }
            $R_MORPHED_GPO { 
                #Duplicate 
                $idx = [Array]::IndexOf($deviance.attributes.name, 'GpoPath')
                $row.GpoPath = $deviance.attributes[$idx].value
                $idx2 = [Array]::IndexOf($deviance.attributes.name, 'DuplicatedFile')
                $row.DuplicatedFile = $deviance.attributes[$idx2].value}
            $R_ORPHAN_GPO {
                # Missing
                $idx = [Array]::IndexOf($deviance.attributes.name, 'GpoPath')
                $row.GpoPath = $deviance.attributes[$idx].value
                $idx2 = [Array]::IndexOf($deviance.attributes.name, 'RemainingPart')
                $row.RemainingPart = $deviance.attributes[$idx2].value
            }
            $R_DISABLED_GPO { 
                $idx = [Array]::IndexOf($deviance.attributes.name, 'GpoPath')
                $row.GpoPath = $deviance.attributes[$idx].value
            }
            Default {
                # Unknown
                Write-Warning "Unknown reasonId: $($deviance.reasonId)"
            }
        }
        $row.reason = ($reasons[$deviance.reasonId]).codename
        $dt.Rows.Add($row)
    }

    # TODO: Add the wantAdObjectType logic here

    # emit the DataTable
    $dt | ForEach-Object {
        [PSCustomObject]@{
            ID              = $_.ID
            EventDate       = $_.EventDate
            Reason          = $_.reason
            ADObjectId      = $_.adObjectId
            ADObjectType    = $_.adObjectType
            GpoPath         = $_.GpoPath
            RemainingPart   = $_.RemainingPart
            DuplicatedFile  = $_.DuplicatedFile
        }
    }
}

$tapi = New-PSTenableIE -ApiKey $ApiKey -TenantFqdn $TenantFqdn -ProfileId $ProfileId -InfrastructureId $InfrastructureId -DirectoryId $DirectoryId -UseLocalDatetime $UseLocalDatetime -ContentType $ContentType

# In my environment, this checker ID is 2. Yours may differ.
[int]$CHECKER_ID = $CheckerId
[System.Collections.ArrayList]$deviances = Get-PSTIESpecificCheckerDeviances -Tapi $tapi -CheckerId $CHECKER_ID
Get-UnlinkedDisabledOrphanGPO -deviances $deviances