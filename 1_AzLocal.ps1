# Run on each node after OS installation to set the IP info, rename and install NIC drivers in preperation for Azure deployment
# Version 1.1

# Variables
    $NodeName="AZLNode1"
# Management Nic Info
  $MgmtNic1 = "Port3"
  $MgmtNicIp="192.168.1.11"
  $MGMTNICGW="192.168.1.1"
  $DNSIps="192.168.1.100,192.168.1.101"
  $MgmtPrefixLength="24"
  $Mgmtvlan=""

# Sets vLAN ID for Mgmt
  IF( $Mgmtvlan.length -gt 0){
      Set-NetAdapter -Name $MgmtNic1 -VlanID $Mgmtvlan -Confirm:$false
  }

# Configures IP addresses for the NICs
    New-NetIPAddress -InterfaceAlias $MgmtNic1 -IPAddress $MgmtNicIp  -PrefixLength $MgmtPrefixLength -DefaultGateway $MGMTNICGW -Confirm:$false

    #Set DNS -comma delimit 2nd DNS Server
    Set-DnsClientServerAddress -InterfaceAlias $MgmtNic1 -ServerAddresses $DNSIps -Confirm:$false

# Enable Remote Desktop
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Rename node
    IF(($env:COMPUTERNAME) -inotmatch $NodeName){Rename-Computer -NewName $NodeName -Confirm:$False}

# Download and Install Nic driver
    md c:\dell
    IF(((Get-NetAdapter).InterfaceDescription | sort -Unique) -imatch "e8"){
	      Invoke-webrequest -Uri "https://dl.dell.com/FOLDER11890492M/1/Network_Driver_6JHVK_WN64_23.0.0_A00.EXE"   -UseBasicParsing -UserAgent "Mozilla/5.0" -outfile c:\dell\Network_Driver_e810.EXE
	      Start-Process  c:\dell\Network_Driver_e810.EXE -ArgumentList "/s" -NoNewWindow -Wait
    }
    IF(((Get-NetAdapter).InterfaceDescription | sort -Unique) -imatch "Mell"){
	      Invoke-webrequest -Uri "https://dl.dell.com/FOLDER11591518M/2/Network_Driver_G6M58_WN64_24.04.03_01.EXE"   -UseBasicParsing -UserAgent "Mozilla/5.0" -outfile c:\dell\Network_Driver_Mx.EXE
	      Start-Process  c:\dell\Network_Driver_Mx.EXE -ArgumentList "/s" -NoNewWindow -Wait
    }
    
# Set NIC Names to the old naming for easy of identification
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

# Prompt before rebooting
	$confirm = Read-Host "Rename complete. Ready to reboot? (Y/N)"
	if ($confirm -match '^(Y|Yes)$') {
	    Restart-Computer
	} else {
	    Write-Host "Reboot skipped."
	}
