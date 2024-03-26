#Configure Switchless
#Version 1.5

#Varables
    
    #Managment Nics
        $MgmtNic1 = "Integrated NIC 1 Port 1-1"	
        $MgmtNic2 = "Integrated NIC 1 Port 2-1"
        $MgmtNicIp="192.168.4.125"
        $MGMTNICGW="192.168.4.1"
        $DNSIps="192.168.200.10,192.168.200.11"
        $VMSwitchName="Mgmt_vSwitch"
        $MgmtNicName="Management"
        $MgmtPrefixLength="24"
        $Mgmtvlan=""
    
    #Storage Nics
        $S1Nic="SLOT 2 Port 1"
        $S2Nic="SLOT 2 Port 2"
        $S1NicName="Storage1"
        $S2NicName="Storage2"
    
Function EndScript{  
    break
}

#Install Roles
    Try{
        $InstRoles=Install-WindowsFeature -Name Hyper-V,Failover-Clustering,Data-Center-Bridging,BitLocker -IncludeManagementTools -IncludeAllSubFeature -Confirm:$false
    }
    Catch{
        Write-Host "ERROR: Please versify why roles failed to install."
        Write-Host $InstRoles
        EndScript
    }
    IF($InstRoles | Where-Object{$_.ExitCode -imatch "restart"}){
        Write-Host "Restart needed from role installation."
        $Restart = Read-Host "Ready to restart? [y/n/q]"
        until ($Restart -match '[yY,nN,qQ]')
        IF($Restart -inotmatch 'y'){EndScript}
        IF($Restart -imatch 'y'){Restart-Computer}
    }

#Creates the Virtual Switch 
    New-VMSwitch -Name $VMSwitchName -AllowManagementOS 0 -NetAdapterName $MgmtNic1 ,$MgmtNic2 -MinimumBandwidthMode Weight -Verbose -Confirm:$false
    #Added to resolve the posibility of MAC address conflicts with the Host NICs
    $RMAC=((1..4)|%{"abcdef0123456789".ToCharArray() | Get-Random}) -join ''
    $RMACMin="00155D"+$RMAC+"00"
    $RMACMax="00155D"+$RMAC+"FF"
    Set-VMHost -MacAddressMinimum ($RMACMin) -MacAddressMaximum  ($RMACMax) -Confirm:$false

#Creates the Virtual Network Cards with random MAC addresses to prevent conflicts
    $RMAC=((1..6)|%{"abcdef0123456789".ToCharArray() | Get-Random}) -join ''
    $RMAC="00155D"+$RMAC
    Add-VMNetworkAdapter -ManagementOS -name $MgmtNicName -SwitchName $VMSwitchName –StaticMacAddress $RMAC -Confirm:$false
    
#Sets each vNIC with it own vLAN ID
   IF($Mgmtvlan -ne ""){Set-VMNetworkAdapterVlan -VMNetworkAdapter $MgmtNicName -Access -VlanId $Mgmtvlan -Confirm:$false}

#Configures IP addresses for the vNICs
    Get-NetAdapter "vEthernet ($MgmtNicName)" | New-NetIPAddress -IPAddress $MgmtNicIp  -PrefixLength $MgmtPrefixLength -DefaultGateway $MGMTNICGW -Confirm:$false

    #Set DNS -comma delimit 2nd DNS Server
    Get-NetAdapter "vEthernet ($MgmtNicName)" | Set-DnsClientServerAddress -ServerAddress $DNSIps -Confirm:$false

#Disable DCB on Intel Nics
    Get-NetAdapter -InterfaceDescription *Intel* | Disable-NetAdapterQos -Confirm:$false

#Max Rx and Tx queues should be max values
    If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "QLogic"){
        Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Receive Buffers*" -DisplayValue 35000 -Confirm:$false
        Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Transmit Buffers*" -DisplayValue 5000 -Confirm:$false
    }
    If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "Mellanox"){
        Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Receive Buffers*" -DisplayValue 4096 -Confirm:$false
        Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Send Buffers*" -DisplayValue 2048 -Confirm:$false
    }
    
#Enable Jumbo Frames
    Set-NetAdapterAdvancedProperty -Name $S1Nic,$S2Nic -DisplayName "Jumbo Packet" -DisplayValue "9014" -Confirm:$false
    
#Set RDMA
    If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "QLogic"){
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
    If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "Mellanox" -or ((Get-PhysicalDisk | Where-Object{$_.MediaType -inotmatch 'HDD'}).count -eq 0)){
        # New QoS policy with a match condition set to 445 (TCP Port 445 is dedicated for SMB)
        # Arguments 3 and 5 to the PriorityValue8021Action parameter indicate the IEEE802.1p 
        # values for SMB and cluster traffic.
            New-NetQosPolicy -Name 'SMB' –NetDirectPortMatchCondition 445 –PriorityValue8021Action 3 -Confirm:$false
            New-NetQosPolicy 'Cluster' -Cluster -PriorityValue8021Action 5 -Confirm:$false
        # Map the IEEE 802.1p priority enabled in the system to a traffic class
            New-NetQosTrafficClass -Name 'SMB' –Priority 3 –BandwidthPercentage 50 –Algorithm ETS
            New-NetQosTrafficClass -Name 'Cluster' –Priority 5 –BandwidthPercentage 2 –Algorithm ETS
        # Configure flow control for the priorities shown in the above table
            Enable-NetQosFlowControl –Priority 3
            Disable-NetQosFlowControl –Priority 0,1,2,4,5,6,7
        # Enable QoS for the network adapter ports.
            If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "Mellanox"){
                Get-NetAdapter $S1Nic,$S2Nic | Enable-NetAdapterQos -Confirm:$false
            }
        # Disable DCBX Willing mode
            Set-NetQosDcbxSetting -Willing $false -Confirm:$false
        # Enable IEEE Priority Tag on all network interfaces to ensure the vSwitch does not drop the VLAN tag information.
    	    $nics  = Get-VMNetworkAdapter -ManagementOS
            ForEach ($nic in $nics) {
                Set-VMNetworkAdapter -VMNetworkAdapter $nic -IeeePriorityTag ON -Confirm:$false
            }
    }

#Enable RDMA
    Enable-NetAdapterRDMA -Name $S1Nic, $S2Nic -Confirm:$false
    
#Rename Storage NICs
    Rename-NetAdapter -Name $S1Nic -NewName $S1NicName -Confirm:$false
    Rename-NetAdapter -Name $S2Nic -NewName $S2NicName -Confirm:$false

#Enable enable RDMA for Live Migration
    Set-VMHost –VirtualMachineMigrationPerformanceOption SMB -Confirm:$false

#Windows Defender exclusions for Hyper-V
    $WinVer=(Get-WmiObject -class Win32_OperatingSystem).Caption
    If ($env:SystemDrive+"\ProgramData\Microsoft\Windows\Hyper-V\Snapshots"){
    Add-MpPreference -ExclusionPath $env:SystemDrive+"\ProgramData\Microsoft\Windows\Hyper-V\Snapshots"}
    Add-MpPreference -ExclusionPath (Get-VMHost).VirtualHardDiskPath
    Add-MpPreference -ExclusionPath (Get-VMHost).VirtualMachinePath
    Add-MpPreference -ExclusionProcess "vmms.exe"
    Add-MpPreference -ExclusionProcess "vmwp.exe"
    If($WinVer -imatch 2016){Add-MpPreference -ExclusionProcess "vmsp.exe"} #2016 only
    If($WinVer -imatch 2019){Add-MpPreference -ExclusionProcess "Vmcompute.exe"} #2019 only
    Add-MpPreference -ExclusionExtension ".vhd"
    Add-MpPreference -ExclusionExtension ".vhdx"
    Add-MpPreference -ExclusionExtension ".avhd"
    Add-MpPreference -ExclusionExtension ".avhdx"
    Add-MpPreference -ExclusionExtension ".vhds"
    Add-MpPreference -ExclusionExtension ".vhdpmem"
    Add-MpPreference -ExclusionExtension ".iso"
    Add-MpPreference -ExclusionExtension ".rct"
    Add-MpPreference -ExclusionExtension ".vsv"
    Add-MpPreference -ExclusionExtension ".bin"
    Add-MpPreference -ExclusionExtension ".vmcx"
    Add-MpPreference -ExclusionExtension ".vmrs"
    Add-MpPreference -ExclusionPath "C:\ClusterStorage"

#Set Spaces Port hardware timeout
        Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\spacePort\Parameters -Name HwTimeout -Value 0x00002710 -Verbose -Confirm:$false
 
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

