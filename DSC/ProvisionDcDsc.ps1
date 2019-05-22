Configuration CreateADForest
{
	param(
		[Parameter(Mandatory=$false)]
		[String]$DomainName='Contoso.Azure',

		[Parameter(Mandatory=$false)]
		[string]$NetBiosName='Contoso',

		[Parameter(Mandatory=$true)]
		[PSCredential] $AdminCreds,

		[Parameter(Mandatory=$true)]
		[string] $UserPrincipalName = "seccxp.ninja",

		[Parameter(Mandatory=$true)]
		[pscredential]$JeffLCreds,

		[Parameter(Mandatory=$true)]
		[pscredential]$SamiraACreds,

		[Parameter(Mandatory=$true)]
		[pscredential]$RonHdCreds,

		[Parameter(Mandatory=$true)]
		[pscredential]$LisaVCreds,

		[Int]$RetryCount=20,
		[Int]$RetryIntervalSec=30
	)
	
	Import-DscResource -ModuleName PSDesiredStateConfiguration, XActiveDirectory, xPendingReboot, `
		xNetworking, xStorage, xDefender

	$Interface=Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1
	$InterfaceAlias=$($Interface.Name)

	[System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($AdminCreds.UserName)", $AdminCreds.Password)
	
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

		xDnsServerAddress DnsServerAddress 
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
			UserPrincipalNameSuffixToAdd = $ # important for AAD Connect purposes
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

		xADUser SamiraA # Domain Admin
		{
			DomainName = $DomainName
			UserName = 'SamiraA'
			Password = $SamiraAPassword
			Ensure = 'Present'
			UserPrincipalName = $UserPrincipalName
			PasswordNeverExpires = $true
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADUser RonHD # Helpdesk
		{
			DomainName = $DomainName
			UserName = 'RonHD'
			Password = $RonHdPassword
			Ensure = 'Present'
			PasswordNeverExpires = $true
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADUser JeffL # Victim
		{
			DomainName = $DomainName
			UserName = 'JeffL'
			Password = $JeffLPassword
			Ensure = 'Present'
			PasswordNeverExpires = $true
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADUser LisaV # Access to High Impact Data
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
			Description = 'Helpdesk for this domain'
			DisplayName = 'Helpdesk'
			MembershipAttribute = 'SamAccountName'
			MembersToInclude = "RonHD"
			DependsOn = @("[xADUser]RonHD", "[xWaitForADDomain]DscForestWait")
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