# This script uses the System.Data assembly to create a DataTable object.
# PowerShell 7+ does not require explicit loading of this assembly, but PowerShell 5.1 and earlier versions do require it.
# If you are using PowerShell 5.1 or earlier, uncomment the following line to load the assembly:
# Add-Type -AssemblyName 'System.Data'

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [int]$CheckerId=59,
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

function Get-ShadowCredentials {
[CmdletBinding(DefaultParameterSetName='Default')]
param (
    [Parameter(Mandatory=$true, ParameterSetName='Default')]
    [Parameter(Mandatory=$true, ParameterSetName='GetADObjectType')]
    [System.Collections.ArrayList]$Deviances,
    [Parameter(Mandatory=$false, ParameterSetName='GetADObjectType')]
    [Parameter(Mandatory=$false, ParameterSetName='Default')]
    [bool]$UseLocalDatetime=$false,

    [Parameter(Mandatory=$false, ParameterSetName='GetADObjectType')]
    [bool]$WantAdObjectType=$true,
    [Parameter(Mandatory=$false, ParameterSetName='GetADObjectType')]
    [string]$ADObjectCsvPath=$null
)
    [System.Collections.Hashtable]$reasons = Get-PSTIECheckerReasons -Tapi $tapi -CheckerId $CHECKER_ID

    $dt = New-Object System.Data.DataTable
    $dt.TableName = 'Deviances'
    $dt.Columns.Add('ID', [int]) | Out-Null
    $dt.Columns.Add('EventDate', [datetime]) | Out-Null
    $dt.Columns.Add('reason', [string]) | Out-Null
    $dt.Columns.Add('adObjectId', [int]) | Out-Null
    $dt.Columns.Add('ADObjectType', [string]) | Out-Null # computer, user
    $dt.Columns.Add('AccountCn', [string]) | Out-Null # r-key-cred-owner
    $dt.Columns.Add('SID', [string]) | Out-Null # r-key-cred-owner
    $dt.Columns.Add('SidCn', [string]) | Out-Null # r-key-cred-owner
    $dt.Columns.Add('ObjectName', [string]) | Out-Null # r-key-cred-acl
    $dt.Columns.Add('DangerousAceList', [string]) | Out-Null # r-key-cred-acl
    $dt.Columns.Add('AceAccount',[string]) | Out-Null # item3 in the json string has the account name
    $dt.Columns.Add('KeyId', [string]) | Out-Null # r-key-cred-roca
    $dt.Columns.Add('DeviceId', [string]) | Out-Null # r-key-cred-roca
    $dt.Columns.Add('ComputerCn', [string]) | Out-Null # r-key-cred-roca

    [int]$id = 0
    [string]$reason = ''
    [int]$idx = -1
    [int]$idx2 = -1
    [int]$idx3 = -1
    [int]$idx4 = -1
    [Int64]$R_KEY_CRED_ROCA = 59000
    [Int64]$R_KEY_CRED_ACL = 59005
    [Int64]$R_KEY_CRED_OWNER = 59006    
    foreach ($deviance in $Deviances) {
        if ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Progress -PercentComplete ($id / $Deviances.Count * 100) -Status "Processing Deviance" -Activity "Deviance ID: $($deviance.id)"
        }
        $id++
        # the reasonId is a 64-bit integer, we may need to upcast 32-bit integers to 64-bit integers
        $reason = ($reasons[$deviance.reasonId]).codename
        $idx = -1
        $idx2 = -1
        $idx3 = -1
        $idx4 = -1
        [System.Data.DataRow]$row = $dt.NewRow()
        $row.ID = $id
        if ($UseLocalDatetime) {
            $row.EventDate = (Get-Date -Date $deviance.eventDate).ToLocalTime()
        } else {
            $row.EventDate = $deviance.eventDate
        }
        $row.reason = $reason
        $row.adObjectId = $deviance.adObjectId
        $row.ADObjectType = [DBNull]::Value

        switch ($deviance.reasonId) {
            { $_ -eq $R_KEY_CRED_ROCA } {
                $idx = [Array]::IndexOf($deviance.attributes.name, 'KeyId')
                $idx2 = [Array]::IndexOf($deviance.attributes.name, 'DeviceId')
                $idx3 = [Array]::IndexOf($deviance.attributes.name, 'ComputerCn')
                $idx4 = [Array]::IndexOf($deviance.attributes.name, 'AccountCn')
                $row.AccountCn = $deviance.attributes[$idx4].value
                $row.SID = [DBNull]::Value
                $row.SidCn = [DBNull]::Value
                $row.ObjectName = [DBNull]::Value
                $row.DangerousAceList = [DBNull]::Value
                $row.KeyId = $deviance.attributes[$idx].value
                $row.DeviceId = $deviance.attributes[$idx2].value
                $row.ComputerCn = $deviance.attributes[$idx3].value
                $row.AceAccount = [DBNull]::Value
            }
            { $_ -eq $R_KEY_CRED_ACL } { 
                $idx = [Array]::IndexOf($deviance.attributes.name, 'ObjectName')
                $idx2 = [Array]::IndexOf($deviance.attributes.name, 'DangerousAceList')
                $row.AccountCn = [DBNull]::Value
                $row.SID = [DBNull]::Value
                $row.SidCn = [DBNull]::Value
                $row.KeyId = [DBNull]::Value
                $row.DeviceId = [DBNull]::Value
                $row.ComputerCn = [DBNull]::Value
                $row.ObjectName = $deviance.attributes[$idx].value
                # this json string is not formatted. so, i formatted it.
                $j = $deviance.attributes[$idx2].value | ConvertFrom-Json
                if ($j.item3) {
                    if ($j.count -gt 1) {
                        $row.AceAccount = $j.item3 -join ', '
                    } else {
                        $row.AceAccount = $j.item3
                    }
                }
                $row.DangerousAceList = $j | ConvertTo-Json -Depth 99 | Out-String
            }
            { $_ -eq $R_KEY_CRED_OWNER } {
                $idx = [Array]::IndexOf($deviance.attributes.name, 'AccountCn')
                $idx2 = [Array]::IndexOf($deviance.attributes.name, 'SID')
                $idx3 = [Array]::IndexOf($deviance.attributes.name, 'SidCn')
                $row.ObjectName = [DBNull]::Value
                $row.DangerousAceList = [DBNull]::Value
                $row.KeyId = [DBNull]::Value
                $row.DeviceId = [DBNull]::Value
                $row.ComputerCn = [DBNull]::Value
                $row.AccountCn = $deviance.attributes[$idx].value
                $row.SID = $deviance.attributes[$idx2].value
                $row.SidCn = $deviance.attributes[$idx3].value
            }
            Default {$reason = "Unknown $($reasonId)"}
        }
        $dt.Rows.Add($row) | Out-Null
    }

    if ($WantAdObjectType) {
        [hashtable]$adObjects = @{}
        if ($ADObjectCsvPath) {
            if ((-not (Test-Path -Path $ADObjectCsvPath)) -and (Test-Path -Path $ADObjectCsvPath -IsValid)) {
                Write-Verbose "ADObject CSV file not found: $($ADObjectCsvPath). I will attempt to create it."
            } elseif (-not (Test-Path -Path $ADObjectCsvPath -IsValid)) {
                Write-Warning "ADObject CSV file is not valid: $($ADObjectCsvPath). I cannot use it."
                $ADObjectCsvPath = $null
            } else {
                Write-Verbose "Reading ADObject CSV file: $($ADObjectCsvPath). I will overwrite it."
                # read the ADObjectId and ADObjectType from the CSV file
                foreach ($csv in (Import-Csv -Path $ADObjectCsvPath -Delimiter ',')) {
                    $adObjects.Add($csv.key, $csv.value)
                }
            }
        }
        # get the ADObjectType for each adObjectId
        [int]$cnt = 0
        foreach ($row in $dt.Rows) {
            $cnt++
            if ($VerbosePreference -ne 'SilentlyContinue') {
                Write-Progress -PercentComplete ($cnt / $dt.Rows.Count * 100) -Status "Setting ADObjects" -Activity "ADObjectId: $($row.adObjectId)"
            }
            if (-not $adObjects.ContainsKey($row.adObjectId)) {
                [PSCustomObject]$adObject = Get-PSTIEADObjectById -Tapi $tapi -AdObjectId $row.adObjectId
                # get the objectcategory for the adObjectId
                $adObjects[$row.adObjectId] = $adObject.objectAttributes[[Array]::IndexOf($adObject.objectAttributes.name, 'objectcategory')].value
            }
            if ($adObjects[$row.adObjectId]) {
                try {
                    $row.BeginEdit()
                    $row.ADObjectType = $adObjects[$row.adObjectId]
                    $row.EndEdit()
                } catch {
                    Write-Host "Error setting ADObjectType for $($row.adObjectId): $($_.Exception.Message)"
                }
            } else {
                $row.ADObjectType = [DBNull]::Value
            }
        }
        if ($ADObjectCsvPath -and $adObjects.Count -gt 0) {
            Write-Verbose "Writing ADObject CSV file: $($ADObjectCsvPath)"
            $adObjects.GetEnumerator() | Export-Csv -Path $ADObjectCsvPath -NoTypeInformation -Delimiter ',' -Force
        }
    }


    # emit the DataTable as a collection of PSCustomObjects
    foreach ($row in $dt.Rows) {
        [PSCustomObject]@{
            ID = $row.ID
            EventDate = $row.EventDate
            reason = $row.reason
            adObjectId = $row.adObjectId
            ADObjectType = $row.ADObjectType
            AccountCn = $row.AccountCn
            SID = $row.SID
            SidCn = $row.SidCn
            ObjectName = $row.ObjectName
            DangerousAceList = $row.DangerousAceList
            AceAccount = $row.AceAccount
            KeyId = $row.KeyId
            DeviceId = $row.DeviceId
            ComputerCn = $row.ComputerCn
        }
    }
}

$tapi = New-PSTenableIE -ApiKey $ApiKey -TenantFqdn $TenantFqdn -ContentType $ContentType -ProfileId $ProfileId -InfrastructureId $InfrastructureId -DirectoryId $DirectoryId

# In my environment, this checker ID is 59. Yours may differ.
[int]$CHECKER_ID = 59
[System.Collections.ArrayList]$deviances = Get-PSTIESpecificCheckerDeviances -Tapi $tapi -CheckerId $CHECKER_ID
Get-ShadowCredentials -Deviances $deviances -UseLocalDatetime $UseLocalDatetime -WantAdObjectType $WantAdObjectType -ADObjectCsvPath $ADObjectCsvPath