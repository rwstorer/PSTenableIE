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
    [int]$DirectoryId=1
)

Import-Module .\PSTenableIE.psd1

function Get-ShadowCredentials {
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [System.Collections.ArrayList]$Deviances,
    [Parameter(Mandatory=$false)]
    [bool]$UseLocalDatetime=$false
)
    [System.Collections.Hashtable]$reasons = Get-PSTIECheckerReasons -Tapi $tapi -CheckerId $CHECKER_ID

    $dt = New-Object System.Data.DataTable
    $dt.TableName = 'Deviances'
    $dt.Columns.Add('ID', [int]) | Out-Null
    $dt.Columns.Add('EventDate', [datetime]) | Out-Null
    $dt.Columns.Add('reason', [string]) | Out-Null
    $dt.Columns.Add('adObjectId', [int]) | Out-Null
    $dt.Columns.Add('AccountCn', [string]) | Out-Null # r-key-cred-owner
    $dt.Columns.Add('SID', [string]) | Out-Null # r-key-cred-owner
    $dt.Columns.Add('SidCn', [string]) | Out-Null # r-key-cred-owner
    $dt.Columns.Add('ObjectName', [string]) | Out-Null # r-key-cred-acl
    $dt.Columns.Add('DangerousAceList', [string]) | Out-Null # r-key-cred-acl
    $dt.Columns.Add('KeyId', [string]) | Out-Null # r-key-cred-roca
    $dt.Columns.Add('DeviceId', [string]) | Out-Null # r-key-cred-roca
    $dt.Columns.Add('ComputerCn', [string]) | Out-Null # r-key-cred-roca

    [int]$id = 0
    [Int64]$reasonId = 0
    [string]$reason = ''
    [int]$idx = -1
    [int]$idx2 = -1
    [int]$idx3 = -1
    [Int64]$R_KEY_CRED_ROCA = 59000
    [Int64]$R_KEY_CRED_ACL = 59005
    [Int64]$R_KEY_CRED_OWNER = 59006    
    foreach ($deviance in $Deviances) {
        $id++
        # the reasonId is a 64-bit integer, we may need to upcast 32-bit integers to 64-bit integers
        $reasonId = $deviance.reasonId
        $reason = ($reasons[$reasonId]).codename
        $idx = -1
        $idx2 = -1
        $idx3 = -1
        [System.Data.DataRow]$row = $dt.NewRow()
        $row.ID = $id
        if ($UseLocalDatetime) {
            $row.EventDate = (Get-Date -Date $deviance.eventDate).ToLocalTime()
        } else {
            $row.EventDate = $deviance.eventDate
        }
        $row.reason = $reason
        $row.adObjectId = $deviance.adObjectId

        switch ($reasonId) {
            { $_ -eq $R_KEY_CRED_ROCA } {
                $idx = [Array]::IndexOf($deviance.attributes.name, 'KeyId')
                $idx2 = [Array]::IndexOf($deviance.attributes.name, 'DeviceId')
                $idx3 = [Array]::IndexOf($deviance.attributes.name, 'ComputerCn')
                $row.AccountCn = [DBNull]::Value
                $row.SID = [DBNull]::Value
                $row.SidCn = [DBNull]::Value
                $row.ObjectName = [DBNull]::Value
                $row.DangerousAceList = [DBNull]::Value
                $row.KeyId = $deviance.attributes[$idx].value
                $row.DeviceId = $deviance.attributes[$idx2].value
                $row.ComputerCn = $deviance.attributes[$idx3].value
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
                $row.DangerousAceList = $deviance.attributes[$idx2].value
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

    # emit the DataTable as a collection of PSCustomObjects
    foreach ($row in $dt.Rows) {
        [PSCustomObject]@{
            ID = $row.ID
            EventDate = $row.EventDate
            reason = $row.reason
            adObjectId = $row.adObjectId
            AccountCn = $row.AccountCn
            SID = $row.SID
            SidCn = $row.SidCn
            ObjectName = $row.ObjectName
            DangerousAceList = $row.DangerousAceList
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
Get-ShadowCredentials -Deviances $deviances -UseLocalDatetime $UseLocalDatetime