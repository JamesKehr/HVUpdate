# removes the HVUpdate secret vault
#requires -Version 5.1
#requires -RunAsAdministrator

using namespace System.Collections.Generic

[CmdletBinding()]
param ()


begin {
    ### FUNCTIONS ###
    #region

    # import the libraries in this order
    . "$PSScriptRoot\lib\libLogging.ps1"
    . "$PSScriptRoot\lib\libFunction.ps1"
    . "$PSScriptRoot\lib\libGlobal.ps1" 

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

    log "Remove-HVUpdateCredentialVault - Begin"
    #endregion

    # make sure the modules are installed
    $modules = 'Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore'

    foreach ($mod in $modules) {
        log "Remove-HVUpdateCredentialVault - Checking module: $mod"
        $modFnd = Get-Module -ListAvailable $mod -EA SilentlyContinue

        if ( -NOT $modFnd) {
            log "Remove-HVUpdateCredentialVault - $mod is not installed."
            try {
                log "Remove-HVUpdateCredentialVault - Installing $mod."
                $null = Install-Module $mod -Force -EA Stop
                log "Remove-HVUpdateCredentialVault - $mod has been installed."
            }
            catch {
                log "Remove-HVUpdateCredentialVault - Failed to install a required module ($mod): $_"
                return ( Write-Error "Failed to install a required module ($mod): $_" -EA Stop )
            }
        } else {
            # run a module update
            log "Remove-HVUpdateCredentialVault - Updating module: $mod"
            $null = Update-Module $mod -EA SilentlyContinue
        }
    }
}

process {
    log "Remove-HVUpdateCredentialVault - Process"
    log "Remove-HVUpdateCredentialVault - Unregistering the $script:VaultName vault."
    try {
        # create the vault
        $null = Unregister-SecretVault -Name $script:VaultName -EA Stop
        log "Remove-HVUpdateCredentialVault - Vault removed." 
    } catch {
        log "Remove-HVUpdateCredentialVault - Failed to remove the vault ($script:VaultName): $_"
        return ( Write-Error "Failed to remove the vault ($script:VaultName): $_" -EA Stop )
    }

    # cleanup the cred file
    if ( $script:VaultPassFile ) {
        log "Remove-HVUpdateCredentialVault - Cleaning up the vault password files."
        $null = Remove-Item "$script:VaultPassFile" -Force -EA SilentlyContinue

        # update libGlobal
        $libGContent = [List[string]]::new()
        switch -Regex -File "$PSScriptRoot\lib\libGlobal.ps1" {
            "^\`$script:VaultPassFile.*$" {
                $tmpLineComment = "# Replaced $((Get-Date).ToString()) : $_"
                log "tmpLineComment: $tmpLineComment"

                $tmpLine = "`$script:VaultPassFile = `$null"
                log "tmpLine: $tmpLine"

                $libGContent.Add($tmpLine)
                $libGContent.Add($tmpLineComment)
            }

            default { $libGContent.Add($_) }
        }

        log "Remove-HVUpdateCredentialVault - Updating libGlobal."
        $libGContent | Out-File "$PSScriptRoot\lib\libGlobal.ps1" -Force
    }

    # remove any files not matching $script:VmConf in the HVUpdate app dir
    log "Remove-HVUpdateCredentialVault - Cleaning up credential file(s)."
    $exclude = "hvupdate.json|.*pem"
    $null = Get-ChildItem "$script:VmConfDir" | Where-Object Name -notmatch $exclude | Remove-Item -Force -EA SilentlyContinue
}

end {
    log "Remove-HVUpdateCredentialVault - End"
}