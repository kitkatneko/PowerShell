
#############################
## Updates:
##  20090408 Weaver: Fixed issue where multiple events are generated throughout the execution
##  20090408 Weaver: Added BacklogFileCount to event message
##  20090409 Weaver: Fixed list of replication connections issue due to change in replication topology
##  20090507 Weaver: Added functionality to return results from all partners in the replication
##  20140728 Florian: Added filter to monitoring only RG from a specific computer
##
##
######################################################################
######################################################################
# Write-Event powershell function
# Written by Mike Hays
# http://blog.mike-hays.net
#
#
 
function Write-Event(
	[string]$Source = $(throw "An event Source must be specified."),
	[int]$EventId = $(throw "An Event ID must be specified."),
	[System.Diagnostics.EventLogEntryType] $EventType = $(throw "Event EventType must be specified. (Error, Warning, Information, SuccessAudit, FailureAudit)"),
	[string]$Message = $(throw "An event Message must be specified."),
	$EventLog
)
{
	#Uncommon event logs can be specified (even custom ones), but since that isn't generally
	#the desired result, I prevent that here
	$acceptedEventLogs = "Application", "System"
	if ($eventEventLog -eq $null)
	{
		$eventEventLog = "Application"
	}
	elseif (!($acceptedEventLogs -icontains $eventEventLog))
	{
		Write-Host "This function supports writing to the following event logs:" $acceptedEventLogs
		Write-Host "Defaulting to Application Eventlog"
		$eventEventLog = "Application"
	}
 
	#Create a .NET object that is connected to the Eventlog
	$event = New-Object -type System.Diagnostics.Eventlog -argumentlist $EventLog
	#Define the Source property
	$event.Source = $Source
	#Write the event to the log
	$event.WriteEntry($Message, $EventType, $EventId)
}
 
######################################################################
######################################################################
## Main 
## Errors written:
##   Log File: Application
##   Source: Check-DFSR Script
##   ID: 9500 - Lists fully replicated replication folders
##   ID: 9501 - Lists replication folders with less than the $BacklogErrorLevel files waiting 
##   ID: 9502 - Lists replication folders with more than the $BacklogErrorLevel files waiting
##   ID: 9503 - If a connection is not pingable, this event is written.
 
$BacklogErrorLevel = 100 
 
#$ComputerName = $env:ComputerName
$ComputerName = read-host "Computer Name to run against? FQDN"

## Query DFSR groups from the local MicrosftDFS WMI namespace.
$DFSRGroupWMIQuery = "SELECT * FROM DfsrReplicationGroupConfig"
$RGroups = Get-WmiObject -computername $computername -Namespace "root\MicrosoftDFS" -Query $DFSRGroupWMIQuery
 
 write-host "Listing all RG on $computername ..." -foregroundcolor green
foreach ($RGitem in $RGroups)
{
	$itemName = $RGitem.ReplicationGroupName.trim()
	write-host "$itemName"
}

##Read intersting RGName
$TargetRGName = read-host "Which RGName are you looking for?"
$TargetRGFolder = "tb_clients"
 
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
