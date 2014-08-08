#$machines = get-cluster “Toronto” | get-vm
$machines = get-vm
foreach ($vm in $machines){
if ( $vm.guest.OSFullName -like “*Windows*")
{
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.changeVersion = $vm.ExtensionData.Config.ChangeVersion
$spec.tools = New-Object VMware.Vim.ToolsConfigInfo
$spec.tools.toolsUpgradePolicy = “upgradeAtPowerCycle”

$_this = Get-View -Id $vm.Id
$_this.ReconfigVM_Task($spec)
}
}