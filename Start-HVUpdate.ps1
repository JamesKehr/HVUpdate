# manages the VM update process
# PowerShell 7.3 is required for SSH compatibility. This is only required on the host process.

<#
    TO-DO:
        - A Hyper-V lab server that cannot run all VMs are once will fail.
            - Need to add a throttle limit of some kind...
            - Update all running VMs.
            - Then start each powered down VM, one at a time, update, stop/pause/suspend, repeat until they are all done.


#>

#requires -Version 7.3
#requires -RunAsAdministrator

using namespace System.Collections.Generic
using namespace System.Collections.Generic.list

[CmdletBinding()]
param (
    [Parameter()]
    [int]
    $StartupThrottleLimit = 2,

    [Parameter()]
    [switch]
    $NoReboot,

    [Parameter()]
    [switch]
    $PassThru
)

begin {
    ### FUNCTIONS ###
    #region

    # import the libraries in this order
    . "$PSScriptRoot\lib\libLogging.ps1"
    . "$PSScriptRoot\lib\libFunction.ps1"
    . "$PSScriptRoot\lib\libGlobal.ps1" 
    . "$PSScriptRoot\lib\libClass.ps1"

    # create the log file
    $null = mkdir $lPath -Force -EA SilentlyContinue

    $lName = "$script:lNameRoot`_$(timestamp -FileStamp)`.log"
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

    log "Start-HVUpdate - Begin"
    #endregion

    # check modules
    $null = Update-RequiredModules

    # make sure the $script:VmConfDir dir is created
    if ( -NOT (Test-Path "$script:VmConfDir" -EA SilentlyContinue) ) {
        $null = mkdir $script:VmConfDir -EA SilentlyContinue
    }

    # get HVUpdate file, or create if missing
    $setFile = Get-Item "$script:VmConf" -EA SilentlyContinue
    if ($setFile) {
        log "Start-HVUpdate - Reading config list."
        [List[Object]]$hvSettings = Get-Content "$script:VmConf" -EA SilentlyContinue | ConvertFrom-Json
    } else {
        log "Start-HVUpdate - Creating a new config list."
        $hvSettings = [List[Object]]::new()
    }

    # get a list of VMs on the host
    log "Start-HVUpdate - Getting all VMs."
    $allVMs = Get-VM
}

process {
    log "Start-HVUpdate - Process"
    log "Start-HVUpdate - Looping through VMs to add the HVUpdateVM object to each setting."

    foreach ( $VM in $allVMs ) {
        log "Start-HVUpdate - VM: $($VM.Name)"
        # check if the VM is listed in settings, or create a new setting
        if ( $VM.Name -notin $hvSettings.VMName ) {
            log "Start-HVUpdate - Creating new setting for $($VM.Name)using defaults."
            $set = New-HVUpdateConfElement
            $set.VMName = $VM.Name
            log "Start-HVUpdate - New setting for $($VM.Name):`n`n$($set | Format-List | Out-String)"
            $hvSettings += $set
        }

        # get the index number of the VM in the hvSettings array
        [scriptblock]$sbFindIdx = { 
            param ($obj)

            return ($VM.Name.Equals("$($obj.VMName)"))
        }
        $setIdx = $hvSettings.FindIndex($sbFindIdx)
        log "Start-HVUpdate - setIdx: $setIdx"

        # run the VM update if allowed
        if ( $setIdx -ge 0 ) {
            # get the VM state
            $hvSettings[$setIdx].VMState = $vm.State.ToString()

            # add the VM to the setting structure
            if ( [string]::IsNullOrEmpty( $hvSettings[$setIdx].SecretName ) ) {
                $hvSettings[$setIdx].HVUpdateVM = [HVUpdateVM]::new($VM, $true)
            } else {
                $hvSettings[$setIdx].HVUpdateVM = [HVUpdateVM]::new($VM, $hvSettings[$setIdx].SecretName, $true)
            }
            
            log "Start-HVUpdate - Current VM setting state:`n$($hvSettings[$setIdx] | Format-List | Out-String)`n"
        } else {
            log "Start-HVUpdate - Critical failure. Failed to find or create a setting object for the VM ($($VM.Name))."
            return
        }
    }

    log "Start-HVUpdate - hvSettings:`n$($hvSettings | Format-List | Out-String)"

    [List[Object]]$running = $hvSettings | Where-Object { $_.VMState -eq "Running" -and $_.Exclude -eq $false }
    [List[Object]]$notRunning = $hvSettings | Where-Object { $_.VMState -ne "Running" -and $_.Exclude -eq $false -and $_.TempSkip -eq $false }  

    log "Start-HVUpdate - running: $($running.VMName -join ', ')"
    log "Start-HVUpdate - notrunning: $($notrunning.VMName -join ', ')"

    if ($running.Count -gt 0) {
        log "Start-HVUpdate - Startng updates on running VMs. Running count: $($running.Count)"
        foreach ($VM in $running) {
            if ( -NOT $VM.Exclude ) {
                log "Start-HVUpdate - Starting updates on $($VM.VMName)."
                $null = $VM.HVUpdateVM.UpdateVM()
            } else {
                log "Start-HVUpdate - $($VM.VMName) is on the exclude list. Updates will not be performed."
            }
        }

        log "Start-HVUpdate - Waiting for the update jobs to end."

        do {
            # take a nap
            Start-Sleep 10
            $allDone = $true

            foreach ($uvm in $running) {
                if ( $uvm.HVUpdateVM.Status -eq "Running" ) {
                    if ( $uvm.HVUpdateVM.IsJobComplete() ) {
                        log "Start-HVUpdate - Update for $($uvm.VMName) completed."

                        # make sure the settings are up-to-date
                        if ( $uvm.OSFamily -ne $uvm.HVUpdateVM.GetOSFamily() ) {
                            log "Start-HVUpdate - Updating $($uvm.VMName) OSFamily to $($uvm.HVUpdateVM.OS)."
                            $uvm.OSFamily = $uvm.HVUpdateVM.GetOSFamily()
                        }
            
                        if ( $uvm.SecretName -ne $uvm.HVUpdateVM.GetSecretName() ) {
                            log "Start-HVUpdate - Updating $($uvm.VMName) SecretName to $($uvm.HVUpdateVM.SecretName)."
                            $uvm.SecretName = $uvm.HVUpdateVM.GetSecretName() 
                        }
            
                        log "Start-HVUpdate - Updating $($uvm.VMName) LastUpdate time."
                        $uvm.LastUpdate = Get-Date

                        # reboot?
                        log "Start-HVUpdate - Checking reboot on $($uvm.VMName)."
                        $null = $uvm.HVUpdateVM.RebootIfRequired()
                    } else {
                        log "Start-HVUpdate - $($uvm.VMName) is still updating. Waiting another minute."
                        $allDone = $false
                    }
                }
            }
        } until ( $allDone )
        log "Start-HVUpdate - Completed updates on running VMs."
    }

    if ($notrunning.Count -gt 0) {
        log "Start-HVUpdate - Starting updates on not running VMs. Not running count: $($notrunning.Count)"
        # start and update systems that are not running
        $activeUpdates = [List[Object]]::new()
        foreach ($VM in $notRunning) {
            if ( $VM.Exclude ) {
                log "Start-HVUpdate - $($VM.VMName) is on the exclude list. VM will not be started. Updates will not be performed."
                continue
            }

            # start the VM if the state is not running
            # [enum]::GetNames([Microsoft.HyperV.Powershell.VMState])
            switch -Regex ( $VM.VMState ) {
                "Paused" {
                    log "Start-HVUpdate - Resuming $($VM.VMName) from a Paused state for upgrades."
                    try {
                        Resume-VM -VM $VM.HVUpdateVM.VM -EA Stop
                    } catch {
                        log "Start-HVUpdate - Failed to Resume the VM: $_"
                        $VM.HVUpdateVM.SetError("VM_FAILED_TO_RESUME")
                        $VM.HVUpdateVM.SetResult($_)
                        $VM.TempSkip = $true
                    }
                }

                "Running" {
                    log "Start-HVUpdate - $($VM.VMName) is running."
                }

                "Off|Saved" {
                    log "Start-HVUpdate - Starting $($VM.VMName) from an $($VM.VMState) state for upgrades."
                    try {
                        Start-VM -VM $VM.HVUpdateVM.VM -EA Stop
                    } catch {
                        log "Start-HVUpdate - Failed to Start the VM: $_"
                        $VM.HVUpdateVM.SetError("VM_FAILED_TO_START")
                        $VM.HVUpdateVM.SetResult($_)
                        $VM.TempSkip = $true
                    }
                }

                "Stopping|Starting" {
                    log "Start-HVUpdate - $($VM.VMName) is currently $($VM.VMState). There may be an issue with the VM. Please try again once the VM has returned to a supported state (Off, Running, Paused, Saved)."
                    $VM.HVUpdateVM.SetError("VM_INVALID_STATE_$($VM.VMState.ToUpper())")
                    $VM.HVUpdateVM.SetResult("$($VM.VMName) is currently $($VM.VMState). There may be an issue with the VM. Please try again once the VM has returned to a supported state (Off, Running, Paused, Saved).")
                    $VM.TempSkip = $true
                    continue
                }

                "^.*Critical$" {
                    log "Start-HVUpdate - $($VM.VMName) is currently in a Critical state: $($VM.VMState). Please try again once the VM is no longer in a critical state."
                    $VM.HVUpdateVM.SetError("VM_INVALID_STATE_$($VM.VMState.ToUpper())")
                    $VM.HVUpdateVM.SetResult("$($VM.VMName) is currently in a Critical state: $($VM.VMState). Please try again once the VM is no longer in a critical state.")
                    $VM.TempSkip = $true
                    continue
                }

                default {
                    log "Start-HVUpdate - $($VM.VMName) is currently in an unsupported state ($($VM.VMState)). Please try again once the VM has returned to a supported state (Off, Running, Paused, Saved)."
                    $VM.HVUpdateVM.SetError("VM_INVALID_STATE_$($VM.VMState.ToUpper())")
                    $VM.HVUpdateVM.SetResult("$($VM.VMName) is currently in an unsupported state ($($VM.VMState)). Please try again once the VM has returned to a supported state (Off, Running, Paused, Saved).")
                    $VM.TempSkip = $true
                    continue
                }
            }

            # wait for an IP address, which indicates that the VM is operational, or 1 minutes
            $sw = [System.Diagnostics.Stopwatch]::new()
            do {
                Start-Sleep -m 500
            } until ( ($VM.HVUpdateVM.VM | Get-VMNetworkAdapter | Foreach-Object { $_.IPAddresses }) -or $sw.Elapsed.TotalMinutes -gt 1 )

            $sw.Stop()

            if ($sw.Elapsed.TotalMinutes -gt 5) {
                log "Start-HVUpdate - Resuming $($VM.VMName) took more than five minutes. There may be an issue with the VM or the host."
                continue
            } else {
                log "Start-HVUpdate - $($VM.VMName) has been resumed or started."
            }

            # start the update
            log "Start-HVUpdate - Starting the update."
            $activeUpdates.Add($VM)
            $null = $VM.HVUpdateVM.UpdateVM()

            # wait until the active updates drop below the throttle limit
            $numRunPend = $notRunning | Where-Object { ($_.HVUpdateVM.Status -eq "Running" -or $_.HVUpdateVM.Status -eq "Pending") -and $_.Exclude -eq $false -and $_.TempSkip -eq $false }
            log "Start-HVUpdate - numRunPend: $($numRunPend.Count)"
            if ($activeUpdates.Count -lt $StartupThrottleLimit -and $numRunPend.Count -gt ($StartupThrottleLimit - 1)) {
                log "Start-HVUpdate - Throttle limit not reached. Starting new update. $($activeUpdates.Count) of $StartupThrottleLimit jobs running."
                continue
            }

            if ($numRunPend.Count -lt $StartupThrottleLimit) {
                log "Start-HVUpdate - Processing final update(s)."
            } else {
                log "Start-HVUpdate - Throttle limit reached. Waiting for one or more update to complete."    
            }

            do {
                # take a nap
                Start-Sleep 10

                $completed = [List[Object]]::new()
                foreach ($uvm in $activeUpdates) {
                    if ( $uvm.HVUpdateVM.IsJobComplete() ) {
                        # mark the job for removal... you can't remove the entry while using the entry in a loop             
                        $null = $completed.Add($uvm)
                        log "Start-HVUpdate - Update for $($uvm.VMName) completed."

                        # is reboot required
                        if ($uvm.HVUpdateVM.RebootRequired) {
                            # reboot?
                            log "Start-HVUpdate - Checking reboot on $($uvm.VMName)."
                            $null = $uvm.HVUpdateVM.RebootIfRequired()

                            # sleep for 60 seconds for the reboot to trigger and get underway
                            Start-Sleep 60

                            # wait for an IP address, which indicates that the VM is operational, or 5 minutes
                            $sw = [System.Diagnostics.Stopwatch]::new()
                            do {
                                Start-Sleep -m 500
                            } until ( ($VM.HVUpdateVM.VM | Get-VMNetworkAdapter | Foreach-Object { $_.IPAddresses }) -or $sw.Elapsed.TotalMinutes -gt 5 )

                            $sw.Stop()

                            # at this point simply try to return the VM to its original state
                            # I may need better logic here in the future for slow to update VMs
                        }

                        # return the VM to previous state
                        # [enum]::GetNames([Microsoft.HyperV.Powershell.VMState])
                        switch -Regex ( $uvm.VMState ) {
                            "Paused" {
                                log "Start-HVUpdate - Suspending (Pause) $($uvm.VMName)."
                                try {
                                    $null = Suspend-VM -VM $uvm.HVUpdateVM.VM -EA Stop
                                } catch {
                                    log "Start-HVUpdate - Failed to Suspend the VM: $_"
                                    $uvm.HVUpdateVM.SetError("VM_FAILED_TO_SUSPEND")
                                    $uvm.HVUpdateVM.SetResult($_)
                                }
                            }

                            "Off" {
                                log "Start-HVUpdate - Shutting down $($uvm.VMName)."
                                try {
                                    $null = Stop-VM -VM $uvm.HVUpdateVM.VM -Force -EA Stop
                                } catch {
                                    log "Start-HVUpdate - Failed to Stop the VM: $_"
                                    $uvm.HVUpdateVM.SetError("VM_FAILED_TO_SHUTDOWN")
                                    $uvm.HVUpdateVM.SetResult($_)
                                }
                            }
                            
                            "Saved" {
                                log "Start-HVUpdate - Saving $($uvm.VMName)."
                                try {
                                    $null = Save-VM -VM $uvm.HVUpdateVM.VM -Force -EA Stop
                                } catch {
                                    log "Start-HVUpdate - Failed to Save the VM: $_"
                                    $uvm.HVUpdateVM.SetError("VM_FAILED_TO_SAVE")
                                    $uvm.HVUpdateVM.SetResult($_)
                                }
                            }

                            default {
                                log "Start-HVUpdate - You should not be here. $($VM.VMName) is currently in an unsupported state ($($VM.VMState))."
                            }
                        }

                        # make sure the settings are up-to-date
                        if ( $uvm.OSFamily -ne $uvm.HVUpdateVM.GetOSFamily() ) {
                            log "Start-HVUpdate - Updating $($uvm.VMName) OSFamily to $($uvm.HVUpdateVM.OS)."
                            $uvm.OSFamily = $uvm.HVUpdateVM.GetOSFamily()
                        }
            
                        if ( $uvm.SecretName -ne $uvm.HVUpdateVM.GetSecretName() ) {
                            log "Start-HVUpdate - Updating $($uvm.VMName) SecretName to $($uvm.HVUpdateVM.SecretName)."
                            $uvm.SecretName = $uvm.HVUpdateVM.GetSecretName() 
                        }
            
                        log "Start-HVUpdate - Updating $($uvm.VMName) LastUpdate time."
                        $uvm.LastUpdate = Get-Date
                    } else {
                        log "Start-HVUpdate - $($uvm.VMName) is still updating. Waiting another minute."
                    }
                }

                # remove indexes
                if ($completed.Count -gt 0) {
                    $completed | ForEach-Object {
                        log "Start-HVUpdate - Removing completed update for: $($_.VMName)"
                        $null = $activeUpdates.Remove($_)
                        log "Start-HVUpdate - Active updates: $($activeUpdates.Count)"
                    }
                }

                # update number of running or pending
                $numRunPend = $notRunning | Where-Object { ($_.HVUpdateVM.Status -eq "Running" -or $_.HVUpdateVM.Status -eq "Pending") -and $_.Exclude -eq $false -and $_.TempSkip -eq $false }

                # account for a single update remaining
                if ($activeUpdates.Count -gt 1 -and $numRunPend.Count -eq 1) {
                    $allDone = $false
                # account for 1 update running but more updates are in queue, go start another update
                } elseif ($activeUpdates.Count -eq 1 -and $numRunPend.Count -gt 1) {
                    $allDone = $true
                # loop when all updates are done
                } elseif ($activeUpdates.Count -eq 0) {
                    $allDone = $true
                # try one more loop if none of the above are met
                } else {
                    $allDone = $false
                }

            } until ( $allDone )

            log "Start-HVUpdate - End Not Running loop."
        }
    }
}

clean {

}

end {
    log "Start-HVUpdate - End"
    # save the settings file
    log "Start-HVUpdate - Updating settings file: $script:VmConf"
    $hvSettings | Select-Object -Property VMName,SecretName,OSFamily,LastUpdate,VMState,TempSkip,Exclude,NoReboot,@{Label="HVUpdateVM"; Expression={$null}} | ConvertTo-Json | Out-File "$script:VmConf" -Force

    if ($PassThru.IsPresent) {
        log "Start-HVUpdate - Passing through update results."
        log "Start-HVUpdate - Work complete!"
        return $hvSettings
    }
}