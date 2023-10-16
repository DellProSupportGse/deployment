#Configure HCI Cluster

#Variables
    #Change this to "Full" for Fully-Converged networking
        $FullyNone="None"

    #Managment Nics
        $MgmtNic1 = "Integrated NIC 1 Port 1-1"	
        $MgmtNic2 = "Integrated NIC 1 Port 2-1"
        $mgmt_compute_nics = @("$MgmtNic1","$MgmtNic2")
        $MgmtVlan=0
    
    #Storage Nics    
        $S1Nic="SLOT 2 Port 1"
        $S2Nic="SLOT 2 Port 2"
        $storage_nics=@("$S1Nic","$S2Nic")
        $S1vlan="700"
        $storage_vlans=@("$S1vlan")

    #Cluster Info
        $ClusterName="AzHCICluster"
        $ClusterIP="100.72.4.124"
        $ClusterNodes='AzHCI02','AzHCI03','AzHCI04'

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#    This section below is for creating and configuring the cluster
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    # Check if cluster exisits
    IF(-not(Get-Cluster -ErrorAction SilentlyContinue)){
        #Test cluster nodes before creating the cluster
            Test-Cluster -Node $ClusterNodes -Include 'Storage Spaces Direct', 'Inventory', 'Network', 'System Configuration'
            #NOTE: Make sure all errors are resolved before proceeding
            Pause
            
        #Create cluster
            New-Cluster -Name $ClusterName -Node $ClusterNodes -StaticAddress $ClusterIP
    }
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Setup NetworkATC on the Cluster
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    # Setup QOS Overrides Intnet
        $QoSOverride = New-NetIntentQoSPolicyOverrides
        $QoSOverride.BandwidthPercentage_Cluster = 2
        $QoSOverride.PriorityValue8021Action_Cluster = 5

    # RDMA/JumboPacket Override for SMB & Management NIC
        $MgmtAdapterPropertyOverrides = New-NetIntentAdapterPropertyOverrides
        $MgmtAdapterPropertyOverrides.NetworkDirect = 0
        $MgmtAdapterPropertyOverrides.JumboPacket = 1514
        $StorAdapterPropertyOverrides = New-NetIntentAdapterPropertyOverrides
        $StorAdapterPropertyOverrides.JumboPacket = 9014
        If ((Get-NetAdapter -Name $storage_nics[0] | Select InterfaceDescription) -inotMatch "Mellanox") { 
            $StorAdapterPropertyOverrides.NetworkDirectTechnology = 1 
            } else {$StorAdapterPropertyOverrides.NetworkDirectTechnology = 4 }
 
    # Storage Overrides if you do not want Network ATC to assign SMB IPs automatically.
        $StorageOverride = New-NetIntentStorageOverrides
        $StorageOverride.EnableAutomaticIPGeneration = $false

    # Create Management and Compute Intent
        IF(Get-AllNetIntents | ?{$_.keys.value -inotmatch "management_compute"}){
        Add-NetIntent -Name Management_Compute -Management -Compute -AdapterName $mgmt_compute_nics -ManagementVlan $MgmtVlan -AdapterPropertyOverrides $MgmtAdapterPropertyOverrides}

    # Create Storage Intent
        IF(Get-AllNetIntents | ?{$_.keys.value -inotmatch "Storage"}){
        add-NetIntent -Name Storage -Storage -AdapterName $storage_nics -StorageVLANs $storage_vlans -QosPolicyOverrides $QoSOverride -AdapterPropertyOverrides $StorAdapterPropertyOverrides -StorageOverrides $Storageoverride}


    # Setup the Cluster Overrides
        $clusterOverride = New-NetIntentGlobalClusterOverrides
        $clusterOverride.EnableVirtualMachineMigrationPerformanceSelection = $false
        $clusterOverride.VirtualMachineMigrationPerformanceOption = "SMB"
        $clusterOverride.MaximumVirtualMachineMigrations = 2

    # Create Cluster Intent
        IF(Get-AllNetIntents -GlobalOverrides | Select-Object -ExpandProperty ClusterOverride | Select-Object VirtualMachineMigrationPerformanceOption){
        Set-NetIntent -GlobalClusterOverrides $clusterOverride}



#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Setup Storage Spaces Direct (S2D)
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IF($FullyNone -imatch "None"){
        IF((Get-ClusterS2D).State){
            #Enable S2d
                Enable-Clusters2d            
        }
    }