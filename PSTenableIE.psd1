@{
    ModuleVersion = '1.8.3'
    GUID = 'd5d6ec4d-2a4b-42cd-8248-7bf632f929fb'
    Author = 'Ray Storer'
    Description = 'A PowerShell module using a class and exported functions to work with the Tenable IE REST API'
    RootModule = 'PSTenableIE.psm1'

    FunctionsToExport = @('Get-PSTIEADObjectById','Get-PSTIECheckerReasons','Get-PSTIEPagedData','Get-PSTIESpecificCheckerDeviances','Get-PSTIEAllDirectoryDeviances','New-PSTenableIE','Update-PSTIEADObjectByCheckerId')

    Copyright = '(c) 2025 Ray Storer. All rights reserved.'
    PowerShellVersion = '5.1'
}
