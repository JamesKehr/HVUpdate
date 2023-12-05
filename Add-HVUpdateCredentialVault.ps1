# creates the HVUpdate secret vault
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

    log "Add-HVUpdateCredentialVault - Begin"
    #endregion

    # make sure the modules are installed
    $modules = 'Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore'

    foreach ($mod in $modules) {
        log "Add-HVUpdateCredentialVault - Checking module: $mod"
        $modFnd = Get-Module -ListAvailable $mod -EA SilentlyContinue

        if ( -NOT $modFnd) {
            log "Add-HVUpdateCredentialVault - $mod is not installed."
            try {
                log "Add-HVUpdateCredentialVault - Installing $mod."
                $null = Install-Module $mod -Force -EA Stop
                log "Add-HVUpdateCredentialVault - $mod has been installed."
            }
            catch {
                log "Add-HVUpdateCredentialVault - Failed to install a required module ($mod): $_"
                return ( Write-Error "Failed to install a required module ($mod): $_" -EA Stop )
            }
        } else {
            # run a module update
            log "Add-HVUpdateCredentialVault - Updating module: $mod"
            $null = Update-Module $mod -EA SilentlyContinue
        }
    }
}

process {
    log "Add-HVUpdateCredentialVault - Process"
    log "Add-HVUpdateCredentialVault - Registering the $script:VaultName vault."
    try {
        # create the vault
        $vault = Register-SecretVault -Name $script:VaultName -ModuleName Microsoft.PowerShell.SecretStore -PassThru
        log "Add-HVUpdateCredentialVault - Vault created:`n$($vault | Format-List | Out-String)`n" 
    } catch {
        log "Add-HVUpdateCredentialVault - Failed to create the vault ($script:VaultName): $_"
        return ( Write-Error "Failed to create the vault ($script:VaultName): $_" -EA Stop )
    }

    if ( [string]::IsNullOrEmpty($script:VaultPassFile) ) {
        log "Add-HVUpdateCredentialVault - Updating the vault password file location to: $($script:vaultFile.PassFile)"

        $script:VaultPassword = (Get-HVUpdateVaultPassword -PassFile "$($script:vaultFile.PassFile)").Password

        # update libGlobal
        $libGContent = [List[string]]::new()
        switch -Regex -File "$PSScriptRoot\lib\libGlobal.ps1" {
            "^\`$script:VaultPassFile.*$" {
                $tmpLineComment = "# Replaced $((Get-Date).ToString()) : $_"
                log "tmpLineComment: $tmpLineComment"

                $tmpLine = "`$script:VaultPassFile = '$($script:vaultFile.PassFile)'"
                log "tmpLine: $tmpLine"

                $libGContent.Add($tmpLine)
                $libGContent.Add($tmpLineComment)
            }

            default { $libGContent.Add($_) }
        }

        $libGContent | Out-File "$PSScriptRoot\lib\libGlobal.ps1" -Force
    }

    if ( $script:VaultPassword -is [System.Security.SecureString] ) {
        log "Add-HVUpdateCredentialVault - Adding the vault password."
        $null = Set-SecretStorePassword -Password $script:VaultPassword -NewPassword $script:VaultPassword
    } else {
        logE "Add-HVUpdateCredentialVault - Failed to retrieve the Vault Password. Unregistering the vault."
        $null = Unregister-SecretVault -Name $script:VaultName
    }
}

end {
    log "Add-HVUpdateCredentialVault - End"
}