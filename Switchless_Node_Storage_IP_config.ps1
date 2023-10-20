#Configure node IP addresses for switchless
#Version 1.2
  param
 (
 [Parameter(Mandatory = $true)]
 [Int]
 $NodeID
 )
 $SwitchlessNodeID = ${NodeID} #Update to the current Node number being configured.
 $SwitchlessClusterNodes = 4 #Edit with number of nodes in the cluster.
 ##############################################
 #Setup Storage Network for Switchless Topology
 ##############################################
 $StorageSubnet = '172.16.0.0'
 $SingleStorageIPAddress = 
@('172.16.12','172.16.13','172.16.14','172.16.23','172.16.24','172.16.34')
 $DualStorageIPAddress = 
@('172.16.21','172.16.31','172.16.41','172.16.32','172.16.42','172.16.43')
 $StorageAddressPrefix = 29
 $supportedAdapters = @("Mellanox", "QLogic", "E810")
 $StorageAdapter = Get-NetAdapter | Where InterfaceDescription -Match ($supportedAdapters -Join "|") | ? Status -like Up | sort Name | Get-NetAdapterHardwareInfo | ? Slot -GE 1 | Sort-Object Slot,Function
 if ( $StorageAdapter ) {
 Write-Output 'These adapters will be used for storage (dependent on cluster size):'
 Write-Output $($StorageAdapter | Format-Table Name,Description,Slot,Function)
 Pause
 } else {
 throw 'No RDMA Storage Adapters found!'
 }
 $SingleStorageIPAddress = $SingleStorageIPAddress | ForEach-Object { if 
(($_).Substring(($_).Length -2) -match $SwitchlessNodeID) { $_ } }
 $DualStorageIPAddress = $DualStorageIPAddress | ForEach-Object { if 
(($_).Substring(($_).Length -2) -match $SwitchlessNodeID) { $_ } }
 $SingleStorageIPAddress = $SingleStorageIPAddress | ForEach-Object { $_ + '.' + 
$SwitchlessNodeID }
 $DualStorageIPAddress = $DualStorageIPAddress | ForEach-Object { $_ + '.' + 
$SwitchlessNodeID }
 $StorageSubnet = $StorageSubnet.Split('.')[0] + '.' + $StorageSubnet.Split('.')[1]
 $SingleStorageIPAddress = $SingleStorageIPAddress | ForEach-Object { 
$_.Replace('172.16',$StorageSubnet) }
 $DualStorageIPAddress = $DualStorageIPAddress | ForEach-Object { $_.Replace('172.16',
$StorageSubnet) }
 Write-Output "Storage IP Addresses: $(($SingleStorageIPAddress)[0..
($SwitchlessClusterNodes -2)]) ($(($DualStorageIPAddress )[0..($SwitchlessClusterNodes -2)]))"
 Pause
 ##
 #################################
 ## Assign IPs for Storage Network
 #################################
 if ( ($SwitchlessClusterNodes -1) -le $StorageAdapter.Count ) {
 Write-Output 'Configuring Single-Link Full Mesh Switchless Networks'
 for ($i=0;$i -lt ($SwitchlessClusterNodes -1);$i++) {
 Write-Output "Adapter: $(($StorageAdapter)[$i].Description) Name: $(($StorageAdapter)[$i].Name) IP: $($SingleStorageIPAddress[$i])"
 $null = New-NetIPAddress -InterfaceAlias ($StorageAdapter)[$i].Name -IPAddress $SingleStorageIPAddress[$i] -PrefixLength $StorageAddressPrefix -Verbose
 }
 if ( ($SwitchlessClusterNodes -1)*2 -le $StorageAdapter.Count ) {
 Write-Output 'Configuring Dual-Link Full Mesh Switchless Networks'
 $n = $SwitchlessClusterNodes -1
 for ($i=0;$i -lt ($SwitchlessClusterNodes -1);$i++) {
 Write-Output "Adapter: $(($StorageAdapter)[$n].Description) Name: $(($StorageAdapter)[$n].Name) IP: $($DualStorageIPAddress[$i])"
 $null = New-NetIPAddress -InterfaceAlias ($StorageAdapter)[$n].Name -IPAddress $DualStorageIPAddress[$i] -PrefixLength $StorageAddressPrefix -Verbose
 $n++
 }
 }
 } else {
 throw "Not enough Storage NICs available based on cluster size of 
$SwitchlessClusterNodes"
 }
