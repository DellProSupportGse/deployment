#Configure HCI Cluster

#Varables
    
    #Managment Nics
        $MgmtNic1 = "Integrated NIC 1 Port 1-1"	
        $MgmtNic2 = "Integrated NIC 1 Port 2-1"
    
    #Storage Nics
        $S1Nic="Storage1"
        $S2Nic="Storage2"
            
    #Cluster Info
        $ClusterName="AzHCICluster"
        $ClusterIP="100.72.4.124"
        $ClusterNodes='AzHCI1','AzHCI2','AzHCI3','AzHCI4'

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#    This section below is for creating and configuring the cluster
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#Test cluster nodes before creating the cluster
    Test-Cluster -Node $ClusterNodes -Include 'Storage Spaces Direct', 'Inventory', 'Network', 'System Configuration'
    #NOTE: Make sure all errors are resolved before proceeding
            
#Create cluster
    New-Cluster -Name $ClusterName -Node $ClusterNodes -StaticAddress $ClusterIP

#Enable S2d
    Enable-Clusters2d            

#Rename cluster networks and set live migration
    IF((Get-Service clussvc -ErrorAction SilentlyContinue).Status -eq "Running"){
        # Change Cluster Network Names
			IF(-not(Get-ClusterNetwork -Name $MgmtNicName -ErrorAction SilentlyContinue)){
                (Get-ClusterNetwork | Where-Object {$_.Address -imatch (($MgmtNicIp.split('.'))[0,1,2] -join '.')}).Name = $MgmtNicName}
			IF(-not(Get-ClusterNetwork -Name $S1NicName -ErrorAction SilentlyContinue)){
                (Get-ClusterNetwork | Where-Object { $_.Address -imatch (($S1NicIp.split('.'))[0,1,2] -join '.')}).Name = $S1NicName}
			IF(-not(Get-ClusterNetwork -Name $S2NicName -ErrorAction SilentlyContinue)){
                (Get-ClusterNetwork | Where-Object { $_.Address -imatch (($S2NicIp.split('.'))[0,1,2] -join '.')}).Name = $S2NicName}
			IF(-not(Get-ClusterNetwork -Name NDIS -ErrorAction SilentlyContinue)){
                (Get-ClusterNetwork | Where-Object { $_.Address -eq ""}).Name = "NDIS"}
			IF(-not(Get-ClusterNetwork -Name NDIS -ErrorAction SilentlyContinue)){
                (Get-ClusterNetwork | Where-Object { $_.Address -eq ""}).Role = 0}
        # Build MigrationExcludeNetworks list
            $ExcludeManagement = [String]::Join(';',
			@(
			(Get-ClusterNetwork | ?{$_.Name -imatch 'NDIS'}).Id))
        # Build MigrationNetworkOrder list
            $LiveMigrationNetworks = [String]::Join(';', 
            @(
            (Get-ClusterNetwork -Name $S1NicName).Id, 
            (Get-ClusterNetwork -Name $S2NicName).Id,
            (Get-ClusterNetwork $MgmtNicName).Id))
        # Configure the Live Migration Networks to use Storage NICs
            Set-ClusterParameter -InputObject (Get-ClusterResourceType -Name 'Virtual Machine') -Name MigrationExcludeNetworks -Value $ExcludeManagement
            Set-ClusterParameter -InputObject (Get-ClusterResourceType -Name 'Virtual Machine') -Name MigrationNetworkOrder -Value $LiveMigrationNetworks
    }
