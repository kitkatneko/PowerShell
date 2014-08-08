#http://support.microsoft.com/kb/2663685 sets stopreplicationonautorecovery to TRUE
#we want it to FALSE so that recovery start replication automatically.
#look for stops (eventid 2213) and starts (event 2214)

set-itemproperty -path HKLM:\System\CurrentControlSet\Services\DFSR\Parameters -name StopReplicationOnAutoRecovery -value 0
wmic /namespace:\\root\microsoftdfs path dfsrmachineconfig set StopReplicationOnAutoRecovery=FALSE