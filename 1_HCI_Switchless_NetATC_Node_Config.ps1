#Configure Non-Converged Switchless with Network ATC
#Version v1.1.1
#Varables
    $NodeName="AzHCI1"
        
    #Managment Nics
        $MgmtNic1 = "Integrated NIC 1 Port 1-1"	
        $MgmtNic2 = "Integrated NIC 1 Port 2-1"
        $MgmtNicIp="192.168.4.125"
        $MGMTNICGW="192.168.4.1"
        $DNSIps="192.168.200.10,192.168.200.11"
        $MgmtPrefixLength="24"
        $Mgmtvlan=""

    #Storage Nics
        $S1Nic="SLOT 2 Port 1"
        $S2Nic="SLOT 2 Port 2"

#Disabled DHCP on Mgmt ports
    Set-NetIPInterface -InterfaceAlias $MgmtNic1,$MgmtNic12 -Dhcp Disabled

#Sets vLAN ID for Mgmt
   IF($Mgmtvlan -ne ""){Set-NetAdapter -InterfaceAlias $MgmtNic1 -VlanId $Mgmtvlan -Confirm:$false}

#Configures IP addresses for the NICs
    New-NetIPAddress -InterfaceAlias $MgmtNic1 -IPAddress $MgmtNicIp  -PrefixLength $MgmtPrefixLength -DefaultGateway $MGMTNICGW -Confirm:$false

    #Set DNS -comma delimit 2nd DNS Server
    Set-DnsClientServerAddress -InterfaceAlias $MgmtNic1 -ServerAddresses $DNSIps -Confirm:$false

#Enable Remote Desktop
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

#Rename node
    IF(($env:COMPUTERNAME) -inotmatch $NodeName){Rename-Computer -NewName $NodeName -Confirm:$False}

#Install Roles
    Install-WindowsFeature -Name Hyper-V, NetworkATC, FS-SMBBW, Failover-Clustering, Data-Center-Bridging, BitLocker, FS-FileServer, RSAT-Clustering-PowerShell -IncludeAllSubFeature -IncludeManagementTools -Confirm:$false
 
#Disable DCB on Intel Nics
    Get-NetAdapter -InterfaceDescription *X710* | Disable-NetAdapterQos -Confirm:$false

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
        Get-NetAdapter $S1Nic,$S2Nic | Set-NetAdapterAdvancedProperty -DisplayName "Send Buffers*" -DisplayValue 4096 -Confirm:$false
    }    

# Exclude iDRAC NIC from Cluster
    $NDISDesc=(Get-NetAdapter | Where-Object{$_.InterfaceDescription -imatch "NDIS"}).InterfaceDescription
    New-Item -Path HKLM:\system\currentcontrolset\services\clussvc\parameters -Force
    New-ItemProperty -Path HKLM:\system\currentcontrolset\services\clussvc\parameters -Name ExcludeAdaptersByDescription -Value $NDISDesc -Force
    
#Set DcbxMode
    If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "Mellanox"){
        Set-NetAdapterAdvancedProperty -Name $S1Nic -DisplayName 'DcbxMode' -DisplayValue 'Host In Charge' -Confirm:$false
        Set-NetAdapterAdvancedProperty -Name $S2Nic -DisplayName 'DcbxMode' -DisplayValue 'Host In Charge' -Confirm:$false
    }

# Disable DCBX Willing mode
    Set-NetQosDcbxSetting -Willing $false -Confirm:$false

# RDMA QOS setting for Mellanox
    If((Get-NetAdapter $S1Nic,$S2Nic | Select InterfaceDescription) -imatch "Mellanox" -or ((Get-PhysicalDisk | Where-Object{$_.MediaType -imatch 'HDD'}).count -eq 0)){
        # Enable IEEE Priority Tag on all network interfaces to ensure the vSwitch does not drop the VLAN tag information.
    	    $nics  = Get-VMNetworkAdapter -ManagementOS
            ForEach ($nic in $nics) {
                Set-VMNetworkAdapter -VMNetworkAdapter $nic -IeeePriorityTag ON -Confirm:$false
            }
    }

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

