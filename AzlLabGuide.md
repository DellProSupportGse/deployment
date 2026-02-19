**Azure Local Lab Guide**
==========================

**Environment**
---------------

* Domain: azurelocal.training
* DC and DNS: dc.azurelocal.training
* IP Address: 100.72.44.200
* User: azurelocal\student#
* Password: P@ssw0rd
* WorkStation Student1 -> student 6: 100.72.44.210-215
* OS: Dell Gold Image on Azure Stack HCI 12.2510 + SBE 2512
* iDrac login:
	+ User: training
	+ Password: D3llP@ssw0rd!

**Lab 1: Prerequisites**
-------------------------

### Lab 1-B: Azure

1. RDP to the student workstation.
2. Launch Edge and set up your Dell.com profile.
3. Enter your Dell account with firstname.lastname@dell.com, and sign in to create the profile.
4. Verify your profile under the profile section.
5. Go to portal.azure.com. You may receive a screen stating that the device does not meet compliance requirements.
6. This is expected behavior. Click on "Sign out and Sign in with a different account" and choose "Use Another Account".
7. Use firstname_lastname@dell.com to sign in, and it will prompt you to log in again.
8. Enter your email address with the underscore and password, and click on OK.
9. You may be prompted to use an authenticator or text message a few times, but it should finally log in to the Azure portal with access to the Dell multicloud subscription.

### Lab 1-B: Create Azure Resource Group

1. Go to portal.azure.com and log in to the Multicloud subscription.
2. Search for "Resource Group" from the search bar on top and click on "Resource groups".
3. Click on "+Create".
4. Enter your resource group name and click on "Review + Create".
5. Wait until it completes successfully.

### Lab 1-C: Prepare AD

In this exercise, we will use AD Users and Computers to create a new OU in the Azurelocal.training domain.

1. From your workstation, type dsa.msc and launch the AD Users and Computers console.
2. Click on "View" and make sure "Advanced Features" is selected.
3. Right-click on the OU "Azure Local", click on "New", and select "Organizational Unit".
4. Create a new OU for your Azure Local installation.
5. Right-click on the OU for your Azure Local installation, go to properties, and click on the "Attribute Editor" tab.
6. Click on "distinguishedName" and click on "View". Press Ctrl+C to copy the distinguishedName for the OU.
7. Close the AD Users and Computers window.
8. Launch the Terminal window by right-clicking on the start button and choosing "Terminal (Admin)".
9. We will create the LCM (LifeCycle Management) User for the Azure Local instance.
10. Copy and paste the following commands into the terminal and run them:
```powershell
cd "c:\program Files\WindowsPowerShell\Modules\AsHciADArtifactsPreCreationTool\10.2402"
Import-Module .\AsHciADArtifactsPreCreationTool.psd1
$User = "lcmusername"
$AdPasswd = ConvertTo-SecureString "D3llP@ssw0rd123!" -AsPlainText -Force
$AdCred = New-Object System.Management.Automation.PSCredential ($User, $AdPasswd)
Replace the AsHciOUName with the distinguishedName you copied earlier.
New-HciAdObjectsPreCreation -AzureStackLCMUserCredential ($AdCred) -AsHciOUName "OU=azurelocalOU,OU=Azure Local,DC=azurelocal,DC=training"
```

**Lab 2: Prepare the Node with iDrac**
--------------------------------------

1. RDP to the student workstation and launch Edge.
2. Enter the IP Address of the assigned iDrac and log in with "training" and "D3llP@ssw0rd!".
3. Click on the "Virtual Console" to launch the virtual console.
4. Click on "Console Controls" and "Ctrl-alt-Del" to log in.
5. The default user is the local administrator. Enter the password: D3llP@ssw0rd123! (password must be at least 14 characters).
6. Enter 15 to exit SConfig.

### Lab 2-A: Configuring the Host

In this exercise, you will use PowerShell to configure networking, NTP, WinRM, and the computer name. See the deployment guide for reference: Predeployment configuration | Azure Portal Deployment and Operations Guide with Scalable Networking | Dell Technologies Info Hub.

Use iDrac's console's Virtual Clipboard to copy and paste each PowerShell command to the server.

```powershell
Get-NetAdapter | ? InterfaceDescription -inotmatch "NDIS" | Set-NetIPInterface -Dhcp Disabled
Get-NetAdapter | Where-Object {$_.status -eq "disconnected"} | Disable-NetAdapter
Type Y to continue
```

Find the network interface name:

```powershell
Get-NetAdapter
```

List all the network adapters available for the lab. Find the adapter that is Port 1 of the dual port 25GB adapter.

```powershell
New-NetIPAddress -InterfaceAlias "interfacename" -IPAddress nodeipaddress -DefaultGateway 100.72.4.1 -PrefixLength 23 -AddressFamily IPv4 -Verbose
Set-DnsClientServerAddress -InterfaceAlias "interfacename" -ServerAddresses 100.72.44.200
```

Enable Remote Desktop:

```powershell
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

Configure time source using DNS IP address:

```powershell
w32tm /config /manualpeerlist:"100.72.44.200" /syncfromflags:manual /update
```

Check time source:

```powershell
w32tm /query /status
```

Configure WinRM:

```powershell
winrm quickconfig
```

Enable ICMP firewall rule:

```powershell
netsh advfirewall firewall add rule name="ICMP Allow incoming V4 echo request" protocol=icmpv4:8,any dir=in action=allow
```

Change Node01 to the name you used previously:

```powershell
Rename-Computer -NewName Node01 -Restart
```

**Lab 2-B: Register the Host to Azure Arc**
-----------------------------------------

In this exercise, you will register the Host to Azure Arc without Proxy and Arc Gateway. Register Azure Local with Azure Arc. - Azure Local | Microsoft Learn.

You can now use RDP to perform the steps below.

RDP to the Azure Local Host and log in with the local administrator.

Username: administrator
Password: D3llP@ssw0rd123!

Enter 15 to exit SConfig.

Copy and paste the following commands:

```powershell
$Subscription = "62986796-c210-4289-a117-303bce7bc77f"
$Tenant = "0081ba70-31da-4d1a-a73c-b56477ccc937"
$RG = "ResourceGroupName"
$Region = "eastus"
Invoke-AzStackHciArcInitialization -TenantID $Tenant -SubscriptionID $Subscription -ResourceGroup $RG -Region $Region -Cloud "AzureCloud" -TargetSolutionVersion "12.2512.1002.16"
```

The Arc registration process will update the OS to the latest version. We want to force the update to the previous version, so we can do the Solution update lab later in the class.

You will have to run the same "Invoke-AzStackHciArcInitialization" command again to complete the registration.

```powershell
$Subscription = "62986796-c210-4289-a117-303bce7bc77f"
$Tenant = "0081ba70-31da-4d1a-a73c-b56477ccc937"
$RG = "EnterYourResourceGroupName"
$Region = "eastus"
Invoke-AzStackHciArcInitialization -TenantID $Tenant -SubscriptionID $Subscription -ResourceGroup $RG -Region $Region -Cloud "AzureCloud" -TargetSolutionVersion "12.2512.1002.16"
```

Open another tab on the Edge browser with your Dell.com profile. When DeviceID authentication information shows up, follow the instructions to complete the DeviceID authentication.

Once the registration is complete, the machine (node) should show up in the Resource group.

**Lab 3 – Deploying Azure Local from Azure Portal**
---------------------------------------------------

In this exercise, we will follow Dell's official deployment guide to deploy a single node Azure Local instance.

Dell AX System for Azure Local Azure Portal-based Deployment and Operations Guide with Scalable Networking | Dell US.

Note: Additional screenshot placeholders have been removed for brevity. Please insert the relevant screenshots as needed.
