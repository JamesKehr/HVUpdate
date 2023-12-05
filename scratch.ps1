CD D:\Scripts\UpdateWindows

. ".\lib\libLogging.ps1"
. ".\lib\libFunction.ps1"
. ".\lib\libGlobal.ps1"
. ".\lib\libClass.ps1"


$vm = Get-VM AWS-VM
$secName = 'VMCred_administrator_728640'
$c = [HVUpdateVM]::new($vm, $secName, $true)

$c.UpdateVM()

do {
    Start-Sleep 60
} until ( $c.IsJobComplete())

$c.GetScriptLog()
$c.RebootIfRequired()
$c.Log




$parameters = @{
    HostName    = 'pkunk@gateway'
    ScriptBlock = { hostnamectl }
    KeyFilePath = 'C:\Users\CloudAdmin\AppData\Local\HVUpdate\gateway-kp.pem'
}
Invoke-Command



$AzureUserName = "azure\p101numecentved"
$PassKey = "PqJEfjyzfelj7tgtR6y/Q7HNP1Bl+ui6Cd0pux/qJfRTMQN4bkI7roNkXhRSElpg9c06i5iuCori+AStIDscvg=="
$password = ConvertTo-SecureString -String $PassKey -AsPlainText -Force
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $AzureUserName, $password

New-SmbGlobalMapping -RemotePath "\\p101numecentved.file.core.windows.net\repo" -Credential $cred -LocalPath M: -FullAccess @( "NT AUTHORITY\SYSTEM" ) -Persistent $true



$vmName = "AWS-VM"

$vms = Get-WmiObject -Class Msvm_ComputerSystem -Namespace "root\virtualization"
$vms = $vms | where-object{$_.caption -ne "Hosting Computer System"}
$records = [List[Object]]
ForEach($vm in $vms) {
	
    $requestedProperties = 3,4,101,102,103,104,106,107
	
    $query = "ASSOCIATORS OF {" + $vm.__Path + "} WHERE resultClass = Msvm_VirtualSystemSettingData"
	$settings = Get-WmiObject -query $query -namespace root\virtualization\v2


	$service = Get-CimInstance -class "Msvm_VirtualSystemManagementService" -namespace "root\virtualization\v2"

	$summaryList = $service.GetSummaryInformation($settings.__PATH, $requestedProperties)
    
    $summary = [List[Object]]::new()
	foreach($sum in $summaryList.SummaryInformation)
	{
		$summary = GetSummaryInfo($vm)
	}
    
    
    
	$record = "" | `
	select @{name="VM Name"; expression={$vm.ElementName}},
			@{name="Notes"; expression={$summary.Notes}},
			@{name="Processors"; expression={$summary.NumberOfProcessors}},
			@{name="Processor Load"; expression={$summary.ProcessorLoad}},
			@{name="Processor Load History[Multi]"; expression={$summary.ProcessorLoadHistory}},
			@{name="Memory Usage"; expression={$summary.MemoryUsage}},
			@{name="Heartbeat"; expression={$summary.Heartbeat}},
			@{name="OS"; expression={$summary.GuestOperatingSystem}},
			@{name="Snapshots[Multi]"; expression={GetSnapshotNames $summary.Snapshots}}
	$records += $record
}






# import the libraries
. ".\lib\libLogging.ps1"
. ".\lib\libFunction.ps1"
. ".\lib\libGlobal.ps1"

$script:VaultPassFile
$script:vaultFile
$script:ValutPassword




    # create the log file
    $null = mkdir $lPath -Force -EA SilentlyContinue

    $lName = "$script:lNameRoot`_AddVault_$(timestamp -FileStamp)`.log"
    $logPath = "$lPath\$lName"
    $null = New-Item -Path "$logPath" -ItemType File -Force

    # now set $logPath as the default LogPath parameter for the log functions
    $PSDefaultParameterValues = @{
        "log:LogPath"="$logPath";
        "logS:LogPath"="$logPath";
        "logE:LogPath"="$logPath";
        "logW:LogPath"="$logPath";
        "logV:LogPath"="$logPath";
        "logD:LogPath"="$logPath";
        "logI:LogPath"="$logPath"    
    }

    if ($Quiet.IsPresent) {
        $PSDefaultParameterValues = @{
            "log:Quiet"=$Quiet;
            "logS:Quiet"=$Quiet;
            "logI:Quiet"=$Quiet    
        }
    }
