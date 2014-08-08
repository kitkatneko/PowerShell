## Check-DFSR.ps1 script

#############################
## Updates:
##  20090408 Weaver: Fixed issue where multiple events are generated throughout the execution
##  20090408 Weaver: Added BacklogFileCount to event message
##  20090409 Weaver: Fixed list of replication connections issue due to change in replication topology
##  20090507 Weaver: Added functionality to return results from all partners in the replication
##  20140729 Puthod: Added functionality to return state RF and RG and computer to run against
##  20140729 Puthod: Added for passing computer name as an argument
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

##Testing for arguments
if ($args.Length -eq 0)
{
	write-host "Usage = check-dfsr.ps1 computername"
	exit
}
else
{ 
$ComputerName = $args[0]
write-host "Checking RG and RF on $ComputerName..."

}

#Verify connectivity
$RemoteHost = $ping.send("$ComputerName")
if ($RemoteHost.Status -eq "Success")
{
	## Writing output to logfile
	$ErrorActionPreference="SilentlyContinue"
	Stop-Transcript | out-null
	$ErrorActionPreference = "Continue" # or "Stop"
	$transcriptpath = ".\DFSRReports\"+$computername+"_DFSR.log"
	Start-Transcript -path $transcriptpath
	
	
	## Query DFSR groups config from the local MicrosftDFS WMI namespace.
	$DFSRGroupWMIQuery = "SELECT * FROM DfsrReplicationGroupConfig"
	$RGroups = Get-WmiObject -computername $computername -Namespace "root\MicrosoftDFS" -Query $DFSRGroupWMIQuery

	foreach ($Group in $RGroups)
	{
		## Cycle through all Replication groups found
		$DFSRGFoldersWMIQuery = "SELECT * FROM DfsrReplicatedFolderConfig WHERE ReplicationGroupGUID='" + $Group.ReplicationGroupGUID + "'"
		$RGFolders = Get-WmiObject -computername $computername -Namespace "root\MicrosoftDFS" -Query $DFSRGFoldersWMIQuery
		
		## Query DFSR Folders information from the local MicrosftDFS WMI namespace.
		$DFSRFolderInfoWMIQuery = "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicationGroupGUID='" + $Group.ReplicationGroupGUID + "'"
		$FoldersInfo = Get-WmiObject -computername $computername -Namespace "root\MicrosoftDFS" -Query $DFSRFolderInfoWMIQuery
		
		$FolderName = $FoldersInfo.ReplicatedFolderName
		$FolderState = $FoldersInfo.State
		write-host "Checking Folder: $FolderName (state: $FolderState)..." -foregroundcolor yellow
		
		## Grab all connections associated with a Replication Group
		$DFSRConnectionWMIQuery = "SELECT * FROM DfsrConnectionConfig WHERE ReplicationGroupGUID='" + $Group.ReplicationGroupGUID + "'"
		$RGConnections = Get-WmiObject -computername $computername -Namespace "root\MicrosoftDFS" -Query $DFSRConnectionWMIQuery	
		foreach ($Connection in $RGConnections)
		{
	 
			$ConnectionName = $Connection.PartnerName.Trim()
			$IsInBound = $Connection.Inbound
			$IsEnabled = $Connection.Enabled
	 
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
						   $Out = $RGName + ":" + $RFName +  " ("+ $RFState +") - S:"+$SendingMember + " R:" + $ReceivingMember 
						   #Write-Host $Out
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
								write-host $RGName":"$RFName" is in sync between "$SendingMember" and "$ReceivingMember -foregroundcolor green
	 
							}
							elseif ($BacklogFilecount -lt $BacklogErrorLevel)
							{
								#Update Warning Audit
								$WarningAudit += $RGName + ":" + $RFName + " has " + $BacklogFileCount + " files in the backlog from " + $SendingMember + " to " + $ReceivingMember + ".`n"
								write-host $RGName ":"$RFName" has "$BacklogFilecount" files in the backlog from "$SendingMember" to "$ReceivingMember -foregroundcolor Magenta
							}
							else
							{
								#Update Error Audit
								$ErrorAudit += $RGName + ":" + $RFName + " has " + $BacklogFilecount + " files in the backlog from " + $SendingMember + " to " + $ReceivingMember + ".`n"
								write-host $RGName ":" $RFName " has "$BacklogFilecount" files in the backlog from "$SendingMember" to "$ReceivingMember -foregroundcolor red
								
							}
							
						}
					}
					else
					{ 
					Write-Host $ConnectionName "is not pingable" -foregroundcolor red
					$NoPingMessage = "Server """ + $ConnectionName + """ could not be reached.`nPlease verify it is on the network and pingable."
					Write-Event $EventSource $NoPingEventID "Warning" $NoPingMessage "Application"
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
	stop-transcript
}
	
else
{ 
Write-Host $ConnectionName "is not pingable" -foregroundcolor red
$NoPingMessage = "Server """ + $ConnectionName + """ could not be reached.`nPlease verify it is on the network and pingable."
#exit
}