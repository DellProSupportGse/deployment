# Configure Node & Azure Arc Settings
# v1.5
### Fill out this section before you run it :)###
$N = "AZLNode1"
$M1 = "Embedded NIC 1"
$MI = "192.168.1.101"
$GW = "192.168.1.1"
$D = "192.168.1.1,192.168.1.2"
$P = 24
$V = ""
$S = "YourSubscriptionID"
$R = "YourResourceGroupName"
$Z = "eastus"
$T = "YourTenantID"
$X = "" # Leave this blank if no proxy is required
$F = "C:\dell"; New-Item $F -ItemType Directory -Force | Out-Null
Start-Transcript -Path "$F\Setup-$(Get-Date -Format "yyyyMMdd-HHmmss").txt" -Append

# Network Config
Get-NetAdapter | ? InterfaceDescription -inotmatch "NDIS" | Set-NetIPInterface -Dhcp Disabled
IF($V -ne ""){Set-NetAdapter -InterfaceAlias $M1 -VlanId $V -Confirm:$false}
New-NetIPAddress -InterfaceAlias $M1 -IPAddress $MI -PrefixLength $P -DefaultGateway $GW -Confirm:$false
Set-DnsClientServerAddress -InterfaceAlias $M1 -ServerAddresses $D -Confirm:$false
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
if ($env:COMPUTERNAME -ne $N) { Rename-Computer -NewName $N -Confirm:$false }

# Create Azure Arc Registration Script
$A = "C:\dell\Arc-Register.ps1"
$Pp = if ($X) { "-Proxy `"$X`"" } else { "" }

# Uninstall all versions except 4.0.2
Get-InstalledModule -Name Az.Accounts -AllVersions -ErrorAction SilentlyContinue | Where-Object { $_.Version -ne '4.0.2' } | ForEach-Object { Uninstall-Module -Name $_.Name -RequiredVersion $_.Version -Force -ErrorAction SilentlyContinue }
# Ensure 4.0.2 is installed
IF(-not (Get-InstalledModule -Name Az.Accounts -AllVersions | Where-Object { $_.Version -eq '4.0.2'})){Install-Module -Name Az.Accounts  -RequiredVersion "4.0.2" -Force -AllowClobber -SkipPublisherCheck -Confirm:$false -ErrorAction SilentlyContinue}}

$C += @"
Connect-AzAccount -SubscriptionId `"$S`" -TenantId `"$T`" -DeviceCode
`$AT = (Get-AzAccessToken -WarningAction SilentlyContinue).Token
`$I = (Get-AzContext).Account.Id
Invoke-AzStackHciArcInitialization -SubscriptionID `"$S`" -ResourceGroup `"$R`" -TenantID `"$T`" -Region `"$Z`" -Cloud "AzureCloud" -ArmAccessToken `$AT -AccountID `$I $Pp
Unregister-ScheduledTask -TaskName "AzureArcRegister" -Confirm:`$false
"@
$C | Set-Content $A

# Schedule Task for Azure Arc Registration
Register-ScheduledTask -TaskName "AzureArcRegister" -Trigger (New-ScheduledTaskTrigger -AtLogon) `
    -Action (New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$A`"") `
    -RunLevel Highest -Force

# Kernel Soft Reboot
if ((Read-Host "Ready to fast reboot? (Y/N)").Trim().ToUpper() -in @("Y", "YES")) {
    Stop-Transcript
    Start-Process "ksrcmd.exe" -ArgumentList "/self" -NoNewWindow -Wait
} else { Stop-Transcript }
