﻿## GIVE RONHD LOGON AS BATCH TO DO SCHEDULEDJOB

Import-Module PSScheduledJob

# THIS SHOULD NOT BE EXECUTED ON PRODUCTION RESOURCES!!!

# disable real-time AV scans
# THIS SHOULD NOT BE EXECUTED ON PRODUCTION RESOURCES!!!
Set-MpPreference -DisableRealtimeMonitoring $true
New-ItemProperty -Path “HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender” -Name DisableAntiSpyware -Value 1 -PropertyType DWORD -Force
# Do fix for Azure DevTest Lab DNS (point to ContosoDC)
# set DNS to ContosoDC IP
# get contosoDC IP
try{
	$contosoDcIp = (Resolve-DnsName "ContosoDC1").IPAddress

	# get current DNS
	$currentDns = (Get-DnsClientServerAddress).ServerAddresses
	# add contosodc
	$currentDns += $contosoDcIp
	# make change to DNS with all DNS servers 
	Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" -ServerAddresses $currentDns
	Write-Output "[+] Added ContosoDC1 to DNS"
}
catch {
	Write-Error "[!] Unable to add ContosoDC1 to DNS" -ErrorAction Stop
}

# Turn on network discovery
try{
	Get-NetFirewallRule -DisplayGroup 'Network Discovery' | Set-NetFirewallRule -Profile 'Private, Domain, Public' -Enabled true
	Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing' | Set-NetFirewallRule -Profile 'Private, Domain, Public' -Enabled true
	Write-Output "[+] Put AdminPC in Network Discovery and File and Printer Sharing Mode"
}
catch {
	Write-Error "[!] Unable to put AdminPC in Network Discovery Mode" -ErrorAction Continue
}

# Domain join computer
try {
	$domain = "contoso.azure"
	$user = "contoso\nuckc"
	$nuckCPass = "NinjaCat123" | ConvertTo-SecureString -AsPlainText -Force
	$cred = New-Object System.Management.Automation.PSCredential($user, $nuckCPass)

	Add-Computer -DomainName $domain -Credential $cred
	Write-Output "[+] AdminPC added to Contoso"
}
catch {
	Write-Error "[!] Unable to add AdminPC to Contoso domain" -ErrorAction Stop
}

# Add Helpdesk to Local Admin Group
try {
	Add-LocalGroupMember -Group "Administrators" -Member "Contoso\Helpdesk"
	Remove-LocalGroupMember -Group "Administrators" -Member "Domain Admins"
	Write-Output "[+] Added Helpdesk to Admins Group. Removed Domain Admins :)"
}
catch {
	Write-Error "[!] Unable to add Helpdesk to Admin Group" -ErrorAction Stop
}

# needed for Azure and Hyper-V since user is removed from admin group
try {
	Add-LocalGroupMember -Group "Remote Desktop Users" -Member "Contoso\NuckC"
	Add-LocalGroupMember -Group "Backup Operators" -Member "Contoso\NuckC" # used to automate traffic as ScheduledJob; gives him "Logon as Batch" privileges required for Scheduled Jobs
	Write-Output "[+] Added NuckC to Remote Desktop Users"
}
catch {
	Write-Error "[!] Unable to add NuckC to Remote Desktop Users group"
}


# hide Server Manager at logon and IE Secure Mode
try{
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\ServerManager -Name DoNotOpenServerManagerAtLogon -PropertyType DWORD -Value "0x1" -Force
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\ServerManager\Oobe -Name DoNotOpenInitialConfigurationTasksAtLogon -PropertyType DWORD -Value "0x1" -Force

	# remove IE Enhanced Security
	Set-ItemProperty -Path “HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}” -Name isinstalled -Value 0
	Set-ItemProperty -Path “HKLM:SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}” -Name isinstalled -Value 0
	Rundll32 iesetup.dll, IEHardenLMSettings,1,True
	Rundll32 iesetup.dll, IEHardenUser,1,True
	Rundll32 iesetup.dll, IEHardenAdmin,1,True
	If (Test-Path “HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}”) {
		Remove-Item -Path “HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}”
	}
	If (Test-Path “HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}”) {
		Remove-Item -Path “HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}”
	}
	Write-Output "[+] Disabled Server Manager and IE Enhanced Security"
}
catch {
	Write-Error "[!] Unable to disable IE Enhanced Security or Server Manager at startup" -ErrorAction Continue
}

# audit remote SAM
try {
	New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name 'RestrictRemoteSamAuditOnlyMode' -PropertyType DWORD -Value "0x1" -Force
	Write-Output "[+] Put remote SAM settings in Audit mode"
}
catch {
	Write-Error "[!] Unable to change Remote SAM settings (needed for lateral movement graph)" -ErrorAction Continue
}

try {
	Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass
	Write-Output "[+] Set execution policy to allow Ps1 across machine"
}
catch {
	Write-Output "[!] Unable to change execution policy for AdminPC"
}

# add scheduled task to simulate NuckC activity
# Requires NuckC to have "logon as batch" privileges on the system since he is now removed from
try {
	$scriptblock = [scriptblock]{
		$powershellScriptBlock = [scriptblock]{ while($true){ Get-Date; Get-ChildItem \\contosodc\c$; exit(0) } }# infinitly loop, traversing c$ of contosodc
		$runAsUser = 'Contoso\NuckC'
		$nuckCSecPass = 'NinjaCat123' | ConvertTo-SecureString -AsPlainText -Force
		$cred = New-Object System.Management.Automation.PSCredential($runAsUser,$nuckCSecPass)
	
		while ($true)
		{
			$j = Start-Job -ScriptBlock $powershellScriptBlock -Credential $cred
			$r = $j | Wait-Job | Receive-Job
	
			$r | fl
			
			Start-Sleep -Seconds 60
		}
	}
	try{
		$filepath = "c:\Users\NuckC\Desktop\dircontosodc.ps1"
		$scriptblock | Out-File $filepath -Force
		Write-Output "[+] Created ps1 file in $filepath for scheduled task purposes"
	}
	catch {
		Write-Output "[!] Unable to create PS1 on AdminPC. Can't replicate NuckC--must do this manually!!!"
	}
	

	$action = New-ScheduledTaskAction "Powershell.exe" -Argument $filepath
	$trigger = New-ScheduledTaskTrigger -AtLogOn -User 'Contoso\NuckC'
	$runAs = 'Contoso\NuckC'
	$nuckCSecPass = 'NinjaCat123'

	Register-ScheduledTask -TaskName "Dir ContosoDC as NuckC" -Trigger $trigger -User $runAs -Password $nuckCSecPass -Action $action
}
catch {
	Write-Error "[!] Unable to create Scheduled Task on AdminPC! Need to simulate NuckC activity other way." -ErrorAction Continue
}