#Configure iSCSI Non-Converged with RDMA per node
#Version 1.0

#Varables (modify these per node)
    #Managment Nics
        $MgmtNics=@()
        $MgmtNic1 = "Integrated NIC 1 Port 1-1"
        $MgmtNics += $MgmtNic1
        $MgmtNics += "Integrated NIC 1 Port 2-1"
        $MgmtNicIp="10.0.1.1"
        $MGMTNICGW="10.0.10.1"
        $DNSIps="10.0.0.1,10.0.0.2"
        $VMSwitchName="Mgmt"
        $MgmtNicName="Mgmt"
        $MgmtPrefixLength="24"
        $Mgmtvlan="10"

        $ClusNicIp="10.0.2.1"
        $ClusNicName="Cluster"
        $MgmtPrefixLength="24"
        $Clusvlan="20"
        $CfgRdma="True" #Set to False if no RDMA
    
    #Storage Nics
        $S1Nic="SLOT 6 Port 1"
        $S2Nic="SLOT 6 Port 2"
        $S1NicIp="10.0.11.1"
        $S2NicIp="10.0.12.1"
        $S1PrefixLength="24"
        $S2PrefixLength="24"
        $S1vlan="0"
        $S2vlan="0"
        $S1NicName="$S1Nic (iSCSI1)"
        $S2NicName="$S2Nic (iSCSI2)"

#Mgmt IP
    New-NetIPAddress -InterfaceAlias $MgmtNic1 -IPAddress $MgmtNicIp  -PrefixLength $MgmtPrefixLength -DefaultGateway $MGMTNICGW -Confirm:$false
    Set-NetAdapter -Name $MgmtNic1 -VlanID $Mgmtvlan -Confirm:$false
    # Set DNS -comma delimit 2nd DNS Server
    Get-NetAdapter $MgmtNic1 | Set-DnsClientServerAddress -ServerAddress $DNSIps -Confirm:$false

#Install Roles
    Install-WindowsFeature -Name Hyper-V,Failover-Clustering,Data-Center-Bridging -IncludeManagementTools -IncludeAllSubFeature -Confirm:$false -Restart

#Creates the Virtual Switch 
    New-VMSwitch -Name $VMSwitchName -AllowManagementOS 0 -NetAdapterName $MgmtNics -MinimumBandwidthMode Weight -Verbose -Confirm:$false
    #Added to resolve the posibility of MAC address conflicts with the Host NICs
    $RMAC=((1..4)|%{"abcdef0123456789".ToCharArray() | Get-Random}) -join ''
    $RMACMin="00155D"+$RMAC+"00"
    $RMACMax="00155D"+$RMAC+"FF"
    Set-VMHost -MacAddressMinimum ($RMACMin) -MacAddressMaximum  ($RMACMax) -Confirm:$false
    Set-NetAdapterAdvancedProperty -Name $MgmtNic1 -DisplayName "VLAN ID" -DisplayValue 0 -Confirm:$false

#Creates the Virtual Network Cards with random MAC addresses to prevent conflicts
    $RMAC=((1..6)|%{"abcdef0123456789".ToCharArray() | Get-Random}) -join ''
    $RMAC="00155D"+$RMAC
    Add-VMNetworkAdapter -ManagementOS -name $MgmtNicName -SwitchName $VMSwitchName -StaticMacAddress $RMAC -Confirm:$false
    $RMAC=((1..6)|%{"abcdef0123456789".ToCharArray() | Get-Random}) -join ''
    $RMAC="00155D"+$RMAC
    Add-VMNetworkAdapter -ManagementOS -name "Cluster" -SwitchName $VMSwitchName -StaticMacAddress $RMAC -Confirm:$false
    
#Sets each vNIC with it own vLAN ID
   Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $MgmtNicName -Access -VlanId $Mgmtvlan -Confirm:$false
   Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $ClusNicName -Access -VlanId $Clusvlan -Confirm:$false
   Set-NetAdapter -Name $S1Nic -VlanID $S1vlan -Confirm:$false
   Set-NetAdapter -Name $S2Nic -VlanID $S2vlan -Confirm:$false

#Configures IP addresses for the vNICs
    Get-NetAdapter "vEthernet ($MgmtNicName)" | New-NetIPAddress -IPAddress $MgmtNicIp  -PrefixLength $MgmtPrefixLength -DefaultGateway $MGMTNICGW -Confirm:$false
    sleep 15
    Get-NetAdapter "vEthernet ($ClusNicName)" | New-NetIPAddress -IPAddress $ClusNicIp  -PrefixLength $MgmtPrefixLength -Confirm:$false
    New-NetIPAddress -InterfaceAlias $S1Nic -IPAddress $S1NicIp -PrefixLength $S1PrefixLength -Confirm:$false
    New-NetIPAddress -InterfaceAlias $S2Nic -IPAddress $S2NicIp -PrefixLength $S2PrefixLength -Confirm:$false

    #Set DNS -comma delimit 2nd DNS Server
    Get-NetAdapter "vEthernet ($MgmtNicName)" | Set-DnsClientServerAddress -ServerAddress $DNSIps -Confirm:$false
    Get-NetAdapter "vEthernet ($ClusNicName)" | Set-DnsClientServerAddress -ServerAddress $DNSIps -Confirm:$false

#Enable Remote Desktop
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

#Fix Live Migration
    New-Item -Path HKLM:\SYSTEM\CurrentControlSet\Services\Vid\Parameters
    New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\Vid\Parameters -Name SkipSmallLocalAllocations -Value 0 -PropertyType DWord

#Set power profile to High Performance
    powercfg /setactive SCHEME_MIN

#Max Rx and Tx queues should be max values
    If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "QLogic"){
        Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Receive Buffers*" -DisplayValue 35000 -Confirm:$false
        Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Transmit Buffers*" -DisplayValue 5000 -Confirm:$false
    }
    If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "Mellanox"){
        Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Receive Buffers*" -DisplayValue 4096 -Confirm:$false
        Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Send Buffers*" -DisplayValue 2048 -Confirm:$false
    }
    If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "E810"){
        Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Receive Buffers*" -DisplayValue 4096 -Confirm:$false
        IF(Get-NetAdapterAdvancedProperty $S1Nic,$S2Nic -DisplayName "Send Buffers*" -ErrorAction SilentlyContinue){
		Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Send Buffers*" -DisplayValue 4096 -Confirm:$false}
  	    else{Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Transmit Buffers*" -DisplayValue 512 -Confirm:$false}
    }
    
# Exclude iDRAC NIC from Cluster
    New-Item -Path HKLM:\system\currentcontrolset\services\clussvc\parameters -Force
    New-ItemProperty -Path HKLM:\system\currentcontrolset\services\clussvc\parameters -Name ExcludeAdaptersByDescription -Value "Remote NDIS based Device" -Force

#Enable Jumbo Frames
    Set-NetAdapterAdvancedProperty -Name SLOT* -DisplayName "Jumbo Packet" -DisplayValue "9014" -Confirm:$false
    Set-NetAdapterAdvancedProperty -Name vETH* -DisplayName "Jumbo Packet" -DisplayValue "9014 bytes" -Confirm:$false

# Disable deplayed ack
    $strGUIDS = Get-WmiObject Win32_NetworkAdapter -Filter "NetConnectionStatus = 2" | Select-Object -ExpandProperty GUID
    foreach ($strGUID in $strGUIDS) {New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$strGUID" -Name TcpAckFrequency -PropertyType DWord -Value 1 -Force}   

IF($CfgRdma -eq "True"){
  #Set RDMA
      If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "QLogic" -or (Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "810" ){
          Set-NetAdapterAdvancedProperty -Name $S1Nic -DisplayName 'NetworkDirect Technology' -DisplayValue 'iWarp' -Confirm:$false
          Set-NetAdapterAdvancedProperty -Name $S2Nic -DisplayName 'NetworkDirect Technology' -DisplayValue 'iWarp' -Confirm:$false
      }
      If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "E810"){
          Set-NetAdapterAdvancedProperty -Name $S1Nic -DisplayName 'NetworkDirect Technology' -DisplayValue 'iWarp' -Confirm:$false
          Set-NetAdapterAdvancedProperty -Name $S2Nic -DisplayName 'NetworkDirect Technology' -DisplayValue 'iWarp' -Confirm:$false
      }        
      If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "Mellanox"){
          Set-NetAdapterAdvancedProperty -Name $S1Nic -DisplayName 'DcbxMode' -DisplayValue 'Host In Charge' -Confirm:$false
          Set-NetAdapterAdvancedProperty -Name $S2Nic -DisplayName 'DcbxMode' -DisplayValue 'Host In Charge' -Confirm:$false
          Set-NetAdapterAdvancedProperty -Name $S1Nic -DisplayName 'NetworkDirect Technology' -DisplayValue 'RoCEv2' -Confirm:$false
          Set-NetAdapterAdvancedProperty -Name $S2Nic -DisplayName 'NetworkDirect Technology' -DisplayValue 'RoCEv2' -Confirm:$false
      }
  
  # RDMA QOS setting for Mellanox
      If((Get-NetAdapter $MgmtNics | Select InterfaceDescription) -imatch "Mellanox" -or ((Get-PhysicalDisk | Where-Object{$_.MediaType -imatch 'HDD'}).count -eq 0)){
          # New QoS policy with a match condition set to 445 (TCP Port 445 is dedicated for SMB)
          # Arguments 3 and 5 to the PriorityValue8021Action parameter indicate the IEEE802.1p 
          # values for SMB and cluster traffic.
              New-NetQosPolicy -Name 'SMB' -NetDirectPortMatchCondition 445 -PriorityValue8021Action 3 -Confirm:$false
              New-NetQosPolicy 'Cluster' -Cluster -PriorityValue8021Action 5 -Confirm:$false
          # Map the IEEE 802.1p priority enabled in the system to a traffic class
              New-NetQosTrafficClass -Name 'SMB' -Priority 3 -BandwidthPercentage 50 -Algorithm ETS
              New-NetQosTrafficClass -Name 'Cluster' -Priority 5 -BandwidthPercentage 2 -Algorithm ETS
          # Configure flow control for the priorities shown in the above table
              Enable-NetQosFlowControl -Priority 3
              Disable-NetQosFlowControl -Priority 0,1,2,4,5,6,7
          # Enable QoS for the network adapter ports.
              If((Get-NetAdapter $MgmtNics | Select InterfaceDescription) -imatch "Mellanox"){
                  Get-NetAdapter $MgmtNics | Enable-NetAdapterQos -Confirm:$false
              }
          # Disable DCBX Willing mode
              Set-NetQosDcbxSetting -Willing $false -Confirm:$false
          # Enable IEEE Priority Tag on all network interfaces to ensure the vSwitch does not drop the VLAN tag information.
          $nics  = Get-VMNetworkAdapter -ManagementOS
              ForEach ($nic in $nics) {
                  Set-VMNetworkAdapter -VMNetworkAdapter $nic -IeeePriorityTag ON -Confirm:$false
              }
      }
  
  #Enable RDMA on storage nics
      Disable-NetAdapterRDMA -Name * -Confirm:$false
      Enable-NetAdapterRDMA -Name $MgmtNics -Confirm:$false
  
  #Enable enable RDMA for Live Migration
      Set-VMHost -VirtualMachineMigrationPerformanceOption SMB -Confirm:$false
}   

#Need to add iSCSI configuration here

#Rename Storage NICs
    Rename-NetAdapter -Name $S1Nic -NewName $S1NicName -Confirm:$false
    Rename-NetAdapter -Name $S2Nic -NewName $S2NicName -Confirm:$false

#Windows Defender exclusions for Hyper-V and Clustering
    If ($env:SystemDrive+"\ProgramData\Microsoft\Windows\Hyper-V\Snapshots"){
    Add-MpPreference -ExclusionPath $env:SystemDrive+"\ProgramData\Microsoft\Windows\Hyper-V\Snapshots"}
    Add-MpPreference -ExclusionPath (Get-VMHost).VirtualHardDiskPath
    Add-MpPreference -ExclusionPath (Get-VMHost).VirtualMachinePath
    Add-MpPreference -ExclusionProcess "vmms.exe"
    Add-MpPreference -ExclusionProcess "vmwp.exe"
    Add-MpPreference -ExclusionProcess "vmsp.exe" #Removed OS check
    Add-MpPreference -ExclusionProcess "Vmcompute.exe" #Removed OS check
    Add-MpPreference -ExclusionProcess "clussvc.exe" #Added new for Clustering
    Add-MpPreference -ExclusionProcess "rhs.exe" #Added new for Clustering
    Add-MpPreference -ExclusionProcess "vmwp.exe"
    Add-MpPreference -ExclusionExtension ".vhd"
    Add-MpPreference -ExclusionExtension ".vhdx"
    Add-MpPreference -ExclusionExtension ".avhd"
    Add-MpPreference -ExclusionExtension ".avhdx"
    Add-MpPreference -ExclusionExtension ".vhds"
    Add-MpPreference -ExclusionExtension ".vhdpmem"
    Add-MpPreference -ExclusionExtension ".iso"
    Add-MpPreference -ExclusionExtension ".rct"
    Add-MpPreference -ExclusionExtension ".mrt" #added 
    Add-MpPreference -ExclusionExtension ".vsv"
    Add-MpPreference -ExclusionExtension ".bin"
    Add-MpPreference -ExclusionExtension ".xml" #added 
    Add-MpPreference -ExclusionExtension ".vmcx"
    Add-MpPreference -ExclusionExtension ".vmrs"
    Add-MpPreference -ExclusionExtension ".vmgs" #added
    Add-MpPreference -ExclusionPath "C:\ClusterStorage"
    Add-MpPreference -ExclusionPath "C:\Users\cliusr\Local Settings\Temp" #Added new for Clustering

#Set Spectre Variant 2 to fix Live Migrations for 
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name FeatureSettingsOverride -Value 0 -Verbose -Confirm:$false
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name FeatureSettingsOverrideMask -Value 3 -Verbose -Confirm:$false
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization' -Name MinVmVersionForCpuBasedMitigations -Value '1.0' -Confirm:$false
 
#Update Pagefile settings for memory dump
    #$blockCacheMB = (Get-Cluster).BlockCacheSize
    $blockCacheMB = 1024
    $pageFilePath = "C:\pagefile.sys"
    $initialSize = [Math]::Round(51200 + $blockCacheMB)
    $maximumSize = [Math]::Round(51200 + $blockCacheMB)
    $system = Get-WmiObject -Class Win32_ComputerSystem -EnableAllPrivileges
        if ($system.AutomaticManagedPagefile) { 
            $system.AutomaticManagedPagefile = $false 
            $system.Put()
        }
    $currentPageFile = Get-WmiObject -Class Win32_PageFileSetting
    If($currentPageFile.Name){
        $currentPageFile.Name=$pageFilePath
        $currentPageFile.InitialSize = $InitialSize
        $currentPageFile.MaximumSize = $MaximumSize 
        $currentPageFile.Put()
    }Else{
        Write-Host "Failed to set pagefile. Please set manually. sysdm.cpl" -ForegroundColor Red
    }
