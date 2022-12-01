## A Script to update the description of the server objects with a meaningful description
## Description PAABB-APP1,APP2-V/ppp
## P = prod, Test or dev [P,D,T]
## AA = Profit Center Code
## BB = Location code
## APP1 = Served Application part 1
## APP2 = Served Application part 2
## V = Virtual(V or H) or Physical
## ppp = impact [low or high] for maintenance, low = reboot anytime with no user impact

## variables
## the content file with header
$ContentFile = "\\achler.ca\xanthus\IT\Scripts\ActiveDirectory\Update-ServersDescription.csv"
$DebugPreference = "Continue" #[{Continue | Ignore | Inquire | SilentlyContinue | Stop |  Suspend }]

##Modules
Import-Module activedirectory

##Read the content
$AllServers = Import-Csv $ContentFile

##Find object in AD and update
Foreach ($server in $AllServers) {
	##Get the AD Object info
	if ($server -notlike "AssetName*"){
		$ServerName = $server.AssetName
		$ServerObject = Get-ADComputer -Filter "name -like '$ServerName'" -Properties description
		if ($ServerObject -ne "") {
			##found a match, updating description
			$NewDescription = $server.'New Description'
			$OldDescription = $ServerObject.description
			Set-ADComputer -Identity $ServerObject -Description $NewDescription
			Write-host Changed description from:$OldDescription to $NewDescription!
		}
	}
}
