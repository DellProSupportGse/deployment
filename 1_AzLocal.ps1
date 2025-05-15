# Configure Node & Azure Arc Settings
# v1.3
### Fill out this section before you run it :)###
$N = "AZLNode1"
$M1 = "Embedded NIC 1"
$MI = "192.168.1.101"
$GW = "192.168.1.1"
$D = "192.168.1.1,192.168.1.2"
$P = 24
$S = "YourSubscriptionID"
$R = "YourResourceGroupName"
$Z = "eastus"
$T = "YourTenantID"
$X = "" # Leave this blank if no proxy is required
$F = "C:\dell"; New-Item $F -ItemType Directory -Force | Out-Null
Start-Transcript -Path "$F\Setup-$(Get-Date -Format "yyyyMMdd-HHmmss").txt" -Append

# Network Config
Get-NetAdapter | ? InterfaceDescription -inotmatch "NDIS" | Set-NetIPInterface -Dhcp Disabled
New-NetIPAddress -InterfaceAlias $M1 -IPAddress $MI -PrefixLength $P -DefaultGateway $GW -Confirm:$false
Set-DnsClientServerAddress -InterfaceAlias $M1 -ServerAddresses $D -Confirm:$false
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
if ($env:COMPUTERNAME -ne $N) { Rename-Computer -NewName $N -Confirm:$false }

# Detect Dell Golden Image
$G=(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation").SupportProvider -imatch "Dell"
if (-not $G) {
    $H = @{
        "e8"   = "https://dl.dell.com/FOLDER11890492M/1/Network_Driver_6JHVK_WN64_23.0.0_A00.EXE"
        "Mell" = "https://dl.dell.com/FOLDER11591518M/2/Network_Driver_G6M58_WN64_24.04.03_01.EXE"
    }
    Get-NetAdapter | ForEach-Object {
        $U = if ($_.InterfaceDescription -match "e8") { $H["e8"] } elseif ($_.InterfaceDescription -match "Mell") { $H["Mell"] }
        if ($U) {
            Try {
                (New-Object Net.WebClient).DownloadFile($U, "$F\Network_Driver.exe")
                Start-Process "$F\Network_Driver.exe" -ArgumentList "/s" -NoNewWindow -Wait
            } Catch { Write-Warning "Failed to install driver for $($_.InterfaceDescription)" }
        }
    }
    # Rename NICs for Easier Identification
    Get-NetAdapterHardwareInfo | % {
        $I = if ($_.Function -ne $null) { $_.Function + 1 } else { 1 }
        $W = if ($_.Slot) { "Slot $($_.Slot) Port $I" } elseif ($_.PCIDeviceLabelString) { $_.PCIDeviceLabelString } else { "NIC$I" }
        if ($_.Name -ne $W) {
            try { Rename-NetAdapter -Name $_.Name -NewName $W -ErrorAction Stop } catch { Write-Warning "Failed to rename '$($_.Name)': $_" }
        }
    }
}

# Create Azure Arc Registration Script
$A = "C:\dell\Arc-Register.ps1"
$Pp = if ($X) { "-Proxy `"$X`"" } else { "" }
$C = if (-not $G) {
@"
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:`$false
@("Az.Accounts -MinimumVersion 4.0.2", "AzStackHci.EnvironmentChecker -MinimumVersion 1.2100.3000.663") | % {
    Install-Module -Name `$_ -Force -AllowClobber -SkipPublisherCheck -Confirm:`$false
}
"@} else { "" }

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
