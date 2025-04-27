# This script uses the System.Data assembly to create a DataTable object.
# PowerShell 7+ does not require explicit loading of this assembly, but PowerShell 5.1 and earlier versions do require it.
# If you are using PowerShell 5.1 or earlier, uncomment the following line to load the assembly:
# Add-Type -AssemblyName 'System.Data'

Import-Module .\PSTenableIE.psd1

function Get-PasswdIssues() {
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [System.Collections.ArrayList]$Deviances,
    [Parameter(Mandatory=$false)]
    [bool]$UseLocalDatetime=$false
)
    New-Variable -Name 'BLANK_PASSOWRD' -Value 'R-BLANK-NT-USER-HASH' -Option Constant -Scope local
    New-Variable -Name 'BREACHED_PASSWORD' -Value 'R-BREACHED-PASSWORD' -Option Constant -Scope local
    $dt = New-Object System.Data.DataTable
    $dt.TableName = 'Deviances'
    $dt.Columns.Add('ID', [int]) | Out-Null
    $dt.Columns.Add('Name', [string]) | Out-Null
    $dt.Columns.Add('Issue', [string]) | Out-Null
    $dt.Columns.Add('EventDate', [datetime]) | Out-Null
    $dt.Columns.Add('PasswordHashPrefix', [string]) | Out-Null

    $Names = New-Object System.Collections.ArrayList
    [string]$Issue = ''
    [string]$PasswordHashPrefix = ''

    [int]$id = 0
    $reasons = Get-PSTIECheckerReasons -Tapi $tapi -CheckerId $CHECKER_ID
    foreach ($deviance in $Deviances) {
        $Names.Clear()
        $Issue = ''
        $PasswordHashPrefix = ''
        
        [int]$idx = [Array]::IndexOf($deviance.attributes.name, 'AccountList')
        if ($idx -gt -1) {
            [PSCustomObject]$acctList = $deviance.attributes[$idx]
            [int]$idx3 = [Array]::IndexOf($deviance.attributes.name, 'PasswordHashPrefix')
            [PSCustomObject]$prefix = $deviance.attributes[$idx3]
            if ($prefix) {
                $PasswordHashPrefix = $prefix.value
            }
            foreach($acct in ($acctList.value.Split(', '))) {
                $Names.Add($acct) | Out-Null
            }
        } else {
            [int]$idx2 = [Array]::IndexOf($deviance.attributes.name, 'Cn')
            [PSCustomObject]$cnAttr = $deviance.attributes[$idx2]
            $Names.Add($cnAttr.value) | Out-Null
        }

        $Issue = ($reasons[$deviance.reasonId]).codename

        foreach ($name in $Names) {
            if ($Issue -eq $BREACHED_PASSWORD) {
                [System.Data.DataRow[]]$sr = $dt.Select("Name = '$($name)' AND Issue = '$($BLANK_PASSOWRD)'")
                if ($sr.Count -eq 0) { # I do not want the breached record if I already have a blank record
                    [System.Data.DataRow]$row = $dt.NewRow()
                    $row.ID = $id++
                    $row.Name = $name
                    $row.Issue = $Issue
                    # the eventDate is in UTC by default
                    if ($UseLocalDatetime) {
                        $row.EventDate = (Get-Date -Date $deviance.eventDate).ToLocalTime()
                    } else {
                        $row.EventDate = $deviance.eventDate
                    }
                    $row.PasswordHashPrefix = $PasswordHashPrefix
                    $dt.Rows.Add($row) | Out-Null
                } 
            } elseif ($Issue -eq $BLANK_PASSOWRD) {
                [System.Data.DataRow[]]$sr = $dt.Select("Name = '$($name)' AND Issue = '$($BREACHED_PASSWORD)'")
                if ($sr.Count -eq 0) {
                    [System.Data.DataRow]$row = $dt.NewRow()
                    $row.ID = $id++
                    $row.Name = $name
                    $row.Issue = $Issue
                    # the eventDate is in UTC by default
                    if ($UseLocalDatetime) {
                        $row.EventDate = $deviance.eventDate.ToLocalTime()
                    } else {
                        $row.EventDate = $deviance.eventDate
                    }
                    $row.PasswordHashPrefix = $PasswordHashPrefix
                    $dt.Rows.Add($row) | Out-Null
                } else { # if the password is blank, I don't need the breached record
                [System.Data.DataRow[]]$upd = $dt.Select("ID = $($sr[0].ID)")[0]
                    $upd[0].Issue = $BLANK_PASSOWRD
                    $dt.AcceptChanges()
                } 
            } else {
                [System.Data.DataRow]$row = $dt.NewRow()
                $row.ID = $id++
                $row.Name = $name
                $row.Issue = $Issue
                if ($UseLocalDatetime) {
                    $row.EventDate = (Get-Date -Date $deviance.eventDate).ToLocalTime()
                } else {
                    $row.EventDate = $deviance.eventDate
                }
                $row.PasswordHashPrefix = $PasswordHashPrefix
                $dt.Rows.Add($row) | Out-Null
            }
        }
    }

    # emit the DataTable as a collection of PSCustomObjects
    foreach ($row in $dt.Rows) {
        [PSCustomObject]@{
            ID = $row.ID
            Name = $row.Name
            Issue = $row.Issue
            EventDate = $row.EventDate
            PasswordHashPrefix = $row.PasswordHashPrefix
        }
    }
}


$tapi = New-PSTenableIE -ApiKey $env:TENABLE_API_KEY -TenantFqdn $env:TENABLE_API_FQDN -ContentType "application/json" -ProfileId 1 -InfrastructureId 1 -DirectoryId 1

# In my environment, this checker ID is 50. Yours may differ.
New-Variable -Name 'CHECKER_ID' -Value 50 -Option Constant -Scope script
[System.Collections.ArrayList]$deviances = Get-PSTIESpecificCheckerDeviances -Tapi $tapi -CheckerId $CHECKER_ID
Get-PasswdIssues -Deviances $deviances -UseLocalDatetime $false
