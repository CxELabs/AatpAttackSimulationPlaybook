Configuration SetupAipScannerCore
{
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$NetBiosName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DnsServer,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$AdminCred,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [PsCredential]$AipScannerCred

    )
    Import-DscResource -ModuleName PSDesiredStateConfiguration, xDefender, ComputerManagementDsc, NetworkingDsc, xSystemSecurity, DSCR_Shortcut, cChoco
    $Interface=Get-NetAdapter | Where-Object Name -Like "Ethernet*"|Select-Object -First 1
    $InterfaceAlias=$($Interface.Name)

    $AipProductId = "48A06F18-951C-42CA-86F1-3046AF06D15E"

	[PSCredential]$Creds = New-Object System.Management.Automation.PSCredential ("${NetBiosName}\$($AdminCred.UserName)", $AdminCred.Password)

    Node localhost
    {
        #region COE
		DnsServerAddress DnsServerAddress 
		{
			Address        = $DnsServer
			InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
            Validate = $true
        }

        xIEEsc DisableAdminIeEsc
        {
            UserRole = 'Administrators'
            IsEnabled = $false
        }

        xIEEsc DisableUserIeEsc
        {
            UserRole = 'Users'
            IsEnabled = $false
        }

        Service DisableWindowsUpdate
        {
            Name = 'wuauserv'
            State = 'Stopped'
            StartupType = 'Disabled'
        }

        Computer JoinDomain
        {
            Name = 'Client01'
            DomainName = $DomainName
            Credential = $Creds
            DependsOn = "[DnsServerAddress]DnsServerAddress"
        }

        Group AddAdmins
        {
            GroupName = 'Administrators'
            MembersToInclude = "$NetBiosName\$($AipScannerCred.UserName)"
            Ensure = 'Present'
            DependsOn = '[Computer]JoinDomain'
        }

        Registry HideServerManager
        {
            Key = 'HKLM:\SOFTWARE\Microsoft\ServerManager'
            ValueName = 'DoNotOpenServerManagerAtLogon'
            ValueType = 'Dword'
            ValueData = '1'
            Force = $true
            Ensure = 'Present'
            DependsOn = '[Computer]JoinDomain'
        }

        #region Choco
        cChocoInstaller InstallChoco
        {
            InstallDir = "C:\choco"
            DependsOn = '[Computer]JoinDomain'
        }

        cChocoPackageInstaller InstallSysInternals
        {
            Name = 'sysinternals'
            Ensure = 'Present'
            AutoUpgrade = $false
            DependsOn = '[cChocoInstaller]InstallChoco'
        }

        Script DownloadBginfo
        {
            SetScript =
            {
                if ((Test-Path -PathType Container -LiteralPath 'C:\BgInfo\') -ne $true){
					New-Item -Path 'C:\BgInfo\' -ItemType Directory
				}
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $ProgressPreference = 'SilentlyContinue' # used to speed this up from 30s to 100ms
                Invoke-WebRequest -Uri 'https://github.com/ciberesponce/AatpAttackSimulationPlaybook/blob/master/Downloads/BgInfo/aippc.bgi?raw=true' -Outfile 'C:\BgInfo\BgInfoConfig.bgi'
			}
            GetScript =
            {
                if (Test-Path -LiteralPath 'C:\BgInfo\BgInfoConfig.bgi' -PathType Leaf){
                    return @{
                        result = $true
                    }
                }
                else {
                    return @{
                        result = $false
                    }
                }
            }
            TestScript = 
            {
                if (Test-Path -LiteralPath 'C:\BgInfo\BgInfoConfig.bgi' -PathType Leaf){
                    return $true
                }
                else {
                    return $false
                }
			}
            DependsOn = '[cChocoPackageInstaller]InstallSysInternals'
        }
        
        cShortcut BgInfo
		{
			Path = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\BgInfo.lnk'
			Target = 'bginfo64.exe'
			Arguments = 'c:\BgInfo\BgInfoConfig.bgi /accepteula /timer:0'
            Description = 'Ensure BgInfo starts at every logon, in context of the user signing in (only way for stable use!)'
            DependsOn = @('[Script]DownloadBginfo','[cChocoPackageInstaller]InstallSysInternals')
		}


        Script TurnOnNetworkDiscovery
        {
            SetScript = 
            {
                Get-NetFirewallRule -DisplayGroup 'Network Discovery' | Set-NetFirewallRule -Profile 'Domain, Private' -Enabled true
            }
            GetScript = 
            {
                $fwRules = Get-NetFirewallRule -DisplayGroup 'Network Discovery'
                $result = $true
                foreach ($rule in $fwRules){
                    if ($rule.Enabled -eq 'False'){
                        $result = $false
                        break
                    }
                }
                return @{
                    result = $result
                }
            }
            TestScript = 
            {
                $fwRules = Get-NetFirewallRule -DisplayGroup 'Network Discovery'
                $result = $true
                foreach ($rule in $fwRules){
                    if ($rule.Enabled -eq 'False'){
                        $result = $false
                        break
                    }
                }
                return $result
            }
            DependsOn = '[Computer]JoinDomain'
        }
        
        Script TurnOnFileSharing
        {
            SetScript = 
            {
                Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing' | Set-NetFirewallRule -Profile 'Domain, Private' -Enabled true
            }
            GetScript = 
            {
                $fwRules = Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing'
                $result = $true
                foreach ($rule in $fwRules){
                    if ($rule.Enabled -eq 'False'){
                        $result = $false
                        break
                    }
                }
                return @{
                    result = $result
                }
            }
            TestScript = 
            {
                $fwRules = Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing'
                $result = $true
                foreach ($rule in $fwRules){
                    if ($rule.Enabled -eq 'False'){
                        $result = $false
                        break
                    }
                }
                return $result
            }
            DependsOn = '[Computer]JoinDomain'
        }

        Registry HideInitialServerManager
        {
            Key = 'HKLM:\SOFTWARE\Microsoft\ServerManager\Oobe'
            ValueName = 'DoNotOpenInitialConfigurationTasksAtLogon'
            ValueType = 'Dword'
            ValueData = '1'
            Force = $true
            Ensure = 'Present'
            DependsOn = '[Computer]JoinDomain'
        }

        Registry AuditModeSamr
        {
            Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
            ValueName = 'RestrictRemoteSamAuditOnlyMode'
            ValueType = 'Dword'
            ValueData = '1'
            Force = $true
            Ensure = 'Present'
            DependsOn = '[Computer]JoinDomain'
        }
        #endregion

        Script DownloadAipMsi
		{
			SetScript = 
            {
                if ((Test-Path -PathType Container -LiteralPath 'C:\LabTools\') -ne $true){
					New-Item -Path 'C:\LabTools\' -ItemType Directory
				}
				[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Start-BitsTransfer -Source 'https://github.com/ciberesponce/AatpAttackSimulationPlaybook/blob/master/Downloads/AzInfoProtection_MSI_for_central_deployment.msi?raw=true' -Destination 'C:\LabTools\aip_installer.msi'
            }
			GetScript = 
            {
				if (Test-Path 'C:\LabTools\aip_installer.msi'){
					return @{
						result = $true
					}
				}
				else {
					return @{
						result = $false
					}
				}
            }
            TestScript = 
            {
				if (Test-Path 'C:\LabTools\aip_installer.msi'){
					return $true
				}
				else {
					return $false
				}
			}
		}

		Package InstallAipClient
		{
			Name = 'Microsoft Azure Information Protection'
			Ensure = 'Present'
			Path = 'C:\LabTools\aip_installer.msi'
			ProductId = $AipProductId
			Arguments = '/quiet'
			DependsOn = @('[Script]DownloadAipMsi','[Computer]JoinDomain')
		}
    }
}