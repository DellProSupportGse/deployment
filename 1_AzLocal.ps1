# Run on each node after OS installation to set the IP info, rename and install NIC drivers in preperation for Azure deployment
# Variables
    $NodeName="AZLNode1"
# Management Nic Info
  $MgmtNic1 = "Port3"
  $MgmtNicIp="192.168.1.11"
  $MGMTNICGW="192.168.1.1"
  $DNSIps="192.168.1.100,192.168.1.101"
  $MgmtPrefixLength="24"
  $Mgmtvlan="124"

# Sets vLAN ID for Mgmt
  Set-NetAdapter -Name $MgmtNic1 -VlanID $Mgmtvlan -Confirm:$false

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
    IF(((Get-NetAdapter).InterfaceDescription | sort -Unique) -imatch "e810"){
	      Invoke-webrequest -Uri "https://dl.dell.com/FOLDER11890492M/1/Network_Driver_6JHVK_WN64_23.0.0_A00.EXE"   -UseBasicParsing -UserAgent "Mozilla/5.0" -outfile c:\dell\Network_Driver_e810.EXE
	      Start-Process  c:\dell\Network_Driver_e810.EXE -ArgumentList "/s" -NoNewWindow -Wait
    }
    IF(((Get-NetAdapter).InterfaceDescription | sort -Unique) -imatch "Mell"){
	      Invoke-webrequest -Uri "https://dl.dell.com/FOLDER11591518M/2/Network_Driver_G6M58_WN64_24.04.03_01.EXE"   -UseBasicParsing -UserAgent "Mozilla/5.0" -outfile c:\dell\Network_Driver_Mx.EXE
	      Start-Process  c:\dell\Network_Driver_Mx.EXE -ArgumentList "/s" -NoNewWindow -Wait
    }
    
# Reboot 
    Restart-computer
