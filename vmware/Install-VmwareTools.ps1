 #Get-VM -Location (Get-Datacenter <Name of Datacenter>| Get-Cluster <Name of Cluster> | Get-Folder <Name of Folder>) | Update-Tools -NoReboot -RunAsync 
 Get-VM | Update-Tools -NoReboot -RunAsync 