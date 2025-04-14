# Register machines with Azure Arc
# Define the subscription where you want to register your machine as Arc device
    $Subscription = "YourSubscriptionID"

# Define the resource group where you want to register your machine as Arc device
    $RG = "YourResourceGroupName"

# Define the region to use to register your server as Arc device
# Do not use spaces or capital letters when defining region
  $Region = "eastus"

# Define the tenant you will use to register your machine as Arc device
    $Tenant = "YourTenantID"

# Define the proxy address if your Azure Local deployment accesses the internet via proxy
    $ProxyServer = "http://proxyaddress:port"

#  Connect to your Azure account and Subscription
    Connect-AzAccount -SubscriptionId $Subscription -TenantId $Tenant -DeviceCode

# Get the Access Token for the registration
    $ARMtoken = (Get-AzAccessToken -WarningAction SilentlyContinue).Token

# Get the Account ID for the registration
    $id = (Get-AzContext).Account.Id   

#  Invoke the registration script. Use a supported region.
    Invoke-AzStackHciArcInitialization -SubscriptionID $Subscription -ResourceGroup $RG -TenantID $Tenant -Region $Region -Cloud "AzureCloud" -ArmAccessToken $ARMtoken -AccountID $id -Proxy $ProxyServer

#Ref: https://learn.microsoft.com/en-us/azure/azure-local/deploy/deployment-arc-register-server-permissions?view=azloc-24112&tabs=powershell#register-machines-with-azure-arc


