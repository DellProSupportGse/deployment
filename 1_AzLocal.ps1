# Configure Node & Azure Arc Settings
# v1.19
#By: Jim Gandy
### Fill out this section before you run it :)###

$N = "AZLNode1"
$M1 = "Embedded NIC 1"
$MI = "192.168.1.101"
$GW = "192.168.1.1"
$D = "192.168.1.1,192.168.1.2"
$P = 24
$V = ""
$NT = ""
$S = "YourSubscriptionID"
$R = "YourResourceGroupName"
$Z = "eastus"
$T = "YourTenantID"
$AGW = "" #Add you ARC gateway
$X = "" # Leave this blank if no proxy is required and DO NOT USE if using ARC Gateway
$TV = "" # Populate this field if you need a specific version https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2?view=azloc-2507&tabs=OS-build-25398-xxxx#supported-versions-of-azure-local
$F = "C:\dell"; New-Item $F -ItemType Directory -Force | Out-Null
Start-Transcript -Path "$F\Setup-$(Get-Date -Format "yyyyMMdd-HHmmss").txt" -Append

# Network Config
Get-NetAdapter | ? InterfaceDescription -inotmatch "NDIS" | Set-NetIPInterface -Dhcp Disabled
Get-NetAdapter | ? status -ne "up" | Disable-NetAdapter -Confirm:$false
IF((gip $M1).ipv4address.ipaddress -ne $MI){New-NetIPAddress -InterfaceAlias $M1 -IPAddress $MI -PrefixLength $P -DefaultGateway $GW  -ErrorAction SilentlyContinue -Confirm:$false}
Set-DnsClientServerAddress -InterfaceAlias $M1 -ServerAddresses $D -Confirm:$false
IF($V -ne ""){Set-NetAdapter -InterfaceAlias $((($M1 -split " ")[0..1] -join " ")+"*") -VlanId $V -Confirm:$false}
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
if ($env:COMPUTERNAME -ne $N) { Rename-Computer -NewName $N -Confirm:$false }
Set-TimeZone -Id "UTC"
if($NT){w32tm /config /manualpeerlist:$NT /syncfromflags:MANUAL /reliable:yes /update; Restart-Service w32time; w32tm /resync /nowait; w32tm /query /source}

# Eject CDROM
IF((Get-WmiObject Win32_CDROMDrive).Drive){(New-Object -ComObject Shell.Application).NameSpace(17).ParseName((Get-WmiObject Win32_CDROMDrive).Drive).InvokeVerb("Eject")}

# Create Azure Arc Registration Script
$A = "C:\dell\Arc-Register.ps1"
$Pp = if ($X) { "-Proxy `"$X`"" } else { "" }

if (!($AGW)) {
$C += @"
Invoke-AzStackHciArcInitialization -SubscriptionID `"$S`" -ResourceGroup `"$R`" -TenantID `"$T`" -Region `"$Z`" -Cloud "AzureCloud"
"@}
if ($AGW) {
$C += @"
`$ArcGwId = "/subscriptions/$S/resourceGroups/$R/providers/Microsoft.HybridCompute/gateways/$AGW"
Invoke-AzStackHciArcInitialization -SubscriptionID `"$S`" -ResourceGroup `"$R`" -TenantID `"$T`" -Region `"$Z`" -Cloud "AzureCloud" -ArcGatewayID `$ArcGwId
"@}
if ($TV){
$C += @"
 -TargetSolutionVersion `$TV
"@
}
$C += @"

Unregister-ScheduledTask -TaskName "DellAzureArcRegist*" -Confirm:`$false
pause
"@
$C | Set-Content $A

# Schedule Task for Azure Arc Registration
Register-ScheduledTask -TaskName "DellAzureArcRegister" -Trigger (New-ScheduledTaskTrigger -AtLogon) `
    -Action (New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$A`"") `
    -RunLevel Highest -Force

# Kernel Soft Reboot
if ((Read-Host "Ready to reboot? (Y/N)").Trim().ToUpper() -in @("Y", "YES")) {
    Stop-Transcript
    Restart-Computer -Force
} else { Stop-Transcript }
