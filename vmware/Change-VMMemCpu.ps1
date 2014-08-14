###################################################################
#
# Change-VM_Memory_CPU_Count.ps1
#
# -MemoryMB the amount of Memory you want 
#  to add or remove from the VM in MB
# -MemoryOption Add/Remove
# -CPUCount the amount of vCPU's you want 
#  to add or remove from the VM
# -CPUOption Add/Remove
#
# Example:
# .\Change-VM_Memory_CPU_Count.ps1 -vCenter vc01 
# -vmName NAGIOS -MemoryMB 512 -MemoryOption Add 
# -CPUCount 1 -CPUOption Remove
#
# Version 1.0 May 2010 Arne Fokkema www.ict-freak.nl @afokkema

#
####################################################################

param(
    [parameter(Mandatory = $true)]
    [string[]]$vCenter,
    [parameter(Mandatory = $true)]
    [string]$vmName,
    [int]$MemoryMB,
    [string]$MemoryOption,
    [int]$CPUCount,
    [string]$CPUOption
)    

function PowerOff-VM{
    param([string] $vm)
    
    Shutdown-VMGuest -VM (Get-VM $vm) -Confirm:$false | Out-Null
    Write-Host "Shutdown $vm"
    do {
        $status = (get-VM $vm).PowerState
    }until($status -eq "PoweredOff")
    return "OK"
}

function PowerOn-VM{
    param( [string] $vm)
    
    if($vm -eq ""){    Write-Host "Please enter a valild VM name"}
    
    if((Get-VM $vm).powerstate -eq "PoweredOn"){
        Write-Host "$vm is already powered on"}
    
    else{
        Start-VM -VM (Get-VM $vm) -Confirm:$false | Out-Null
        Write-Host "Starting $vm"
        do {
            $status = (Get-vm $vm | Get-View).Guest.ToolsRunningStatus
        }until($status -eq "guestToolsRunning")
        return "OK"
    }
}

function Change-VMMemory{
    param([string]$vmName, [int]$MemoryMB, [string]$Option)
    if($vmName -eq ""){
        Write-Host "Please enter a VM Name"
        return
    }
    if($MemoryMB -eq ""){
        Write-Host "Please enter an amount of Memory in MB"
        return
    }
    if($Option -eq ""){
        Write-Host "Please enter an option to add or remove memory"
        return
    }

    $vm = Get-VM $vmName    
    $CurMemoryMB = ($vm).MemoryMB
    
    if($vm.Powerstate -eq "PoweredOn"){
        Write-Host "The VM must be Powered Off to continue"
        return
    }
    
    if($Option -eq "Add"){
        $NewMemoryMB = $CurMemoryMB + $MemoryMB
    }
    elseif($Option -eq "Remove"){
        if($MemoryMB -ge $CurMemoryMB){
            Write-Host "The amount of memory entered is greater or equal than 
            the current amount of memory allocated to this VM"
            return
        }
        $NewMemoryMB = $CurMemoryMB - $MemoryMB
    }

    $vm | Set-VM -MemoryMB $NewMemoryMB -Confirm:$false
    Write-Host "The new configured amount of memory is"(Get-VM $VM).MemoryMB
}

function Change-VMCPUCount{
    param([string]$vmName, [int]$NumCPU, [string]$Option)
    if($vmName -eq ""){
        Write-Host "Please enter a VM Name"
        return
    }
    if($NumCPU -eq ""){
        Write-Host "Please enter the number of vCPU's you want to add"
        return
    }
    if($Option -eq ""){
        Write-Host "Please enter an option to add or remove vCPU"
        return
    }

    $vm = Get-VM $vmName    
    $CurCPUCount = ($vm).NumCPU
    
    if($vm.Powerstate -eq "PoweredOn"){
        Write-Host "The VM must be Powered Off to continue"
        return
    }
    
    if($Option -eq "Add"){
        $NewvCPUCount = $CurCPUCount + $NumCPU
    }
    elseif($Option -eq "Remove"){
        if($NumCPU -ge $CurCPUCount){
            Write-Host "The number of vCPU's entered is higher or equal 
            than the current number of vCPU's allocated to this VM"
            return
        }
        $NewvCPUCount = $CurCPUCount - $NumCPU
    }

    $vm | Set-VM -NumCPU $NewvCPUCount -Confirm:$false
    Write-Host "The new configured number of vCPU's is"(Get-VM $VM).NumCPU
}

#######################################################################################
# Main script
#######################################################################################

$VIServer = Connect-VIServer $vCenter
If ($VIServer.IsConnected -ne $true){
    Write-Host "error connecting to $vCenter" -ForegroundColor Red
    exit
}

if($MemoryMB -or $CPUCount -ne "0"){
    $poweroff = PowerOff-VM $vmName
    if($poweroff -eq "Ok"){
    Write-Host "PowerOff OK"

        if($MemoryMB -ne "0"){
            if($MemoryOption -eq " ") {Write-Host "Please enter an option to add or remove memory"}
            else{
                Change-VMMemory $vmName $MemoryMB $MemoryOption
            }
        }

        if($CPUCount -ne "0"){
            if($CPUOption -eq " ") {Write-Host "Please enter an option to add or remove cpu"}
            else{
                Change-VMCPUCount $vmName $CPUCount $CPUOption
            }
        }
        
        $poweron = PowerOn-VM $vmName
        if($poweron -eq "Ok"){
            Write-Host "PowerOn OK"}
    }
}

Disconnect-VIServer -Confirm:$false