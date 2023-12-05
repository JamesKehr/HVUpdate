# gets one or more HVUpdate vault secret 
#requires -Version 5.1

using namespace System.Collections.Generic

[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $SecretName = $null
)


begin {
    ### FUNCTIONS ###
    #region

    # import the libraries in this order
    . "$PSScriptRoot\lib\libLogging.ps1"
    . "$PSScriptRoot\lib\libFunction.ps1"
    . "$PSScriptRoot\lib\libGlobal.ps1"

    # create the log file
    $null = mkdir $lPath -Force -EA SilentlyContinue

    $lName = "$script:lNameRoot`_AddVaultCred_$(timestamp -FileStamp)`.log"
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

    log "Get-HVUpdateCredential - Begin"
    #endregion

    # make sure the modules are updated
    $modules = 'Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore'

    foreach ($mod in $modules) {
        # run a module update
        log "Get-HVUpdateCredential - Updating module: $mod"
        $null = Update-Module $mod -EA SilentlyContinue
    }


    # import the modules
    $null = Import-Module Microsoft.PowerShell.SecretManagement -EA Stop
    $null = Import-Module Microsoft.PowerShell.SecretStore -EA Stop
}

process {
    log "Get-HVUpdateCredential - Process"

    log "Get-HVUpdateCredential - Unlocking vault."
    try {
        Unlock-SecretStore -Password $script:VaultPassword -EA Stop 
    } catch {
        logE "Get-HVUpdateCredential - Failed to unlock vault: $_"
        exit
    }
    

    if ( $null -eq $SecretName ) {
        log "Get-HVUpdateCredential - Retrieving all secrets."
        $secret = Get-SecretInfo -Name * -Vault $script:VaultName
    } else {
        $secret = Get-SecretInfo -Name $SecretName -Vault $script:VaultName
    }

}

end {
    log "Get-HVUpdateCredential - End"
    return $secret
}