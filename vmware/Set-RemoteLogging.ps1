# Remote Syslogging setup for ESXi Hosts in a particular datacenter object
# Version 1.0
# Get-Date = 15/12/2011

#region Set variables up
$SyslogDatastore = "SharedDatastore2" # The name of the Shared Datastore to use for logging folder location - must be accessible to all ESXi hosts
$SyslogFolderName = "ESXi-Syslogging" # The name of the folder you want to use for logging - must NOT already exist
$RemoteSyslogHost = "udp://192.168.1.247:514" #specify your own Remote Syslog host here in this format
$DataCenters = Get-Datacenter
$FoundMatch = $false
$SyslogDatastoreLogDir = "[" + $SyslogDatastore + "]"
#endregion

#region Determine DataCenter to work with
if (($DataCenters).Count -gt 1) {
	Write-Host "Found more than one DataCenter in your environment, please specify the exact name of the DC you want to work with..."
	$DataCenter = Read-Host
	foreach ($DC in $DataCenters) {
		if ($DC.Name -eq $DataCenter) {
			Write-Host "Found Match ($DataCenter). Proceeding..."
			$FoundMatch = $true
			break
			}
		else {
			$FoundMatch = $false
			}
	}
	if ($FoundMatch -eq $false) {
		Write-Host "That input did not match any valid DataCenters found in your environment. Please run script again, and try again."
		exit		
		}
	}
else {
	$DataCenter = ($DataCenters).Name
	Write-Host "Only one DC found, so using this one. ($DataCenter)"
	}
#endregion

#Enough of the error checking, lets get to the script!

$VMHosts = Get-Datacenter $DataCenter | Get-VMHost | Where {$_.ConnectionState -eq "Connected"}

cd vmstore:
cd ./$DataCenter
cd ./$SyslogDatastore
if (Test-Path $SyslogFolderName) {
	Write-Host "Folder already exists. Configure script with another folder SyslogFolderName & try again."
	exit
}
else {
	mkdir $SyslogFolderName
	cd ./$SyslogFolderName
}

# Crux of the script in here:
foreach ($VMHost in $VMHosts) {
	if (Test-Path $VMHost.Name) {
		Write-Host "Path for ESXi host log directory already exists. Aborting script."
		exit
	}
	else {
		mkdir $VMHost.Name
		Write-Host "Created folder: $VMHost.Name"
		$FullLogPath = $SyslogDatastoreLogDir + "/" + $SyslogFolderName + "/" + $VMHost.Name
		Set-VMHostAdvancedConfiguration -VMHost $VMHost -Name "Syslog.global.logHost" -Value $RemoteSyslogHost
		Set-VMHostAdvancedConfiguration -VMHost $VMHost -Name "Syslog.global.logDir" -Value $FullLogPath
		Write-Host "Paths set: HostLogs = $RemoteSyslogHost LogDir = $FullLogPath"
	}
}