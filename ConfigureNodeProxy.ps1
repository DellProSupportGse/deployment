# This configuration is used to set up the proxy across all locations on a Windows server to ensure the proxy functions properly.
# Version 1.1
# By: Jim Gandy

 # Proxy variables
		Clear-Host
		$ProxyServer=Read-Host "Please enter the Proxy Sever: example: http://myproxyserver.com:8080" 
		$noproxylist=Read-Host "Please enter the Proxy By-Pass List: example: localhost,127.0.0.1,*.DomainShortName.com,*.DomainFQDN.com,wacserver,nodeshort,nodefqdn,nodeipaddress,idracIPs,iSMiDRACIPs,infrastructureIps,ClusterShortName,ClusterFQDN"

	Write-Host "    Environment variables..."
	Try	{
		[Environment]::SetEnvironmentVariable("HTTPS_PROXY",$ProxyServer , "Machine")
		$env:HTTPS_PROXY = [System.Environment]::GetEnvironmentVariable("HTTPS_PROXY", "Machine")
		[Environment]::SetEnvironmentVariable("HTTP_PROXY",$ProxyServer, "Machine")
		$env:HTTP_PROXY = [System.Environment]::GetEnvironmentVariable("HTTP_PROXY", "Machine")
		#ProxyBypass MUST use comma , delimiter
		[Environment]::SetEnvironmentVariable("NO_PROXY", $noproxylist, "Machine")
		$env:NO_PROXY = [System.Environment]::GetEnvironmentVariable("NO_PROXY", "Machine")
	}Catch{
		Write-Host "    ERROR: Failed to set Environment variables" -ForegroundColor Red
	}

	Try	{
		Write-Host "    Configure Powershell Global Proxy..."
		# Set the global default proxy
		[System.Net.WebRequest]::DefaultWebProxy = (New-Object System.Net.WebProxy($ProxyServer))
	}Catch{
		Write-Host "    ERROR: Failed Configure Powershell Global Proxy" -ForegroundColor Red
	}

	Write-Host "    Configure netsh winhttp..."
	Try{
		#ref: https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/windows-update-client-determines-proxy-server-connect
		#ProxyBypass MUST use semi-colon ; delimiter
		$noproxylist_sem = $noproxylist -replace ",",";"
		netsh winhttp set proxy proxy-server=$ProxyServer bypass-list=$noproxylist_sem
	}Catch{
		Write-Host "    ERROR: Failed Configure netsh winhttp" -ForegroundColor Red
	}

	Write-Host "    Configure WinHttpProxy..."
	Try{
		#Ref: https://learn.microsoft.com/en-us/powershell/module/winhttpproxy/?view=windowsserver2025-ps
		#ProxyBypass MUST use semi-colon ; delimiter
		$noproxylist_sem = $noproxylist -replace ",",";"
		Set-winhttpproxy -proxyserver $ProxyServer -BypassList $noproxylist_sem
	}Catch{
		Write-Host "    ERROR: Failed Configure WinHttpProxy" -ForegroundColor Red
	}

	Write-Host "    Configure WinInetProxy New for Azure Local..."
	Try{
		#ref: https://learn.microsoft.com/en-us/azure/azure-local/manage/configure-proxy-settings-23h2?view=azloc-24113
		mkdir c:\dell -force
		Set-Location c:\dell\
		IF(!(Get-Command Set-WinInetProxy)){
			Write-Host "        WARN: wininetproxy is NOT installed." -ForegroundColor Yellow
			IF (Test-Path .\wininetproxy.0.1.0.nupkg.zip) {
				Write-Host "        Found wininetproxy in c:dell importing..."
				Expand-Archive .\wininetproxy.0.1.0.nupkg.zip -Force
				Set-Location .\wininetproxy.0.1.0.nupkg\
				Import-Module .\WinInetProxy.psd1
			}else{
			Write-Host "        Please manually download from https://psg-prod-eastus.azureedge.net/packages/wininetproxy.0.1.0.nupkg" -ForegroundColor Yellow
			Write-Host "        copy to c:\dell and run again" -ForegroundColor Yellow}
		}elseif(Get-Command Set-WinInetProxy){
		# ProxyBypass MUST use comma , delimiter	
		Set-WinInetProxy -ProxySettingsPerUser 0 -ProxyServer $ProxyServer -ProxyBypass $noproxylist
		}
	}Catch{
		Write-Host "    ERROR: Failed Configure WinInetProxy New for Azure Local" -ForegroundColor Red
	}
