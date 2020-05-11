<#
.SYNOPSIS
    Automated process of starting scaling 'X' number of WVD session hosts during peak-hours.
    (Using the Spring 2020 Update)
.DESCRIPTION
    This script is intended to automatically start 'X' session hosts in a Windows Virtual Desktop
    environment during peak-hours. The script pulls all session hosts underneath a WVD pool
    and runs the Start-AzVM/Stop-AzVM command to start/stop the desired session hosts. This runbook is 
    triggered via a Azure Function running on a trigger.

    Please make sure your Azure Function is setup in the correct timezone by using the Applicaton Settings:

    WEBSITE_TIME_ZONE : YOUR TIME ZONE (Eastern Standard Time)

.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Test it before you trust it
    Author      : Brandon Babcock
    Website     : https://www.linkedin.com/in/brandonbabcock1990/
    Version     : 1.1.0.0 Initial Build
#>


######## Variables ##########

# Update the following settings for your environment
# Server start threshold.  Number of available sessions to trigger a server start or shutdown
# (Active Sessions + Threshold) / Max Connections per session host
$serverStartThreshold = 1

# Tenant ID of Azure AD
$aadTenantId = Get-AutomationVariable -Name 'aadTenantId'

# Azure Subscription ID
$azureSubId = Get-AutomationVariable -Name 'azureSubId'

# Session Host Resource Group
$sessionHostRg = 'ahead-brandon-babcock-testwvd-rg'

# Host Pool Name
$hostPoolName = 'brandonhp1'

############## Functions ####################

Function Start-SessionHost {
    param (
        $SessionHosts
    )
    # Number Of Session Hosts That Are Turned Off
    $offSessionHosts = $sessionHosts | Where-Object { $_.Status -eq "Unavailable" }
    Write-Output "Current Number Of Turned Off Session Host: $offSessionHostsCount"
    Write-Output "Current List Of Turned Off Session Hosts:"
    Write-Output $offSessionHosts | Out-String

    if ($offSessionHosts.Count -eq 0 ) {
        Write-Output "Start Threshold Met, But There Are No Hosts Available To Start!"
    }
    else {
        Write-Output "Conditions Met To Start A Session Host..."
        $startServerName = ($offSessionHosts | Select-Object -first 1).Name
        Write-Output "Server To Start $startServerName"
        try {
            # Start the VM
            $vmName = $startServerName.Split('.')[0]
            $vmName = $vmName.Split('/')[1]
            Write-Output "Trying To Start Up: $vmName"
            Start-AzVM -ResourceGroupName $sessionHostRg -Name $vmName -ErrorAction Stop -AsJob
            Write-Output "Startup Sucessfull!"
        }
        catch {
            $ErrorMessage = $_.Exception.message
            Write-Output "Error Starting The Session Host: $ErrorMessage"
            Break
        }
    }
}

Function Stop-SessionHost {
    param (
        $SessionHosts
    )

    # Number Of Session Hosts With No Users Logged In
    $emptyHosts = $sessionHosts | Where-Object { $_.Session -eq 0 -and $_.Status -eq 'Available' } 

    Write-Output "Evaluating Servers To Shut Down..."
    if ($emptyHosts.count -eq 1) {
        Write-error "No Session Hosts Available To Shut Down!"
    }
    elseif ($emptyHosts.count -gt 1) {
        Write-Output "There Are Session Hosts With No Users Logged On."
        Write-Output "Conditions Met To Stop A Session Host..."
        $shutServerName = ($emptyHosts | Select-Object -last 1).Name 
        Write-Output "Shutting Down Server: $shutServerName"
        try {
            # Stop the VM
            $vmName = $shutServerName.Split('.')[0]
            $vmName = $vmName.Split('/')[1]
            Write-Output "Trying To Shutdown: $vmName"
            Stop-AzVM -ErrorAction Stop -ResourceGroupName $sessionHostRg -Name $vmName -Force -AsJob
            Write-Output "Shutdown Sucessfull!"
        }
        catch {
            $ErrorMessage = $_.Exception.message
            Write-Output "Error Stopping The VM:  $ErrorMessage"
            Break
        }
    }   
}

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

# Verify load balancing is set to Depth-first
if ($hostPool.LoadBalancerType -ne "DepthFirst") {
    Write-Error "Host Pool Not Set To Depth-First Load Balancing.  This Script Requires Depth-First Load Balancing To Execute!"
    exit
}


# Get the Max Session Limit on the host pool
# This is the total number of sessions per session host
$maxSession = $hostPool.MaxSessionLimit
Write-Output "MaxSession Per Session Host:  $maxSession"

# Find the total number of session hosts
# Exclude servers that do not allow new connections
try {
    Write-Output "Grabbing All Session Host Where New Logins Are Allowed:"
    $sessionHosts = Get-AzWvdSessionHost -HostPoolName $hostPoolName -ResourceGroupName $sessionHostRg -ErrorVariable Stop | Where-Object { $_.AllowNewSession -eq $true }
    Write-Output $sessionHosts.Name
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Output "Error Getting Session Hosts Details: $ErrorMessage"
    Break
}

# Get current active user sessions
$currentSessions = 0
foreach ($sessionHost in $sessionHosts) {
    $count = $sessionHost.sessions
    $currentSessions += $count
}
Write-Output "Current Number Of Live User Sessions:  $currentSessions"

# Number of running and available session hosts
# Host shut down are excluded
$runningSessionHosts = $sessionHosts | Where-Object { $_.Status -eq "Available" }
$runningSessionHostsCount = $runningSessionHosts.count
Write-Output "Running Session Host That Are Available: $runningSessionHostsCount"
Write-Output "Running Session Host List:" 
Write-Output $runningSessionHosts | Out-String

# Target number of servers required running based on active sessions, Threshold and maximum sessions per host
$sessionHostTarget = [math]::Ceiling((($currentSessions + $serverStartThreshold) / $maxSession))

if ($runningSessionHostsCount -lt $sessionHostTarget) {
    Write-Output "Running Session Host Count $runningSessionHosts Is Less Than Session Host Target Count $sessionHostTarget, Run START Function." 
    Start-SessionHost -Sessionhosts $sessionHosts
}
elseif ($runningSessionHostsCount -gt $sessionHostTarget) {
    Write-Output "Running Session Host Count $runningSessionHostsCount Is Greater Than Session Host Target Count $sessionHostTarget, run STOP Function." 
    Stop-SessionHost -SessionHosts $sessionHosts
}
else {
    Write-Output "Running Session Host Count $runningSessionHostsCount Matches Session Host Target Count $sessionHostTarget, Do NOTHING." 
}