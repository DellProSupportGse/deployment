# This configuration is used to set up the proxy across all locations on a Windows server to ensure the proxy functions properly.
# Version 1.5
# By: Jim Gandy

 # Proxy variables
	# Update with your Proxy information before running
		$ProxyServer="http://myproxyserver.com:8080" 
        # Please use CIDR notation for IP ranges EX: 192.168.1.1-254 = 192.168.1.0/24
		$noproxylist="192.168.1.0/24,*.svc,localhost,127.0.0.1,*.DomainShortName.com,*.DomainFQDN.com,wacserver,nodeshort,nodefqdn,nodeipaddress,idracIPs,iSMiDRACIPs,infrastructureIps,ClusterShortName,ClusterFQDN"

    # Check for semicolan(;) delimitation and change the comma(,)
    $noproxylist = $noproxylist -replace ";",","

    # Convert wildcards to CIDR
    # Ref: https://learn.microsoft.com/en-us/azure/azure-local/manage/configure-proxy-settings-23h2?view=azloc-2504#environment-variables-proxy-bypass-list-string-considerations
    function Convert-CidrInListToWildcard {
        param (
            [string]$inputList
        )

        $outputList = $inputList -split ',' | ForEach-Object {
            if ($_ -match '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/(\d+)$') {
                $a, $b, $c, $d, $prefix = $matches[1..5]
                $prefix = [int]$prefix

                if ($prefix -ge 1 -and $prefix -le 7) {
                    '*.*.*.*'
                } elseif ($prefix -ge 8 -and $prefix -le 15) {
                    "$a.*.*.*"
                } elseif ($prefix -ge 16 -and $prefix -le 23) {
                    "$a.$b.*.*"
                } elseif ($prefix -eq 24 -and $prefix -le 32) {
                    "$a.$b.$c.*"
                } else {
                    $_  # Leave it untouched if not in range
                }
            } else {
                $_  # Not a CIDR, leave unchanged
            }
        }

        return ($outputList -join ',')
    }

    # Run only if CIDR detected
    if ($noproxylist -match '\d{1,3}(\.\d{1,3}){3}/\d{1,2}') {
    	Write-Host "Converting CIDR to Wildcard..."
	$cidrnoproxylist = $noproxylist
        $NoProxyList = Convert-CidrInListToWildcard $noproxylist
	Write-Host "CIDR:" $cidrnoproxylist
 	Write-host "Wildcard:" $noproxylist
    }

	Write-Host "    Environment variables..."
	Try	{
		[Environment]::SetEnvironmentVariable("HTTPS_PROXY",$ProxyServer , "Machine")
		$env:HTTPS_PROXY = [System.Environment]::GetEnvironmentVariable("HTTPS_PROXY", "Machine")
		[Environment]::SetEnvironmentVariable("HTTP_PROXY",$ProxyServer, "Machine")
		$env:HTTP_PROXY = [System.Environment]::GetEnvironmentVariable("HTTP_PROXY", "Machine")
		#ProxyBypass MUST use comma , delimiter
        IF($cidrnoproxylist){[Environment]::SetEnvironmentVariable("NO_PROXY", $cidrnoproxylist, "Machine")}Else{[Environment]::SetEnvironmentVariable("NO_PROXY", $NoProxyList, "Machine")}
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
