<# ----------------------------------------------------------------------------------------------------------------
Author:     Jeremy Hagan
Date:       2024-10-21
Version:    1.0.0
Purpose:    Script to import powershell runbooks into Azure Automation Account.

            This script is designed to be run from a Github pipeline azure/powershell@v2 task. It will enumerate
            PowerShell scripts under the supplied path and attempt to import each script into the supplied
            automation account, assuming that the runbook has the same name as the script.

Chlog: 

-------------------------------------------------------------------------------------------------------------------
#>
[CmdletBinding()]
param (
    # The resource group name
    [Parameter(Mandatory)]
    [string]
    $ResourceGroupName,
    # The automation account name
    [Parameter(Mandatory)]
    [string]
    $AutomationAccountName,
    # The path to the scripts
    [Parameter(Mandatory)]
    [string]
    $Path
)
#requires -modules Az.Accounts,Az.Automation
dir $path -Recurse | Select Fullname
$runbooks = Get-ChildItem -Path $Path -Filter *.ps1 -Recurse
If ($null -eq $runbooks) {
    Write-Warning "No scripts found under $Path"
    Exit
}
$runbooks | ForEach-Object {
    $runbookName = $_.BaseName
    $runbook = Get-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName -Name $runbookName -ErrorAction SilentlyContinue
    if ($null -ne $runbook) {
        Write-Output "Importing script from $($_.FullName) into runbook $runbookName"
        try {
            Import-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName -Name $runbookName -Type PowerShell `
                -Path $_.FullName -Published -Force
        }
        catch {
            Throw $_
        }
    } else {
        Write-Warning "Runbook $runbookName not found in automation account $AutomationAccountName"
    }
}