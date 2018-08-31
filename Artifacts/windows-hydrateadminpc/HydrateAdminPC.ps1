﻿Import-Module PSScheduledJob

# THIS SHOULD NOT BE EXECUTED ON PRODUCTION RESOURCES!!!

# disable real-time AV scans
# THIS SHOULD NOT BE EXECUTED ON PRODUCTION RESOURCES!!!
Set-MpPreference -DisableRealtimeMonitoring $true

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

# Add JeffV and Helpdesk to Local Admin Group
try {
	Add-LocalGroupMember -Group "Administrators" -Member "Contoso\Helpdesk"

	Remove-LocalGroupMember -Group "Administrators" -Member "Domain Admins"
	Write-Output "[+] Added Helpdesk to Admins Group. Removed Domain Admins :)"
}
catch {
	Write-Error "[!] Unable to add Helpdesk to Admin Group" -ErrorAction Stop
}

try {
	Add-LocalGroupMember -Group "Remote Desktop Users" -Member "Contoso\NuckC"
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

# add scheduled task to simulate NuckC activity
try {
	$powershellScriptBlock = { while($true){ Invoke-Expression "dir \\contosodc1\c$";  Start-Sleep -Seconds 60 } } # infinitly loop, traversing c$ of contosodc
	$trigger = New-JobTrigger -AtStartup

	$runAsUser = 'Contoso\NuckC'
	$nuckCSecPass = 'NinjaCat123' | ConvertTo-SecureString -AsPlainText -Force
	$cred = New-Object System.Management.Automation.PSCredential($runAsUser,$nuckCSecPass)

	Register-ScheduledJob -Name "Dir ContosoDC1 as RonHD -- Mimick DA activity" -ScriptBlock $powershellScriptBlock -Trigger $trigger -Credential $cred
	
	Write-Output "[+] Created Scheduled Job to simulate dir \\contosodc\c$ as NuckC on AdminPC (simulate domain admin activity)"

}
catch {
	Write-Error "[-] Unable to create Scheduled Job on AdminPC! Need to simulate NuckC activity other way." -ErrorAction Continue
}