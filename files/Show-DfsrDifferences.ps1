<#  
.SYNOPSIS  
    This script outputs the pending outbound changes  from one DFSR server to another for a given replication group
	
	Note: this is an unsupported script and has not undergone testing.  Please use this script at your own risk.  
	Microsoft’s Customer Support Services (CSS/PSS) will not support issues associated with this script
	Copyright (C) 1993 - 2010.  Microsoft Corporation.  All rights reserved.	
.DESCRIPTION  
    This script was born because of the limitation imposed by GetOutboundBacklogFileIdRecords WMI method, allowing only first 100 records be returned when called. 
	The limit is hard coded and this is done for a good reason - trying to fetch all the outbound changes from a DFSR WMI provider is a very expensive operation and WILL put the server under a heavy load if performed on DFSR server hosting a large amount of files.
	Yet, sometimes you do want to be able to identify the files that were changed and have not replicated yet to a given replica.	
.NOTES
    File Name  : Show-DfsrDifferences.ps1  
    Author     : Guy Teverovsky - guyte@microsoft.com  
    Requires   : PowerShell Version 2.0  
.LINK  
    This script is posted to:  
        http://blogs.technet.com/b/isrpfeplat/
	GetOutboundBacklogFileIdRecords on MSDN:
        http://msdn.microsoft.com/en-us/library/bb540039(v=VS.85).aspx
.PARAMETER SourceServer
	The name of the source DFSR server
.PARAMETER TargetServer
	The name of the target DFSR server
.PARAMETER ReplicationGroupName
	The name of the replication group
.Parameter FullList
	If specified, will return a full list of pending outbound changes. Otherwise the script will default to top 100 records.
	This switch is used as safety mechanism to prevent unintentional heavy load on the server.
.EXAMPLE  
    .\Show-DfsrDifferences.ps1 -SourceServer w2k8r2dfsr01 -TargetServer w2k8dfsr01 -ReplicationGroupName TestReplGroup	
	Description
	-----------	
	Return at most first 100 pending outbound changes from server w2k8r2dfsr01 to server w2k8dfsr01 for replication group TestReplGroup
.EXAMPLE 
	.\Show-DfsrDifferences.ps1 -source w2k8r2dfsr01 -target w2k8dfsr01 -rg TestReplGroup
	Description
	-----------	
	Same as above, but uses short aliases for the switches
.EXAMPLE  
    .\Show-DfsrDifferences.ps1 -SourceServer w2k8r2dfsr01 -TargetServer w2k8dfsr01 -ReplicationGroupName TestReplGroup -FullList
	Description
	-----------	
	Return all the pending outbound changes from server w2k8r2dfsr01 to server w2k8dfsr01 for replication group TestReplGroup
#>  

#	THIS CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF
#	ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED
#	TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
#	PARTICULAR PURPOSE.
#
#	Note: this is an unsupported script and has not undergone testing.  Please use this script at your own risk.  
#	Microsoft’s Customer Support Services (CSS/PSS) will not support issues associated with this script
#	Copyright (C) 1993 - 2010.  Microsoft Corporation.  All rights reserved.
	
#region Script parameters

param(

	[parameter(mandatory=$true, HelpMessage="Source DFSR server name")]
	[alias("source")]
	[string]$SourceServer,

	[parameter(mandatory=$true, HelpMessage="Target DFSR server name")]
	[alias("target")]
	[string]$TargetServer,
	
	[parameter(mandatory=$true, HelpMessage="Replication Group name")]
	[alias("rg","group")]	
	[string]$ReplicationGroupName,

	[parameter(mandatory=$false, 
	HelpMessage="Return all pending changes. The default is top 100")]
	[alias("all","full")]	
	[switch]$FullList=$false
	
	)

#endregion

#region Internal Functions

function GetReplFoldersInGroup
{param([string]$dfsrServer, [string]$replGrpName)

	try
	{
		$wmiQuery = "SELECT * FROM DfsrReplicationGroupConfig WHERE ReplicationGroupName='" + $replGrpName + "'"
		Write-Debug "Executing WMI query ""$wmiQuery"" on $dfsrServer"
		$dfsrReplGrp = Get-WmiObject -Namespace "root\microsoftdfs" -Query $wmiQuery -ComputerName $dfsrServer -ErrorAction Stop 
		$replGrpGuid=$dfsrReplGrp.ReplicationGroupGuid
		
		$wmiQuery = "SELECT * FROM DfsrReplicatedFolderConfig WHERE ReplicationGroupGuid='" + $replGrpGuid + "'"
		Write-Debug "Executing WMI query ""$wmiQuery"" on $dfsrServer"
		$dfsrReplFoldersConfig = Get-WmiObject -Namespace "root\microsoftdfs" -Query $wmiQuery -ComputerName $dfsrServer -ErrorAction Stop

		return $dfsrReplFoldersConfig
	}
	catch {
		Write-Host $_.Exception.GetType().Name ": " $_.Exception.Message
		return $null
	}
}

function GetReplFolderVersionVector
{param([string]$dfsrServer, [string]$replFolderGUID)
	
	try
	{
		$wmiQuery = "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicatedFolderGuid='" + $replFolderGUID + "'"
		Write-Debug "Executing WMI query ""$wmiQuery"" on $dfsrServer"
		$dfsrReplFolderInfo = Get-WmiObject -Namespace "root\microsoftdfs" -Query $wmiQuery -ComputerName $dfsrServer -ErrorAction Stop
		Write-Debug "Invoking GetVersionVector() on $dfsrServer"
		$replFolderVV = (Invoke-WmiMethod -InputObject $dfsrReplFolderInfo -Name GetVersionVector -ErrorAction Stop).VersionVector
		return $replFolderVV
	}
	catch {
		Write-Host $_.Exception.GetType().Name ": " $_.Exception.Message
		return $null
	}
}

function BuildVVHashFromVV
{param([string]$VersionVector)

	$vvParts = ($VersionVector | Select-String -Pattern "{.*?}\s.{3}(\s+\(\d*,\s\d*\])+" -AllMatches).Matches
	$vvHash =  @{}

	foreach ($vvPart in $vvParts)
	{
		$guid	= ($vvPart.Value | Select-String -Pattern "{.*?}").Matches[0].Value
		$versionsArray = ($vvPart.Value | Select-String -Pattern "(\s+\(\d*,\s\d*\])+").Matches[0].Value
		$vvPairs = ($vvPart.Value | Select-String -Pattern "\(\d*,\s\d*\]" -AllMatches).Matches
		$vArr = @()
		$vvPairs | % {
			$low 	= [int]($_.value | Select-String -Pattern "\d+" -AllMatches).Matches[0].Value
			$high 	= [int]($_.value | Select-String -Pattern "\d+" -AllMatches).Matches[1].Value
			$vArr += @($low, $high)
		}
		
		$vvHash[$guid] = $vArr
	}
	return $vvHash
}

function GetOutboundBacklogFileCount
{param([string]$dfsrServer, [string]$replFolderGUID, [string]$versionVector)
	$backLogFileCount = 0
	try
	{	
		$wmiQuery = "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicatedFolderGuid='" + $replFolderGUID + "'"
		Write-Debug "Executing WMI query ""$wmiQuery"" on $dfsrServer"
		$dfsrReplFolderInfo = Get-WmiObject -Namespace "root\microsoftdfs" -Query $wmiQuery -ComputerName $dfsrServer -ErrorAction Stop 
		Write-Debug "Invoking GetOutboundBacklogFileCount() on $dfsrServer"
		$backLogFileCount = (Invoke-WmiMethod -InputObject $dfsrReplFolderInfo -Name GetOutboundBacklogFileCount -ArgumentList $versionVector -ErrorAction Stop).BacklogFileCount
	}
	catch {
		Write-Host $_.Exception.GetType().Name ": " $_.Exception.Message
	}
	return $backLogFileCount
}

function FileFromIdrecord
{param($FileIdRecord)

	$file = New-Object PSObject -Property @{
		Name		= $FileIdRecord.FileName
		GVsn		= $FileIdRecord.GVsn
		ParentUid	= $FileIdRecord.ParentUid
		Volume		= $FileIdRecord.Volume
		UpdateTime	= $FileIdRecord.UpdateTime
		Uid			= $FileIdRecord.Uid
		FullPath	= (Invoke-WmiMethod -InputObject $FileIdRecord -Name GetFullFilePath).FullPath
	}
	return $file
}

function GetTop100DFSRDiff
{param([string]$dfsrServer, [string]$replFolderGUID, [string]$versionVector)
	
	try
	{	
		$wmiQuery = "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicatedFolderGuid='" + $replFolderGUID + "'"
		Write-Debug "Executing WMI query ""$wmiQuery"" on $dfsrServer"
		$dfsrReplFolderInfo = Get-WmiObject -Namespace "root\microsoftdfs" -Query $wmiQuery -ComputerName $dfsrServer -ErrorAction Stop 

		$backLogFileCount = GetOutboundBacklogFileCount $dfsrServer $replFolderGUID $versionVector
		if ($backLogFileCount -gt 0) 
		{
			
			
			Write-Debug "Invoking GetOutboundBacklogFileIdRecords() on $dfsrServer"
			
			$backlogFileIdRecords = Invoke-WmiMethod -InputObject $dfsrReplFolderInfo -Name GetOutboundBacklogFileIdRecords -ArgumentList $versionVector -ErrorAction Stop
			$versionVector
			$backlogFileIdRecords.IdRecordIndex
			foreach ($fileidrec in $backlogFileIdRecords.BacklogIdRecords)
			{
				$filter = "uid='" + $fileidrec.Uid + "'"
				Write-Debug "Enumerating DfsrIdRecordInfo instances using filter: $filter on $dfsrServer"
				$idrec = Get-WmiObject -Namespace "root\microsoftdfs" -class DfsrIdRecordInfo -Filter $filter -ComputerName $dfsrServer -ErrorAction Stop
				$file = FileFromIdrecord $idrec
				Write-Output $file			
			}
			Write-Host "Only first 100 pending outbound changes are reported"
			Write-Host "Total pending outbound from API: $backLogFileCount"			
		}
		else
		{
			Write-Host "There are no pending outbound changes for the given replicated folder"
		}
	}
	catch {
		Write-Host $_.Exception.GetType().Name ": " $_.Exception.Message
	}
}

function GetFullDFSRDiff 
{param([string]$dfsrServer, [string]$replFolderGUID, [string]$versionVector)
	
	$vvHash = BuildVVHashFromVV $versionVector
	$backLogFileCount2 = 0
	try
	{
		$backLogFileCount = GetOutboundBacklogFileCount $dfsrServer $replFolderGUID $versionVector
		if ($backLogFileCount -gt 0)
		{		
			$wmiQuery = "SELECT * FROM DfsrIdRecordInfo WHERE ReplicatedFolderGuid='" + $replFolderGUID + "'"
			Write-Debug "Executing WMI query ""$wmiQuery"" on $dfsrServer"
			$dfsrIdRecords = Get-WmiObject -Namespace "root\microsoftdfs" -Query $wmiQuery -ComputerName $dfsrServer -ErrorAction Stop
			foreach ($dfsrIdRecord in $dfsrIdRecords)
			{
				$guid		= ($dfsrIdRecord.GVsn | Select-String -Pattern "{.*?}").Matches[0].Value
				$version 	= [int](($dfsrIdRecord.GVsn | Select-String -Pattern "-v\d+").Matches[0].Value).Replace("-v","")
				$isInSync = $false 
				
				if ($vvHash.ContainsKey($guid))
				{
					$vvArray = $vvHash[$guid]
					for ($i=0; $i -lt $vvArray.Count;$i+=2)
					{
						if (($version -gt $vvArray[$i]) -and ($version -le $vvArray[$i+1]))
						{
							$isInSync = $true
							break
						}
					}
					if (!$isInSync)
					{
						$file = FileFromIdrecord $dfsrIdRecord
						Write-Output $file
						$backLogFileCount2++
					}
				}
			}
			Write-Host "Total pending outbound from API: $backLogFileCount"
			Write-Host "Total pending outbound parsed: $backLogFileCount2"
		}
		else
		{
			Write-Host "There are no pending outbound changes for the given replicated folder"
		}
	}	
	catch {
		Write-Host $_.Exception.GetType().Name ": " $_.Exception.Message
	}
}

#endregion


#region Main Script Body

$replicationGroupName = $replicationGroupName.Replace("\","\\")

$dfsrReplFolders = GetReplFoldersInGroup $TargetServer.ToUpper() $replicationGroupName

if ($dfsrReplFolders -eq $null) { 
	Write-Error "ERROR: Either the replication group was not found or it does not contain any replicated folders"
	break 
}

foreach ($dfsrReplFolder in $dfsrReplFolders) 
{
	$versionVector = GetReplFolderVersionVector $TargetServer.ToUpper() $dfsrReplFolder.ReplicatedFolderGuid
	if ($FullList)
	{
		GetFullDFSRDiff $SourceServer.ToUpper() $dfsrReplFolder.ReplicatedFolderGuid $versionVector
	}
	else
	{
		GetTop100DFSRDiff $SourceServer.ToUpper() $dfsrReplFolder.ReplicatedFolderGuid $versionVector
	}
}

#endregion