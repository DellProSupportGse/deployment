# ========================
# Configure Node Settings
# ========================
#v1.2
# Variables
$NodeName = "AZLNode1"

# Management NIC Info
$MgmtNic1 = "Port3"
$MgmtNicIp = "192.168.1.11"
$MGMTNICGW = "192.168.1.1"
$DNSIps = "192.168.1.100,192.168.1.101"
$MgmtPrefixLength = 24
$Mgmtvlan = ""

# Start transcript logging in C:\dell
$driverFolder = "C:\dell"
if (-not (Test-Path $driverFolder)) {
    New-Item -Path $driverFolder -ItemType Directory | Out-Null
    Write-Host "Created driver folder: $driverFolder"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptPath = "$driverFolder\Setup-$timestamp.txt"
Start-Transcript -Path $transcriptPath -Append


Write-Host "Starting configuration for node: $NodeName"

# Set VLAN ID for Management NIC if provided
if ($Mgmtvlan -ne "") {
    Set-NetAdapter -Name $MgmtNic1 -VlanID $Mgmtvlan -Confirm:$false
    Write-Host "VLAN ID $Mgmtvlan set on $MgmtNic1"
}

# Configure IP address and gateway
New-NetIPAddress -InterfaceAlias $MgmtNic1 -IPAddress $MgmtNicIp -PrefixLength $MgmtPrefixLength -DefaultGateway $MGMTNICGW -Confirm:$false
Write-Host "Assigned IP $MgmtNicIp/$MgmtPrefixLength to $MgmtNic1 with gateway $MGMTNICGW"

# Set DNS Servers
Set-DnsClientServerAddress -InterfaceAlias $MgmtNic1 -ServerAddresses $DNSIps -Confirm:$false
Write-Host "Set DNS servers on $MgmtNic1 to $DNSIps"

# Enable Remote Desktop
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Write-Host "Remote Desktop enabled"

# Rename computer if needed
if ($env:COMPUTERNAME -ne $NodeName) {
    Rename-Computer -NewName $NodeName -Confirm:$false
    Write-Host "Computer will be renamed to $NodeName on reboot"
}

# Detect and install appropriate NIC drivers
$nicList = Get-NetAdapter | Select-Object -ExpandProperty InterfaceDescription

if ($nicList -match "e8") {
    $url = "https://dl.dell.com/FOLDER11890492M/1/Network_Driver_6JHVK_WN64_23.0.0_A00.EXE"
    $file = "$driverFolder\Network_Driver_e810.EXE"
    try {
        Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent "Mozilla/5.0" -OutFile $file -ErrorAction Stop
        Start-Process $file -ArgumentList "/s" -NoNewWindow -Wait
        Write-Host "Installed Intel E810 driver"
    } catch {
        Write-Warning "Failed to download or install Intel E810 driver"
    }
}
elseif ($nicList -match "Mell") {
    $url = "https://dl.dell.com/FOLDER11591518M/2/Network_Driver_G6M58_WN64_24.04.03_01.EXE"
    $file = "$driverFolder\Network_Driver_Mx.EXE"
    try {
        Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent "Mozilla/5.0" -OutFile $file -ErrorAction Stop
        Start-Process $file -ArgumentList "/s" -NoNewWindow -Wait
        Write-Host "Installed Mellanox driver"
    } catch {
        Write-Warning "Failed to download or install Mellanox driver"
    }
}

# Rename NICs for easier identification
$AdaptersHWInfo = Get-NetAdapterHardwareInfo

foreach ($Adapter in $AdaptersHWInfo) {
    $functionIndex = if ($Adapter.Function -ne $null) { $Adapter.Function + 1 } else { 1 }

    if ($Adapter.Slot) {
        $NewName = "Slot $($Adapter.Slot) Port $functionIndex"
    } elseif ($Adapter.PCIDeviceLabelString) {
        $NewName = $Adapter.PCIDeviceLabelString
    } else {
        $NewName = "NIC$functionIndex"
    }

    if ($Adapter.Name -ne $NewName) {
        try {
            Rename-NetAdapter -Name $Adapter.Name -NewName $NewName -ErrorAction Stop
            Write-Host "Renamed '$($Adapter.Name)' to '$NewName'"
        } catch {
            Write-Warning "Failed to rename '$($Adapter.Name)': $_"
        }
    }
}

# Prompt for reboot
$confirm = Read-Host "Ready to reboot? (Y/N)"
if ($confirm.Trim().ToUpper() -in @("Y", "YES")) {
    Stop-Transcript
    Restart-Computer
} else {
    Write-Host "Reboot skipped."
    Stop-Transcript
}
