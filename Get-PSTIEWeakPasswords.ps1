# This script uses the System.Data assembly to create a DataTable object.
# PowerShell 7+ does not require explicit loading of this assembly, but PowerShell 5.1 and earlier versions do require it.
# If you are using PowerShell 5.1 or earlier, uncomment the following line to load the assembly:
# Add-Type -AssemblyName 'System.Data'

Import-Module PSTenableIE

function Get-PasswdIssues() {
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [System.Collections.ArrayList]$Deviances,
    [Parameter(Mandatory=$false)]
    [bool]$UseLocalDatetime=$false
)
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

        if ($deviance.description.template.Contains('blank')) {
            $Issue = 'blank'
        } elseif ($deviance.description.template.Contains('breached')) {
            $Issue = 'breached'
        } elseif ($deviance.description.template.Contains('privileged')) {
            $Issue = 'shared_privileged'
        } elseif ($deviance.description.template.Contains('shared')) {
            $Issue = 'shared'
        }
        foreach ($name in $Names) {
            if ($Issue -eq 'breached') {
                [System.Data.DataRow[]]$sr = $dt.Select("Name = '$($name)' AND Issue = 'blank'")
                if ($sr.Count -eq 0) { # I do not want the breached record if I already have a blank record
                    [System.Data.DataRow]$row = $dt.NewRow()
                    $row.ID = $id++
                    $row.Name = $name
                    $row.Issue = 'breached'
                    if ($UseLocalDatetime) {
                        $row.EventDate = $deviance.eventDate.Date.ToLocalTime()
                    } else {
                        $row.EventDate = $deviance.eventDate.Date
                    }
                    $row.PasswordHashPrefix = $PasswordHashPrefix
                    $dt.Rows.Add($row) | Out-Null
                } 
            } elseif ($Issue -eq 'blank') {
                [System.Data.DataRow[]]$sr = $dt.Select("Name = '$($name)' AND Issue = 'breached'")
                if ($sr.Count -eq 0) {
                    [System.Data.DataRow]$row = $dt.NewRow()
                    $row.ID = $id++
                    $row.Name = $name
                    $row.Issue = 'blank'
                    if ($UseLocalDatetime) {
                        $row.EventDate = $deviance.eventDate.Date.ToLocalTime()
                    } else {
                        $row.EventDate = $deviance.eventDate.Date
                    }
                    $row.PasswordHashPrefix = $PasswordHashPrefix
                    $dt.Rows.Add($row) | Out-Null
                } else { # if the password is blank, I don't need the breached record
                [System.Data.DataRow[]]$upd = $dt.Select("ID = $($sr[0].ID)")[0]
                    $upd[0].Issue = 'blank'
                    $dt.AcceptChanges()
                } 
            } else {
                [System.Data.DataRow]$row = $dt.NewRow()
                $row.ID = $id++
                $row.Name = $name
                $row.Issue = $Issue
                if ($UseLocalDatetime) {
                    $row.EventDate = $deviance.eventDate.Date.ToLocalTime()
                } else {
                    $row.EventDate = $deviance.eventDate.Date
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

$tapi = New-PSTenableIE -ApiKey "your_api_key" -TenantFqdn "your_tenant_fqdn" -ContentType "application/json" -ProfileId 1 -InfrastructureId 1 -DirectoryId 1

# In my environment, this checker ID is 50. Yours may differ.
Get-PasswdIssues -Deviances (Get-SpecificCheckerDeviances $tapi -CheckerId 50 -UseLocalDatetime=$false)
