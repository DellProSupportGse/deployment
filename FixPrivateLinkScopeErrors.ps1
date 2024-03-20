<#.Synopsis
   Fix PrivateLinkScopeErrors
.DESCRIPTION
    Script will check the azcmagent.log for PrivateLinkScopeErrors and add the resolved hostnames to the local hosts file.
.CREATEDBY
    Jim Gandy
    Tommy Paulk
.NOTES
#>
Clear-Host
Write-Host "Checking for PrivateLinkScopeErrors..."
$LogPath="C:\programdata\AzureConnectedMachineAgent\Log\azcmagent.log"
$FailingHostname = Get-Content $LogPath | Select-String -Pattern 'PrivateLinkScopeErrors' | ForEach-Object { if ($_ -match '(\S+\.azure\.com)') { $matches[1] } } | sort -Unique
IF($FailingHostname){
    Write-Host "FOUND: PrivateLinkScopeErrors"
    $FailingHostname | %{Write-Host "    $_"}
    $hostnameToIps=@()
    foreach ($hostname in $FailingHostname){
        Write-Host "DNS Lookup $hostname with 8.8.8.8..."
      $dip=(Resolve-DnsName $hostname -Type A -Server 8.8.8.8 -ErrorAction SilentlyContinue).IPAddress
      if (!$dip) {
        Write-Host "    No Response from 8.8.8.8 Trying SimpleDNS.plus/lookup"
        Try{
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $response=Invoke-WebRequest 'https://simpledns.plus/lookup' -Method Default -SessionVariable rb # -Method Post -Body $formFields -ContentType "application/x-www-form-urlencoded"
        $form=$response.forms[0]
        $form.Fields["domain"]=$hostname
        $form.Fields["server"]='8.8.8.8' 
        $form.Fields["recType"]='A'
        $dip=Invoke-WebRequest -Uri ('https://simpledns.plus/lookup') -Body $form -Method POST -WebSession $rb -Headers @{'Content-Type' = 'application/x-www-form-urlencoded'}
        $dip= [Regex]::Matches($dip.Content.split("\n"),".*?((\d*\.){3}\d)")[1].groups[1].value}
        Finally{
            if (!$dip) {
                Write-Host "        ERROR: Failed to resolve $hostname" -ForegroundColor Red
            }Else{
                Write-Host "        SUCCESS: $dip`t$hostname" -ForegroundColor Green      
            }
        }
      }Else{
      Write-Host "    SUCCESS: $dip`t$hostname" -ForegroundColor Green 
      }
      if ($dip) {
        $hostnameToIps+="$dip`t$hostname"
      }
    }
    $hostnamesfile=Get-Content -Path "C:\Windows\System32\drivers\etc\hosts"
    if (!($hostnamesfile -match $hostname)){
        Try{
            Write-Host "Adding the following to C:\Windows\System32\drivers\etc\hosts"
            $hostnameToIps
            $Run = Read-Host "Append? [y/n]"
            If ($run -ine "y"){Break}
            $hostnameToIps | Out-File -FilePath "C:\Windows\System32\drivers\etc\hosts" -Append
        }
        Catch{
            $errout=$Error[0]
            Write-Host "    ERROR: $errout" -ForegroundColor Red
            Write-Host "           Copy/Paste manually or RunAs Administrator" -ForegroundColor Red
            }
    }
}Else{
    Write-Host "No PrivateLinkScopeErrors"
}
