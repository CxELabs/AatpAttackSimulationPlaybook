Configuration CreateADForest
{
	param(
		[Parameter(Mandatory=$true)]
		[string]$DomainName='Contoso.Azure',

		[Parameter(Mandatory=$true)]
		[string]$NetBiosName='Contoso',

		[Parameter(Mandatory=$true)]
		[PSCredential]$AdminCreds,

		[Parameter(Mandatory=$true)]
		[string]$UserPrincipalName = "seccxp.ninja",

		[Parameter(Mandatory=$true)]
		[PSCredential]$JeffLCreds,

		[Parameter(Mandatory=$true)]
		[PSCredential]$SamiraACreds,

		[Parameter(Mandatory=$true)]
		[PSCredential]$RonHdCreds,

		[Parameter(Mandatory=$true)]
		[PSCredential]$LisaVCreds,

		[int]$RetryCount=20,
		[int]$RetryIntervalSec=30
	)

	Import-DscResource -ModuleName PSDesiredStateConfiguration, xActiveDirectory, xPendingReboot, `
		NetworkingDsc, xStorage, xDefender

	$Interface=Get-NetAdapter | Where-Object Name -Like "Ethernet*"|Select-Object -First 1
	$InterfaceAlias=$($Interface.Name)

	[PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($AdminCreds.UserName)", $AdminCreds.Password)
	
	Node localhost
	{
		LocalConfigurationManager
		{
			RebootNodeIfNeeded = $true
		}
		
		WindowsFeature DNS
		{
			Ensure = 'Present'
			Name = 'DNS'
		}

		DnsServerAddress DnsServerAddress 
		{ 
			Address        = '127.0.0.1'
			InterfaceAlias = $InterfaceAlias
			AddressFamily  = 'IPv4'
			DependsOn = "[WindowsFeature]DNS"
		}

		WindowsFeature DnsTools
		{
			Ensure = "Present"
			Name = "RSAT-DNS-Server"
			DependsOn = "[WindowsFeature]DNS"
		}

		WindowsFeature ADDSInstall
		{
			Ensure = 'Present'
			Name = 'AD-Domain-Services'
		}

		WindowsFeature ADDSTools
		{
			Ensure = "Present"
			Name = "RSAT-ADDS-Tools"
			DependsOn = "[WindowsFeature]ADDSInstall"
		}

		WindowsFeature ADAdminCenter
		{
			Ensure = "Present"
			Name = "RSAT-AD-AdminCenter"
			DependsOn = "[WindowsFeature]ADDSInstall"
		}

		xADDomain ContosoDC
		{
			DomainName = $DomainName
			DomainNetbiosName = $NetBiosName
			DomainAdministratorCredential = $DomainCreds
			SafemodeAdministratorPassword = $DomainCreds
			ForestMode = 'Win2012R2'
			DatabasePath = 'C:\Windows\NTDS'
			LogPath = 'C:\Windows\NTDS'
			SysvolPath = 'C:\Windows\SYSVOL'
			DependsOn = '[WindowsFeature]ADDSInstall'
		}
	
		xADForestProperties ForestProps
		{
			ForestName = $DomainName
			UserPrincipalNameSuffixToAdd = $UserPrincipalName
			DependsOn = '[xADDomain]ContosoDC'
		}

		xWaitForADDomain DscForestWait
		{
				DomainName = $DomainName
				DomainUserCredential = $DomainCreds
				RetryCount = $RetryCount
				RetryIntervalSec = $RetryIntervalSec
				DependsOn = "[xADDomain]ContosoDC"
		}

		xADUser SamiraA
		{
			DomainName = $DomainName
			UserName = 'SamiraA'
			Password = $SamiraAPassword
			Ensure = 'Present'
			UserPrincipalName = $UserPrincipalName
			PasswordNeverExpires = $true
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADUser RonHD
		{
			DomainName = $DomainName
			UserName = 'RonHD'
			Password = $RonHdPassword
			Ensure = 'Present'
			PasswordNeverExpires = $true
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADUser JeffL
		{
			DomainName = $DomainName
			UserName = 'JeffL'
			Password = $JeffLPassword
			Ensure = 'Present'
			PasswordNeverExpires = $true
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADUser LisaV
		{
			DomainName = $DomainName
			UserName = 'LisaV'
			Password =  $LisaVPassword
			Ensure = 'Present'
			PasswordNeverExpires = $true
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADGroup DomainAdmins
		{
			GroupName = 'Domain Admins'
			Category = 'Security'
			GroupScope = 'Global'
			MembershipAttribute = 'SamAccountName'
			MembersToInclude = "SamiraA"
			DependsOn = @("[xADUser]SamiraA", "[xWaitForADDomain]DscForestWait")
		}

		xADGroup Helpdesk
		{
			GroupName = 'Helpdesk'
			Category = 'Security'
			GroupScope = 'Global'
			Description = 'Tier-2 (desktop) Helpdesk for this domain'
			DisplayName = 'Helpdesk'
			MembershipAttribute = 'SamAccountName'
			MembersToInclude = "RonHD"
			DependsOn = @("[xADUser]RonHD","[xWaitForADDomain]DscForestWait")
		}

		xMpPreference DefenderSettings
		{
			Name = 'DefenderProperties'
			DisableRealtimeMonitoring = $true
			ExclusionPath = 'c:\Temp'
		}

		# scheduled tasks section
		# https://github.com/PowerShell/ComputerManagementDsc/wiki/ScheduledTask
		# good way to avert attackers knowing if its planted there via other means
		# would also mean can't do this via ScheduledTask, that it would need to run as a real Extension 
		# applied every XXX minutes
	} #end of node
} #end of configuration