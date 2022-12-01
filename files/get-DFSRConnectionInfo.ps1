##Script to retrieve all information about connections details in order to perhaps build some diagram or usefull output
##for now I use it raw and import it to excel as a pivot table

##change log
## 20140808 name: first go


##Variables
$DebugPreference = "SilentlyContinue" #[{Continue | Ignore | Inquire | SilentlyContinue | Stop |  Suspend }]
$RGs = $null
$RGitem = $null
$CurrentRGItem = $null
$ConnItem = $null

##Get the RG list
$RGs = DfsrAdmin.exe RG list /Attr:RgName

##Cycle through the RG list to connections information
foreach ($RGitem in $RGs) {
	Write-Debug "RGItem= $RGitem"
	if (($RGitem -notlike "*RgName*") -and ($RGitem -notlike "*Command*") -and ($RGitem -notlike "*domain*")) {
		Write-Debug "Looping on $RGItem"
		##Getting the list of connexions for this item
		$CurrentRGItem = DfsrAdmin.exe conn list /rgname:$RGItem /attr:"SendMem,ConnSendSite,RecvMem,ConnRecvSite,ConnEnabled,RepHrsWeek,ConnType,SchedType,MaxBW,ConnRdcEnabled"
		
		
		##Cycle Through to remove header and build array
		foreach ($ConnItem in $CurrentRGItem) {
		if (($ConnItem -notlike "*SendMem*") -and ($ConnItem -notlike "*Command*") -and ($ConnItem -ne "")){
			Write-Debug "Looping on connection't't list"
			$ConnItemLine = $RGitem+" "+$ConnItem
			Write-Output $ConnItemLine 
		}
		}
	}
}
