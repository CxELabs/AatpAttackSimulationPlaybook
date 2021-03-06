param(
    # resource group name; defaults to andrew-test
    [Parameter(Mandatory=$false)]
    [string]
    $ResourceGroupName = 'cxe-lab-test'
)

$Ips = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName
$vmDetails = New-Object "System.Collections.Generic.List[psobject]"
foreach ($instance in $Ips){
    $Vm = ($instance.VirtualMachine).Id.Split('/') | Select-Object -Last 1
    $PrivateIp = $instance.IpConfigurations.PrivateIpAddress
    $PublicIp = (Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name ($instance.IpConfigurations.publicIpAddress.Id.Split('/') `
        | Select-Object -Last 1)).IpAddress
    $obj = New-Object psobject -Property @{
        ResourceGroupName = $ResourceGroupName
        VmName = $vm
        PrivateIp = $PrivateIp
        PublicIp = $PublicIp
    }
    $vmDetails.Add($obj)
}
Write-Output $vmDetails