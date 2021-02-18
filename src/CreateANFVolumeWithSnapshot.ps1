# Copyright(c) Microsoft and contributors. All rights reserved
#
# This source code is licensed under the MIT license found in the LICENSE file in the root directory of the source tree

<#
.SYNOPSIS
    This script creates Azure Netapp files resources with Snapshot Policy
.DESCRIPTION
    Authenticates with Azure and select the targeted subscription first, then created ANF account, Snapshot Policy, capacity pool and NFSv3 Volume
.PARAMETER ResourceGroupName
    Name of the Azure Resource Group where the ANF will be created
.PARAMETER Location
    Azure Location (e.g 'WestUS', 'EastUS')
.PARAMETER NetAppAccountName
    Name of the Azure NetApp Files Account
.PARAMETER NetAppPoolName
    Name of the Azure NetApp Files Capacity Pool
.PARAMETER ServiceLevel
    Service Level - Ultra, Premium or Standard
.PARAMETER NetAppPoolSize
    Size of the Azure NetApp Files Capacity Pool in Bytes. Range between 4398046511104 and 549755813888000
.PARAMETER NetAppVolumeName
    Name of the Azure NetApp Files Volume
.PARAMETER NetAppVolumeSize
    Size of the Azure NetApp Files volume in Bytes. Range between 107374182400 and 109951162777600
.PARAMETER SubnetId
    The Delegated subnet Id within the VNET
.PARAMETER EPUnixReadOnly 
    Export Policy UnixReadOnly property 
.PARAMETER EPUnixReadWrite
    Export Policy UnixReadWrite property
.PARAMETER AllowedClientsIp 
    Client IP to access Azure NetApp files volume
.PARAMETER CleanupResources
    If the script should clean up the resources, $false by default
.EXAMPLE
    PS C:\\> CreateANFVolumeWithSnapshot.ps1
#>
param
(
    # Name of the Azure Resource Group
    [string]$ResourceGroupName = 'My-rg',

    #Azure location 
    [string]$Location ='CentralUS',

    #Azure NetApp Files account name
    [string]$NetAppAccountName = 'anfaccount',

    #Azure NetApp Files Snapshot policy name
    [string]$SnapshotPolicyName = 'anfsnappolicy',

    #Azure NetApp Files capacity pool name
    [string]$NetAppPoolName = 'pool1' ,

    # Service Level can be {Ultra, Premium or Standard}
    [ValidateSet("Ultra","Premium","Standard")]
    [string]$ServiceLevel = 'Standard',

    #Azure NetApp Files capacity pool size
    [ValidateRange(4398046511104,549755813888000)]
    [long]$NetAppPoolSize = 4398046511104,

    #Azure NetApp Files volume name
    [string]$NetAppVolumeName = 'vol1',
    
    #Azure NetApp Files volume size
    [ValidateRange(107374182400,109951162777600)]
    [long]$NetAppVolumeSize = 107374182400,

    #Subnet Id 
    [string]$SubnetId = 'Subnet ID',

    #UnixReadOnly property
    [bool]$EPUnixReadOnly = $false,

    #UnixReadWrite property
    [bool]$EPUnixReadWrite = $true,

    #UnixReadOnly property
    [string]$AllowedClientsIp = "0.0.0.0/0",

    #Clean Up resources
    [bool]$CleanupResources = $false
)

$ErrorActionPreference="Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#Functions
Function WaitForANFResource
{
    Param 
    (
        [ValidateSet("NetAppAccount","CapacityPool","Volume","Snapshot")]
        [string]$ResourceType,
        [string]$ResourceId, 
        [int]$IntervalInSec = 10,
        [int]$retries = 60
    )

    for($i = 0; $i -le $retries; $i++)
    {
        Start-Sleep -s $IntervalInSec
        try
        {
            if($ResourceType -eq "NetAppAccount")
            {
                $Account = Get-AzNetAppFilesAccount -ResourceId $ResourceId
                if($Account.ProvisioningState -eq "Succeeded")
                {
                    break
                }

            }
            elseif($ResourceType -eq "CapacityPool")
            {
                $Pool = Get-AzNetAppFilesPool -ResourceId $ResourceId
                if($Pool.ProvisioningState -eq "Succeeded")
                {
                    break
                }
            }
            elseif($ResourceType -eq "Volume")
            {
                $Volume = Get-AzNetAppFilesVolume -ResourceId $ResourceId
                if($Volume.ProvisioningState -eq "Succeeded")
                {
                    break
                }
            }
            elseif($ResourceType -eq "Snapshot")
            {            
                $Snapshot = Get-AzNetAppFilesSnapshotPolicy -ResourceId $ResourceId
                if($Snapshot.ProvisioningState -eq "Succeeded")
                {
                    break
                }
            }
        }
        catch
        {
            continue
        }
    }    
}

Function WaitForNoANFResource
{
Param 
    (
        [ValidateSet("NetAppAccount","CapacityPool","Volume","Snapshot")]
        [string]$ResourceType,
        [string]$ResourceId, 
        [int]$IntervalInSec = 10,
        [int]$retries = 60
    )

    for($i = 0; $i -le $retries; $i++)
    {
        Start-Sleep -s $IntervalInSec
        try
        {
            if($ResourceType -eq "Snapshot")
            {
                Get-AzNetAppFilesSnapshotPolicy -ResourceId $ResourceId                
            }
            elseif($ResourceType -eq "Volume")
            {
               Get-AzNetAppFilesVolume -ResourceId $ResourceId                               
            }
            elseif($ResourceType -eq "CapacityPool")
            {
                Get-AzNetAppFilesPool -ResourceId $ResourceId                
            }
            elseif($ResourceType -eq "NetAppAccount")
            {   
                Get-AzNetAppFilesAccount -ResourceId $ResourceId                              
            }
        }
        catch
        {
            break
        }
    }
}

# Authorizing and connecting to Azure
Write-Verbose -Message "Authorizing with Azure Account..." -Verbose
Add-AzAccount

# Create Azure NetApp Files Account
Write-Verbose -Message "Creating Azure NetApp Files Account" -Verbose
$NewAccount = New-AzNetAppFilesAccount -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Name $NetAppAccountName `
    -ErrorAction Stop
Write-Verbose -Message "Azure NetApp Account has been created successfully: $($NewAccount.Id)" -Verbose

# Create Azure NetApp Files Snapshot Policy
Write-Verbose -Message "Creating snapshot policy..." -Verbose
$HourlySchedule = @{        
    Minute = 50
    SnapshotsToKeep = 5
}
$DailySchedule = @{
    Hour = 15
    Minute = 30
    SnapshotsToKeep = 5
}
$WeeklySchedule = @{
   Minute = 30    
   Hour = 12	        
   Day = "Monday"
   SnapshotsToKeep = 5   
}
$MonthlySchedule = @{
   Minute = 50    
   Hour = 14        
   DaysOfMonth = "2,11,21"
   SnapshotsToKeep = 5
}

$NewSnapshotPolicy = New-AzNetAppFilesSnapshotPolicy -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AccountName $NetAppAccountName `
    -Name $SnapshotPolicyName `
    -HourlySchedule $HourlySchedule `
    -DailySchedule $DailySchedule `
    -WeeklySchedule $WeeklySchedule `
    -MonthlySchedule $MonthlySchedule

Write-Verbose -Message "Snapshot policy has been created successfully: $($NewSnapshotPolicy.Id)" -Verbose


# Create Azure NetApp Files Capacity Pool
Write-Verbose -Message "Creating Azure NetApp Files Capacity Pool" -Verbose
$NewPool = New-AzNetAppFilesPool -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AccountName $NetAppAccountName `
    -Name $NetAppPoolName `
    -PoolSize $NetAppPoolSize `
    -ServiceLevel $ServiceLevel `
    -ErrorAction Stop
Write-Verbose -Message "Azure NetApp Files Capacity Pool has been created successfully: $($NewPool.Id)" -Verbose


#Create Azure NetApp Files NFS Volume
Write-Verbose -Message "Creating Azure NetApp Files Volume" -Verbose

$ExportPolicyRule = New-Object -TypeName Microsoft.Azure.Commands.NetAppFiles.Models.PSNetAppFilesExportPolicyRule
$ExportPolicyRule.RuleIndex =1
$ExportPolicyRule.UnixReadOnly =$EPUnixReadOnly
$ExportPolicyRule.UnixReadWrite =$EPUnixReadWrite
$ExportPolicyRule.Cifs = $false
$ExportPolicyRule.Nfsv3 = $true
$ExportPolicyRule.Nfsv41 = $false
$ExportPolicyRule.AllowedClients =$AllowedClientsIp

$ExportPolicy = New-Object -TypeName Microsoft.Azure.Commands.NetAppFiles.Models.PSNetAppFilesVolumeExportPolicy -Property @{Rules = $ExportPolicyRule}

$NewSnapshot = New-Object -TypeName Microsoft.Azure.Commands.NetAppFiles.Models.PSNetAppFilesVolumeSnapshot -Property @{SnapshotPolicyId = $($NewSnapshotPolicy.Id)}

$NewVolume = New-AzNetAppFilesVolume -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AccountName $NetAppAccountName `
    -PoolName $NetAppPoolName `
    -Name $NetAppVolumeName `
    -UsageThreshold $NetAppVolumeSize `
    -ProtocolType 'NFSv3' `
    -ServiceLevel $ServiceLevel `
    -SubnetId $SubnetId `
    -CreationToken $NetAppVolumeName `
    -ExportPolicy $ExportPolicy `
    -Snapshot $NewSnapshot

Write-Verbose -Message "Azure NetApp Files Volume has been created successfully: $($NewVolume.Id)" -Verbose

Write-Verbose -Message "Updating existing Snapshot Policy..." -Verbose
$HourlySchedule = @{
    minute = 1
    SnapshotsToKeep = 10
}
Update-AzNetAppFilesSnapshotPolicy -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AccountName $NetAppAccountName `
    -Name $SnapshotPolicyName `
    -HourlySchedule $HourlySchedule `
    -Enabled $true

Write-Verbose -Message "Snapshot Policy has been updated." -Verbose
Write-Verbose -Message "Azure NetApp Files has been created successfully." -Verbose

if($CleanupResources)
{    
    Write-Verbose -Message "Cleaning up Azure NetApp Files resources..." -Verbose

    #Deleting NetApp Files Volume
    Write-Verbose -Message "Deleting Azure NetApp Files Volume: $NetAppVolumeName" -Verbose
    Remove-AzNetAppFilesVolume -ResourceGroupName $ResourceGroupName `
            -AccountName $NetAppAccountName `
            -PoolName $NetAppPoolName `
            -Name $NetAppVolumeName

    WaitForNoANFResource -ResourceType Volume -ResourceId $($NewVolume.Id)
    #Deleting NetApp Files Pool
    Write-Verbose -Message "Deleting Azure NetApp Files pool: $NetAppPoolName" -Verbose
    Remove-AzNetAppFilesPool -ResourceGroupName $ResourceGroupName `
        -AccountName $NetAppAccountName `
        -PoolName $NetAppPoolName

    WaitForNoANFResource -ResourceType CapacityPool -ResourceId $($NewPool.Id)

    #Deleting NetApp Files Pool
    Write-Verbose -Message "Deleting Snapshot Policy: $SnapshotPolicyName" -Verbose
    Remove-AzNetAppFilesSnapshotPolicy -ResourceGroupName $ResourceGroupName `
        -AccountName $NetAppAccountName `
        -Name $SnapshotPolicyName

    #Deleting NetApp Files account
    Write-Verbose -Message "Deleting Azure NetApp Files Volume: $NetAppVolumeName" -Verbose
    Remove-AzNetAppFilesAccount -ResourceGroupName $ResourceGroupName -Name $NetAppAccountName

    Write-Verbose -Message "All Azure NetApp Files resources have been deleted successfully." -Verbose    
}