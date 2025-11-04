#Verify S2D/HCI Switchless connections
#Version 1.2
#by: Jim Gandy
$Nodes="AZHCI02","AZHCI03","AZHCI04"
md c:\dell -Force -ErrorAction SilentlyContinue
Get-NetAdapter -CimSession $Nodes | Export-Clixml "c:\dell\GetNetAdapter.xml" -Force
Get-NetIpAddress -CimSession $Nodes | Export-Clixml "c:\dell\GetNetIpAddress.xml" -Force
Get-NetNeighbor -CimSession $Nodes | Export-Clixml "c:\dell\GetNetNeighbor.xml" -Force
Get-NetAdapterAdvancedProperty -CimSession $Nodes | Export-Clixml "c:\dell\GetNetAdapterAdvancedProperty.xml" -Force

$SDDCPath = "c:\dell"
$GetNetAdapter=Get-ChildItem -Path $SDDCPath -Filter GetNetadapter.xml -Recurse -Depth 2 | Import-Clixml | Where-Object{($_.InterfaceDescription -imatch "QLogic") -or ($_.InterfaceDescription -imatch "Mellanox") -or ($_.InterfaceDescription -imatch "NVidia") -or ($_.InterfaceDescription -imatch "E810")} 
$GetIPAddress=Get-ChildItem -Path $SDDCPath -Filter GetNetIpAddress.xml -Recurse -Depth 2 | Import-Clixml 
$GetNetNeighbor=Get-ChildItem -Path $SDDCPath -Filter GetNetNeighbor.xml -Recurse -Depth 2 | Import-Clixml 
$GetNetAdapterAdvancedProperty=Get-ChildItem -Path $SDDCPath -Filter GetNetAdapterAdvancedProperty.xml -Recurse -Depth 2 | Import-Clixml | Where-Object{($_.InterfaceDescription -imatch "QLogic") -or ($_.InterfaceDescription -imatch "Mellanox") -or ($_.InterfaceDescription -imatch "NVidia") -or ($_.InterfaceDescription -imatch "E810")} 

    $Table=@()
    foreach($Neighbor in $GetNetNeighbor){
        foreach($Adapter in $GetNetAdapter){
            IF($Neighbor.LinkLayerAddress -eq $Adapter.MacAddress){
                $Table  += [PSCustomObject]@{
				    LocalName 		= $Adapter.Name
                    LocalMask = (($GetIPAddress | ?{($_.PSComputerName -eq $Adapter.PSComputerName) -and ($_.ifIndex -eq $Adapter.ifIndex) -and ($_.AddressFamily -eq "2")}).PrefixLength | sort -Unique)
                    LocalMac =$Adapter.MacAddress
                    LocalIP = (($GetIPAddress | ?{($_.PSComputerName -eq $Adapter.PSComputerName) -and ($_.ifIndex -eq $Adapter.ifIndex) -and ($_.AddressFamily -eq "2")}).IPAddress | sort -Unique)
                    LocalvLAN = (($GetNetAdapterAdvancedProperty | ?{($_.PSComputerName -eq $Adapter.PSComputerName) -and ($_.Name -eq $Adapter.Name)}) | ?{$_.DisplayName -imatch 'vlan id'}).DisplayValue
                    Local = $Adapter.PSComputerName
                    Remote = $Neighbor.PSComputerName
                    RemotevLAN = (($GetNetAdapterAdvancedProperty | ?{($_.PSComputerName -eq $Adapter.PSComputerName) -and ($_.Name -eq $Adapter.Name)}) | ?{$_.DisplayName -imatch 'vlan id'}).DisplayValue
                    RemoteIP = (($GetIPAddress | ?{($_.PSComputerName -eq $Neighbor.PSComputerName) -and ($_.ifIndex -eq $Neighbor.ifIndex) -and ($_.AddressFamily -eq "2")}).IPAddress | sort -Unique)
                    RemoteMac = (($GetNetAdapter | ?{($_.PSComputerName -eq $Neighbor.PSComputerName) -and ($_.ifIndex -eq $Neighbor.ifIndex)}).MacAddress)
                    RemoteMask = (($GetIPAddress | ?{($_.PSComputerName -eq $Neighbor.PSComputerName) -and ($_.ifIndex -eq $Neighbor.ifIndex) -and ($_.AddressFamily -eq "2")}).PrefixLength | sort -Unique)
                    RemoteName = $Neighbor.InterfaceAlias
                
			    }
            }
        }
    }
$StorageN2NMapOut=$Table | Sort-Object LocalMac -Unique | Sort-Object Local,remote 
$StorageN2NMapOut | FT