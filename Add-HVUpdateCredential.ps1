# creates the HVUpdate secret vault
#requires -Version 5.1

using namespace System.Collections.Generic

[CmdletBinding()]
param (
    [Parameter()]
    [System.Management.Automation.PSCredential]
    $Credential = $null,

    [Parameter()]
    [string]
    $KeyFile,

    [Parameter()]
    [string]
    $SSHPath
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

    log "Add-HVUpdateCredential - Begin"
    #endregion

    # make sure the modules are updated
    $modules = 'Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore'

    foreach ($mod in $modules) {
        # run a module update
        log "Add-HVUpdateCredential - Updating module: $mod"
        $null = Update-Module $mod -EA SilentlyContinue
    }


    # import the modules
    $null = Import-Module Microsoft.PowerShell.SecretManagement -EA Stop
    $null = Import-Module Microsoft.PowerShell.SecretStore -EA Stop
}

process {
    log "Add-HVUpdateCredential - Process"
    # unlock to the vault
    Unlock-SecretStore -Password $script:VaultPassword 

    if ( -NOT [string]::IsNullOrEmpty( $KeyFile ) ) {

        if ( [string]::IsNullOrEmpty($SSHPath) ) {
            log "Add-HVUpdateCredential - No SSH path provided. This is required when adding a key file, and must contain the connection string to reach the Linux VM: user@[server|IP|FQDN]"
            return (Write-Error "No SSH path provided. This is required when adding a key file, and must contain the connection string to reach the Linux VM: user@[server|IP|FQDN]" -EA Stop)
        }

        $randomizer = "{0:000000}" -f (Get-Random -Minimum 1000 -Maximum 999999)
        log "Add-HVUpdateCredential - Adding keyfile ($KeyFile) as $randomizer."

        $sshConnections = @{HostName = $SSHPath}

        $secretSplat = @{
            Name        = "VMCred_KeyFile_$randomizer"
            Secret      = $KeyFile
            Metadata    = $sshConnections
            Vault       = $script:VaultName
            NoClobber   = $true
            ErrorAction = "Stop"
        }

        try {
            Set-Secret @secretSplat
            log "Add-HVUpdateCredential - Secret added to vault."
        } catch {
            log "Add-HVUpdateCredential - Failed to add the KeyFile secret: $_"
            return ( Write-Host "Failed to add the KeyFile secret: $_" -EA Stop)
        }
    } elseif ( $null -eq $Credential ) {
        log "Add-HVUpdateCredential - Asking for credential(s)."
        [array]$whatToSay = "Try selecting Remove first.", "What do you want to do with that?", "Nothing to see here.", "Move along.", "I don't get it.", "How much wood could a woodchuck chuck if a woodchuck could chuck wood?", "Peanuts are neither peas nor nuts, discuss!", "How does that help?", "What is the average air speed velocity of an unlaided swallow?"
        $opts = [List[System.Management.Automation.PSCredential]]::new()
        $lastError = $null
        
        do {
            Clear-Host

            if ( -NOT [string]::IsNullOrEmpty($lastError) ) {
                log "Add-HVUpdateCredential - lastError: $lastError"
                Write-Host -ForegroundColor Yellow $lastError
            }

            Write-Host "Add Credential to $script:VaultName Secret Vault"
            Write-Host "Select an option:"

            for ($i = 0; $i -lt $opts.Count; $i++) {
                Write-Host "[$($i + 1)] - $($opts[$i].UserName)"
            }

            Write-Host "`n[A] - Add"
            if ($opts.Count -gt 0) { Write-Host "[R] - Remove" }
            Write-Host "[D] - Done"
            Write-Host "[?] - Help"
            
            $selection = Read-Host "`nSelection"

            $selection = $selection.ToLower()

            switch -Regex ($selection) {
                "^a$" {
                    Write-Host "`nPlease enter the credentials: "
                    log "Add-HVUpdateCredential - Adding a credential."

                    try {
                        $tmpCred = Get-Credential -Message "Credential for $script:VaultName" -EA Stop
                    } catch {
                        logE "Add-HVUpdateCredential - Failed to create the credential: $_"
                        break
                    }

                    # add to the opts
                    $opts.Add($tmpCred)
                    log "Add-HVUpdateCredential - Credential added to list."

                    $lastError = $null
                    break
                }
                
                "^r$" {
                    log "Add-HVUpdateCredential - Removing credentials."

                    # ignore if opts is empty
                    if ($opts.Count -eq 0) {
                        log "Add-HVUpdateCredential - Nothing to remove."
                        $lastError = "Cannot remove a credential that does not exist."
                        break
                    }
                    
                    $failCount = 0

                    do {
                        $rmCred = -1
                        try {
                            [int]::TryParse( (Read-Host "Select the credential to remove"), [ref]$rmCred )    
                        } catch {
                            logW "Add-HVUpdateCredential - Invalid selection. Selection must be a number in the credential list."
                            $failCount++
                            continue
                        }

                        if ( $rmCred -lt 1 -or $rmCred -gt $opts.Count ) {
                            logW "Add-HVUpdateCredential - Invalid selection. Selection is out of bounds. The number must be on the credential list."
                            $failCount++
                            continue
                        }
                        
                    } until ( $failCount -gt 5 -or ($rmCred -gt 0 -and $rmCred -le $opts.Count) )
                    
                    if ($rmCred -gt 0 -and $rmCred -le $opts.Count) {
                        # find and remove the credential
                        log "Add-HVUpdateCredential - Removing credntial at index $($rmCred - 1)."
                        $opts.RemoveAt(($rmCred - 1))
                        $lastError = $null
                    } elseif ( $failCount -gt 5 ) {
                        $lastError = "Remove failed. Too many failed attempts."
                    } else {
                        $lastError = "Remove failed. Unknown error. failCount: $failCount, rmCred: $rmCred"
                    }

                    break
                }

                "^\?$" {
                    Clear-Host
                    Write-Host "How to use the credential menu:

The HVUpdateVault is a PowerShell SecretStore on the Hyper-V host. The HVUpdate process uses these secured credentials to logon and manage the update process on VMs. 
                    
`t- Enter A (upper or lower case) to add a credential.
`t`t- Follow the prompts to add VM credentials to the HVUpdateVault.
`t`t- Use the A option to add additional VM credentials until all credentials are added.
`t- Enter R (upper or lower case) to remove a credential.
`t`t- Select the credential number to be removed.
`t`t- Press Enter.
`t`t- Enter R at the main menu to remove additional credentials.
`t- Enter D (upper or lower case) to add the VM credential(s) to the HVUpdateVault.

Press any key to continue..."
                    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                    $lastError = $null
                    break
                }

                default 
                {
                    $saying = Get-Random -Minimum 0 -Maximum ($whatToSay.Count - 1)
                    $lastError = $whatToSay[$saying]
                    break
                }
            }
        } until ($selection -eq "d")

        if ($opts.Count -gt 0) {

            # add the secrets to the vault
            foreach ($cred in $opts) {
                $randomizer = "{0:000000}" -f (Get-Random -Minimum 1000 -Maximum 999999)
                log "Add-HVUpdateCredential - Adding manual credential for $($cred.UserName) as $randomizer."
                $secretSplat = @{
                    Name        = "VMCred_$($cred.UserName)_$randomizer"
                    Secret      = $cred
                    Vault       = $script:VaultName
                    NoClobber   = $true
                    ErrorAction = "Stop"
                }

                try {
                    Set-Secret @secretSplat
                    log "Add-HVUpdateCredential - Secret added to vault."
                } catch {
                    log "Add-HVUpdateCredential - Failed to add the manual secret: $_"
                    return ( Write-Host "Failed to add the manual secret: $_" -EA Stop)
                }
            }
        }
    } else {
        $randomizer = "{0:000000}" -f (Get-Random -Minimum 1000 -Maximum 999999)
        $secretSplat = @{
            Name        = "VMCred_$($Credential.UserName)_$randomizer"
            Secret      = $Credential
            Vault       = $script:VaultName
            NoClobber   = $true
            ErrorAction = "Stop"
        }

        try {
            Set-Secret @secretSplat
            log "Add-HVUpdateCredential - Secret added to vault."
        } catch {
            log "Add-HVUpdateCredential - Failed to add the Credential secret: $_"
            return ( Write-Host "Failed to add the Credential secret: $_" -EA Stop)
        }
    }

}

end {
    log "Add-HVUpdateCredential - End"
}