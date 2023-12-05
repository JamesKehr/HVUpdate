# runs Windows Update via PowerShell
#requires -RunAsAdministrator
#requires -Version 5.1

#log "Update-Windows - "

using namespace System.Collections.Generic

[CmdletBinding()]
param (
    # Restarts the system, if needed, once updates are done.
    [Parameter()]
    [switch]
    $Restart
)

begin {
    # disable progress
    $ProgressPreference = "SilentlyContinue"

    ### FUNCTIONS ###
    #region

    # import the libraries
    . "$PSScriptRoot\lib\libGlobal.ps1"
    . "$PSScriptRoot\lib\libLogging.ps1"

    # create the log file
    $null = mkdir $lPath -Force -EA SilentlyContinue

    $lName = "Update-Windows_$((timestamp).Replace(':',''))`.log"
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

    log "Update-Windows - Begin"
    #endregion

    # make sure PSWindowsUpdate is installed
    $pswuFnd = Get-Module -ListAvailable PSWindowsUpdate -EA SilentlyContinue

    if ( -NOT $pswuFnd ) {
        try {
            log "Update-Windows - Installing PSWindowsUpdate"
            $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
            $null = Install-Module PSWindowsUpdate -Force -ErrorAction Stop
            log "Update-Windows - PSWindowsUpdate was successfully installed."
        }
        catch {
            logE "Update-Windows - Failed to install PSWindowsUpdate: $_"
            exit
        }
    } else {
        log "Update-Windows - Checking for a new version of PSWindowsUpdate."
        # run a module update
        try {
            $null = Update-Module PSWindowsUpdate -Force -EA Stop
        }
        catch {
            logE "Update-Windows - Failed to update PSWindowsUpdate: $_"
            # not a termination error
        }
        
    }
}

process {
    log "Update-Windows - Process"

    log "Update-Windows - Installing updates."
    $gwu = Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot

    if ( $gwu ) {
        log "Update-Windows - Installed updates:`n$($gwu | Format-Table | Out-String)`n"

        $rebootRequired = !!($gwu | Where-Object { $_.RebootRequired })

        log "Update-Windows - Reboot needed: $rebootRequired"
    } else {
        log "Update-Windows - No updates were installed"
    }
}

end {
    return "rebootRequired:$rebootRequired"
    log "Update-Windows - End"
}