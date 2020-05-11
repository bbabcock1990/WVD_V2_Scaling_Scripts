<#
.SYNOPSIS
    Automated process of starting 'X' number of WVD session hosts before peak-hours.
    (Using the Spring 2020 Update)
.DESCRIPTION
    This script is intended to automatically start 'X" session hosts in a Windows Virtual Desktop
    environment before peak-hours. The script pulls all session hosts underneath a WVD pool
    and runs the Start-AzVM command to start the desired session hosts. This runbook is triggered via
    a Azure Automation Schedule running on a trigger.
    
.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Test it before you trust it
    Author      : Brandon Babcock
    Website     : https://www.linkedin.com/in/brandonbabcock1990/
    Version     : 1.1.0.0 Initial Build
#>

######## Variables ##########

# AD and Sub IDs Pulled From Runbook Variables
$aadTenantId = Get-AutomationVariable -Name 'aadTenantId'
$azureSubId = Get-AutomationVariable -Name 'azureSubId'

# Session Host Resource Group
$sessionHostRg = 'ahead-brandon-babcock-testwvd-rg'

# Host Pool Name
$hostPoolName = 'brandonhp1'

########## Script Execution ##########

# Log into Azure
try {
    $creds = Get-AutomationPSCredential -Name 'WVD-Scaling-SVC'
    $context=Connect-AzAccount -ErrorAction Stop -ServicePrincipal -SubscriptionId $azureSubId -TenantId $aadTenantId -Credential $creds
    Write-Output "Trying To Log Into Azure..."
    Write-Output $context
    Write-Output "Login Successfull!"
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Output "Error Logging Into Azure: $ErrorMessage"
    Break
}

# Get Host Pool 
try {
    Write-Output "Grabbing Hostpool: $hostPoolName"
    $hostPool = Get-AzWVDHostPool -Name $hostPoolName -ResourceGroupName $sessionHostRg -ErrorVariable Stop
    Write-Output $hostPool
    Write-Output "Grabbed Hostpool Successfully"
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Output "Error Getting Hostpool Details: $ErrorMessage"
    Break
}
# Get List Of All Session Host Under Host Pool
Write-Output "Grabbing All Session Host Underneath Hostpool: $hostPoolName"
$sessionHostList = Get-AzWvdSessionHost -HostPoolName $hostPoolName -ResourceGroupName $sessionHostRg -ErrorVariable Stop
Write-Output $sessionHostList
Write-Output "Grabbed All Session Host Successfully"

# Start 'X' Session Host. Session Host >= 'X'
try{
    For ($i=0; $i -lt ($sessionHostList.length); $i++) {
        $vmName=$sessionHostList[$i].Name.Split('.')[0]
        $vmName=$vmName.Split('/')[1]
        Write-Output "Trying To StartUp: $vmName"
        Start-AzVM -ResourceGroupName $sessionHostRg -Name $vmName -AsJob -ErrorAction Stop
        Write-Output "Startup Sucessfull"
    }
}
catch{
    $ErrorMessage = $_.Exception.message
    Write-Output "Error starting VMs: $ErrorMessage"
    Break
}
