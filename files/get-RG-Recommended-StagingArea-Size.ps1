
#############################
## Updates:
##  20140729 http://blogs.technet.com/b/askds/archive/2011/07/13/how-to-determine-the-minimum-staging-area-dfsr-needs-for-a-replicated-folder.aspx references for rule of thumb
## 
##
######################################################################
######################################################################
 
 
$BacklogErrorLevel = 100 
 
#$ComputerName = $env:ComputerName
$ComputerName = read-host "Computer Name to run against? FQDN"

## Query DFSR groups from the local MicrosftDFS WMI namespace.
$DFSRGroupWMIQuery = "SELECT * FROM DfsrReplicationGroupConfig"
$RGroups = Get-WmiObject -computername $computername -Namespace "root\MicrosoftDFS" -Query $DFSRGroupWMIQuery
 
## Setup my variables
$ping = New-Object System.Net.NetworkInformation.Ping
$SuccessAudit = $Null
$WarningAudit = $Null
$ErrorAudit = $Null
$EventSource = "Check-DFSR Script"
$SuccessEventID = 9500
$WarningEventID = 9501
$ErrorEventID = 9502
$NoPingEventID = 9503
 
foreach ($Group in $RGroups)
{
	if ($Group.ReplicationGroupName -eq "$TargetRGName")
	{
		##write-host "This is the RG ($Group.ReplicationGroupName) you are looking for..." -foregroundcolor green
		##Finding out some information about the status
		$DFSRGQuery = "SELECT * FROM DfsrReplicatedFolderInfo"
		$DFSRGInfo = Get-WmiObject -computername $computername -Namespace "root\MicrosoftDFS" -query $DFSRGQuery
		
		##Cycle Through all Replication Folder info to get information
		foreach ($DFSRG in $DFSRGInfo)
		{
			$DFSRGNAme = $DFSRG.ReplicatedFolderName
			$DFSRGStatus = $DFSRG.State
			$DFSRGStagingSize = $DFSRG.CurrentStageSizeInMB
			$DFSRGConflictSize = $DFSRG.CurrentConflictSizeInMB
			$DFSRGLastErrCode = $DFSRG.LastErrorCode
			$DFSRFLastMessID = $DFSRG.LastErrorMessageId
			$DFSRFLastTbCleanup = $DFSRG.LastTombStoneCleanupTime
			$DFSRFLastConfCleanup = $DFSRG.LastConflictCleanupTime
			
			
			
			if ($DFSRGNAme -eq $TargetRGFolder )
			{
				write-host "Details about $targetRGfolder..." -foregroundcolor green
					switch ($DFSRGStatus) 
					{ 
						0 {"$DFSRGNAme is Uninitialized."} 
						1 {"$DFSRGNAme is Initialized."} 
						2 {"$DFSRGNAme is Initial Sync."} 
						3 {"$DFSRGNAme is Auto Recovery."} 
						4 {"$DFSRGNAme is Normal."} 
						5 {"$DFSRGNAme is In Error."}  
						default {"$DFSRGNAme Status could not be determined."}
					}
				write-host "$DFSRGNAme Staging size = $DFSRGStagingSize"
				write-host "$DFSRGNAme Conflict size = $DFSRGConflictSize"
				write-host "Last Error Code = $DFSRGLastErrCode"
				write-host "Last Error Message ID = $DFSRFLastMessID"
				write-host "Last Tombstone Cleanup Time = $DFSRFLastTbCleanup"
				write-host "Last Conflict Cleanup Time = $DFSRFLastConfCleanup"
				}

		}
		
		## Cycle through all Replication groups found
		$DFSRGFoldersWMIQuery = "SELECT * FROM DfsrReplicatedFolderConfig WHERE ReplicationGroupGUID='" + $Group.ReplicationGroupGUID + "'"
		$RGFolders = Get-WmiObject -computername $computername -Namespace "root\MicrosoftDFS" -Query $DFSRGFoldersWMIQuery
		
		## Grab all connections associated with a Replication Group
		$DFSRConnectionWMIQuery = "SELECT * FROM DfsrConnectionConfig WHERE ReplicationGroupGUID='" + $Group.ReplicationGroupGUID + "'"
		$RGConnections = Get-WmiObject -computername $computername -Namespace "root\MicrosoftDFS" -Query $DFSRConnectionWMIQuery	
		foreach ($Connection in $RGConnections)
		{
			$ConnectionName = $Connection.PartnerName.Trim()
			$IsInBound = $Connection.Inbound
			$IsEnabled = $Connection.Enabled
			
			write-host "...and testing connection with $ConnectionName (enabled=$IsEnabled)" -foregroundcolor yellow
	 
			## Do not attempt to look at connections that are Disabled
			if ($IsEnabled -eq $True)
			{  
				## If the connection is not ping-able, do not attempt to query it for Backlog info
				$Reply = $ping.send("$ConnectionName")
				if ($reply.Status -eq "Success")
				{
	 
	 
					## Cycle through the Replication Folders that are part of the replication group and run DFSRDIAG tool to determine the backlog on the connection partners.
					foreach ($Folder in $RGFolders)
					{
						$RGName = $Group.ReplicationGroupName
						$RFName = $Folder.ReplicatedFolderName
	 
						## Determine if current connect is an inbound connection or not, set send/receive members accordingly
						if ($IsInBound -eq $True)
						{
							$SendingMember = $ConnectionName
							$ReceivingMember = $ComputerName
						}
						else
						{
							$SendingMember = $ComputerName
							$ReceivingMember = $ConnectionName
						}
						   $Out = $RGName + ":" + $RFName +  " - S:"+$SendingMember + " R:" + $ReceivingMember 
						   Write-Host $Out
							## Execute the dfsrdiag command and get results back in the $Backlog variable
							$BLCommand = "dfsrdiag Backlog /RGName:'" + $RGName + "' /RFName:'" + $RFName + "' /SendingMember:" + $SendingMember + " /ReceivingMember:" + $ReceivingMember
							$Backlog = Invoke-Expression -Command $BLCommand
	 
							$BackLogFilecount = 0
							foreach ($item in $Backlog)
							{
								if ($item -ilike "*Backlog File count*")
								{
									$BacklogFileCount = [int]$Item.Split(":")[1].Trim()
								}
	 
							}
	 
	 
							if ($BacklogFileCount -eq 0)
							{
								#Update Success Audit 
								$SuccessAudit += $RGName + ":" + $RFName + " is in sync with 0 files in the backlog from "+ $SendingMember + " to " + $ReceivingMember +".`n"					
	 
							}
							elseif ($BacklogFilecount -lt $BacklogErrorLevel)
							{
								#Update Warning Audit
								$WarningAudit += $RGName + ":" + $RFName + " has " + $BacklogFileCount + " files in the backlog from " + $SendingMember + " to " + $ReceivingMember + ".`n"
							}
							else
							{
								#Update Error Audit
								$ErrorAudit += $RGName + ":" + $RFName + " has " + $BacklogFilecount + " files in the backlog from " + $SendingMember + " to " + $ReceivingMember + ".`n"
							}
							Write-Host + $Folder.ReplicatedFolderName "- " $BackLogFilecount "files in backlog" -foregroundcolor yellow
						}
					}
					else
					{ 
					Write-Host $ConnectionName "is not pingable" 
					$NoPingMessage = "Server """ + $ConnectionName + """ could not be reached.`nPlease verify it is on the network and pingable."
					Write-Event $EventSource $NoPingEventID "Warning" $NoPingMessage "Application"
					}
				}
	 
		}
	 }
}
## Write my events to the local Application log.
 
if ($SuccessAudit -ne $Null)
{
	Write-Event $EventSource $SuccessEventID "Information" $SuccessAudit "Application"
}
 
if ($WarningAudit -ne $Null)
{
	Write-Event $EventSource $WarningEventID "Warning" $WarningAudit "Application"
}
 
if ($ErrorAudit -ne $Null)
{
	Write-Event $EventSource $ErrorEventID "Error" $ErrorAudit "Application"
}
