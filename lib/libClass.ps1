<#
    CLASS   : HVUpdateVM
    PURPOSE : Manages the WU process on a host VM.

    Constructor:
    
    Constructs class with just the VM object. Credentials are auto discovered.
    [HVUpdateVM]::new([Microsoft.HyperV.PowerShell.VirtualMachine]$VM)

    Constructs class with the VM object and enforces a specific credential. Will return a terminating error if the credential fails to work.
    [HVUpdateVM]::new([Microsoft.HyperV.PowerShell.VirtualMachine]$VM, [string]$SecretName)


    The other libraries must be loaded. The class depends on libGlobals and libFunction specifically being loaded and the Script scope variables being loaded.
#>

#requires -Module "ThreadJob"

using namespace System.Collections
using namespace System.Collections.Generic

enum HVUpdateStatus {
    Pending
    Running
    Completed
    Error
}

enum HVUpdateWriteType {
    Force
    Append
}

enum HVUpdateOperatingSystem {
    Unknown
    Windows
    Debian
    Fedora
}

enum DebianBasedDistros {
    MX
    Mint
    Ubuntu
    Kali
    Debian
    Zorin
    Pop
    Parrot 
    Deepin
    Elementary
    BunsenLabs
    Peppermint
    Kaisen
    Raspberry
    BOSS
    SolydXK
    Nitrux
    PureOS
    Tails
    Grml
    Q4OS
    Sparky
    Devuan
    Bodhi
}


enum FedoraBasedDistros {
    Fedora
    CentOS
    Oracle
    Rocky
    Scientific
    ClearOS
    Endless
    Korora
    PUIAS
    Spins
    Nobara
    Ultramarine
    Risi
    Qubes
    Berry
    Clear
    Alma
}


class HVUpdateVM {
    # $this.AddLog("[HVUpdateVM] - ")

    ### PROPERTIES ###
    #region
    $VM

    [HVUpdateOperatingSystem]
    $OS
    
    [string]
    $SecretName

    [System.Management.Automation.PSCredential]
    hidden
    $Credential

    [hashtable]
    hidden
    $SSHParameters

    # The status of the command.
    [HVUpdateStatus]
    $Status

    # is a reboot required?
    [bool]
    $RebootRequired

    # error or success codes go here.
    [string]
    hidden
    $StatusCode

    # The name of the threadjob that executes the command.
    [string]
    hidden
    $JobName

    # The job object
    hidden
    $Job

    # run the script as a job
    [bool]
    $AsJob

    # The result of the job, as an Object list, as retrieved by Receive-Job.
    [List[Object]]
    hidden
    $Result

    # The PSSession name
    [string]
    hidden
    $SessionName

    # PSSession object
    #[]
    hidden
    $Session

    [int]
    hidden
    $ThrottleLimit

    # Logged events.
    [List[string]]
    hidden
    $Log
    #endregion

    ### CONSTRUCTORS ###
    #region

    # constructors without AsJob. Default = $false
    HVUpdateVM() {
        $this.AddLog("[HVUpdateVM] - Initialize empty class object.")
        $this.VM          = $null
        $this.OS          = "Unknown"
        $this.SecretName  = $null
        $this.Credential  = $null
        $this.SSHParameters = $null
        $this.SetPending()
        $this.RebootRequired = $null
        $this.StatusCode  = $null
        $this.JobName     = "UW_Job_$($this.GetRandChar(8))"
        $this.AddLog("[HVUpdateVM] - JobName: $($this.JobName)")
        $this.Job         = $null
        $this.AsJob       = $false
        $this.Result      = $null
        $this.SessionName = "UW_Session_$($this.GetRandChar(8))"
        $this.AddLog("[HVUpdateVM] - SessionName: $($this.SessionName)")
        $this.Session     = $null
        $this.ThrottleLimit = 3
        $this.AddLog("[HVUpdateVM] - Class initialized.")
    }


    HVUpdateVM($VM) {
        $this.AddLog("[HVUpdateVM] - Initialize class with VM object.")
        $this.AddLog("[HVUpdateVM] - VM name: $($VM.Name)")
        $this.VM          = $this.ValidateVM($VM)
        $this.OS          = "Unknown"
        $this.AddLog("[HVUpdateVM] - VM validated: $(if ($null -eq $this.VM) {$false} else {$true})")
        $this.AddLog("[HVUpdateVM] - All other values are null.")
        $this.SecretName  = $null
        $this.Credential  = $null
        $this.SetPending()
        $this.RebootRequired = $null
        $this.StatusCode  = $null
        $this.JobName     = "UW_Job_$($this.GetRandChar(8))"
        $this.AddLog("[HVUpdateVM] - JobName: $($this.JobName)")
        $this.Job         = $null
        $this.AsJob       = $false
        $this.Result      = $null
        $this.SessionName = "UW_Session_$($this.GetRandChar(8))"
        $this.AddLog("[HVUpdateVM] - SessionName: $($this.SessionName)")
        $this.Session     = $null
        $this.AddLog("[HVUpdateVM] - Class initialized.")
    }

    HVUpdateVM( $VM,
                [string]$SecretName) {
        $this.AddLog("[HVUpdateVM] - Initialize class with VM object and a secret name.")
        $this.AddLog("[HVUpdateVM] - VM name: $($VM.Name)")
        $this.VM          = $this.ValidateVM($VM)
        $this.OS          = "Unknown"
        $this.AddLog("[HVUpdateVM] - VM validated: $(if ($null -eq $this.VM) {$false} else {$true})")
        $this.AddLog("[HVUpdateVM] - Secret name: $SecretName")
        $this.SecretName  = $this.ValidateSecretName($SecretName)
        $this.AddLog("[HVUpdateVM] - Secret validated: $(if ($null -eq $this.SecretName) {$false} else {$true})")
        $this.Credential  = $null
        $this.SSHParameters = $null
        $this.SetPending()
        $this.RebootRequired = $null
        $this.StatusCode  = $null
        $this.JobName     = "UW_Job_$($this.GetRandChar(8))"
        $this.AddLog("[HVUpdateVM] - JobName: $($this.JobName)")
        $this.Job         = $null
        $this.AsJob       = $false
        $this.Result      = $null
        $this.SessionName = "UW_Session_$($this.GetRandChar(8))"
        $this.AddLog("[HVUpdateVM] - SessionName: $($this.SessionName)")
        $this.Session     = $null
        $this.ThrottleLimit = 3
        $this.AddLog("[HVUpdateVM] - Class initialized.")
    }
    

    # constructors with AsJob.
    HVUpdateVM($VM, [bool]$AsJob) {
        $this.AddLog("[HVUpdateVM] - Initialize class with VM object.")
        $this.AddLog("[HVUpdateVM] - VM name: $($VM.Name)")
        $this.VM          = $this.ValidateVM($VM)
        $this.OS          = "Unknown"
        $this.AddLog("[HVUpdateVM] - VM validated: $(if ($null -eq $this.VM) {$false} else {$true})")
        $this.AddLog("[HVUpdateVM] - All other values are null.")
        $this.SecretName  = $null
        $this.Credential  = $null
        $this.SSHParameters = $null
        $this.SetPending()
        $this.RebootRequired = $null
        $this.StatusCode  = $null
        $this.JobName     = "UW_Job_$($this.GetRandChar(8))"
        $this.AddLog("[HVUpdateVM] - JobName: $($this.JobName)")
        $this.Job         = $null
        $this.AddLog("[HVUpdateVM] - AsJob: $AsJob")
        $this.AsJob       = $AsJob
        $this.Result      = $null
        $this.SessionName = "UW_Session_$($this.GetRandChar(8))"
        $this.AddLog("[HVUpdateVM] - SessionName: $($this.SessionName)")
        $this.Session     = $null
        $this.ThrottleLimit = 3
        $this.AddLog("[HVUpdateVM] - Class initialized.")
    }

    HVUpdateVM( $VM,
                [string]$SecretName,
                [bool]$AsJob) {
        $this.AddLog("[HVUpdateVM] - Initialize class with VM object and a secret name.")
        $this.AddLog("[HVUpdateVM] - VM name: $($VM.Name)")
        $this.VM          = $this.ValidateVM($VM)
        $this.OS          = "Unknown"
        $this.AddLog("[HVUpdateVM] - VM validated: $(if ($null -eq $this.VM) {$false} else {$true})")
        $this.AddLog("[HVUpdateVM] - Secret name: $SecretName")
        $this.SecretName  = $this.ValidateSecretName($SecretName)
        $this.AddLog("[HVUpdateVM] - Secret validated: $(if ($null -eq $this.SecretName) {$false} else {$true})")
        $this.Credential  = $null
        $this.SSHParameters = $null
        $this.SetPending()
        $this.RebootRequired = $null
        $this.StatusCode  = $null
        $this.JobName     = "UW_Job_$($this.GetRandChar(8))"
        $this.AddLog("[HVUpdateVM] - JobName: $($this.JobName)")
        $this.Job         = $null
        $this.AddLog("[HVUpdateVM] - AsJob: $AsJob")
        $this.AsJob       = $AsJob
        $this.Result      = $null
        $this.SessionName = "UW_Session_$($this.GetRandChar(8))"
        $this.AddLog("[HVUpdateVM] - SessionName: $($this.SessionName)")
        $this.Session     = $null
        $this.ThrottleLimit = 3
        $this.AddLog("[HVUpdateVM] - Class initialized.")
    }

    #endregion

    ### FUNCTIONS ###
    #region FUNCTIONS
    #region GETTERS and SETTERS
    ## Getters ##
    # property getters
    [string]GetVM()             { return ($this.VM) }
    [string]GetSecretName()     { return ($this.SecretName) }
    [string]GetCredential()     { return ($this.Credential) }
    [string]GetStatus()         { return ($this.Status) }
    [string]GetStatusCode()     { return ($this.StatusCode) }
    [string]GetJobName()        { return ($this.JobName) }
    [string]GetJob()            { return ($this.Job) }
    [List[Object]]GetResult()   { return ($this.Result) }
    [List[Object]]GetLog()      { return ($this.Log) }
    [int]GetThrottleLimit()       { return ($this.ThrottleLimit) }

    [string]
    GetJobState() {
        if ($this.Job) {
            $this.AddLog("[HVUpdateVM].GetJobState - Job state: $($this.Job.State)")
            return $this.Job.State
        } else {
            $this.AddLog("[HVUpdateVM].GetJobState - No job found.")
            return $null
        }
    }

    [string]
    GetScriptLog() {
        $this.AddLog("[HVUpdateVM].GetScriptLog - Begin")
        $connected = $this.ConnectToVM()

        if ( -NOT $connected ) {
            $this.AddLog("[HVUpdateVM].GetScriptLog - Unable to connect to the VM.")
            return $null
        }

        [scriptblock] $sbGetLog = {
            $dir = "C:\Scripts\UpdateWindows\Logs"
            $newest = Get-ChildItem "$dir" -Filter "Update-Windows_*.log" | Sort-Object -Descending | Select-Object -First 1
            [System.Collections.Generic.List[string]]$logs = Get-Content "$($newest.FullName)" -Delimiter "`n" | ForEach-Object { $_.Trim(' ') }
            return $logs
        }

        $this.AddLog("[HVUpdateVM].GetScriptLog - Getting newest script log.")
        [List[string]]$scriptLog = Invoke-Command -Session $this.Session -ScriptBlock $sbGetLog
        $this.AddLog("[HVUpdateVM].GetScriptLog - scriptLog:`n$scriptLog")

        if ( -NOT $this.IsJobRunning() ) {
            $this.AddLog("[HVUpdateVM].GetScriptLog - No job running, disconnect from VM.")
            $this.DisconnectFromVM()
        }

        $this.AddLog("[HVUpdateVM].GetScriptLog - End")
        return $scriptLog
    }

    [bool]
    IsJobComplete() {
        if ($this.Job) {
            $this.AddLog("[HVUpdateVM].IsJobComplete - Job state: $($this.Job.State)")
            if ($this.Job.State -eq "Completed" -or $this.Job.State -eq "Failed") {
                # update the class status
                $this.UpdateJob()
                return $true
            } else {
                return $false
            }
        } else {
            $this.AddLog("[HVUpdateVM].IsJobComplete - No job found. Returning True to prevent infinite loops on job waiters.")
            return $true
        }
    }

    [bool]
    IsJobRunning() {
        if ($this.Job) {
            $this.AddLog("[HVUpdateVM].IsJobRunning - Job state: $($this.Job.State)")
            if ($this.Job.State -eq "Running") {
                return $true
            } else {
                return $false
            }
        } else {
            $this.AddLog("[HVUpdateVM].IsJobRunning - No job found.")
            return $false
        }
    }

    [string]
    GetOSFamily() {
        return $this.OS.ToString()
    }

    ## Setters ##
    # property setters
    SetVM($VM) { 
        $this.AddLog("[HVUpdateVM].SetVM - SetVM: $($VM.Name)")
        $this.VM =  $this.ValidateVM($VM)
        $this.AddLog("[HVUpdateVM].SetVM - Validated result: $($this.VM.Name)")
    }

    SetCredentialName([string]$SecretName) {
        $this.AddLog("[HVUpdateVM].SetCredentialName - SetCredentialName: $SecretName")
        $this.SecretName = $this.ValidateSecretName($SecretName)
        $this.AddLog("[HVUpdateVM].SetCredentialName - Validated result: $($this.SecretName)")
    }

    SetSSHParameter(
        [string]$HostName,
        [string]$KeyFilePath
    ) {
        $this.AddLog("[HVUpdateVM].SetSSHParameter - HostName: $HostName")
        $this.AddLog("[HVUpdateVM].SetSSHParameter - KeyFilePath: $KeyFilePath")

        # prevents saving the parameter if validation fails
        $skippy = $false
        
        if ( [string]::IsNullOrEmpty( $HostName ) ) {
            $this.AddLog("[HVUpdateVM].SetSSHParameter - HostName is null or empty.")
            Write-Error "Invalid hostname. The hostname is null or empty."
            $skippy = $true
        }

        if ( [string]::IsNullOrEmpty( $HostName ) ) {
            $this.AddLog("[HVUpdateVM].SetSSHParameter - HostName is null or empty.")
            Write-Error "Invalid hostname. The hostname is null or empty."
            $skippy = $true
        }

        if ( -NOT $skippy ) {
            [hashtable]$table = @{
                KeyFilePath = $KeyFilePath
                HostName    = $HostName
            }

            $this.AddLog("[HVUpdateVM].SetSSHParameter - table: $table")
            $this.SSHParameters = $table
            $this.AddLog("[HVUpdateVM].SetSSHParameter - SSHParameters updated.")
        } else {
            $this.AddLog("[HVUpdateVM].SetSSHParameter - Failed to update SSHParameters.")
        }
    }

    SetThrottleLimit([int]$tl) { 
        $this.ThrottleLimit = $tl
    }

    hidden 
    SetError ([string]$code) {
        $this.Status = "Error"
        $this.AddLog("[HVUpdateVM].SetError - Code: $code")
        $this.StatusCode = $code
    }

    hidden 
    SetPending() {
        $this.Status = "Pending"
        $this.AddLog("[HVUpdateVM].SetPending() - Code: STATUS_PENDING")
        $this.StatusCode = "STATUS_PENDING"
    }

    hidden 
    SetRunning() {
        $this.Status = "Running"
        $this.AddLog("[HVUpdateVM].SetRunning() - Code: STATUS_RUNNING")
        $this.StatusCode = "STATUS_RUNNING"
    }

    hidden 
    SetResult([string]$result) {
        $this.AddLog("[HVUpdateVM].SetRunning() - Result:`n$result`n")
        $this.Result = $result
    }

    hidden 
    SetCompleted() {
        $this.Status = "Completed"
        $this.AddLog("[HVUpdateVM].SetCompleted() - Code: STATUS_SUCCESS")
        $this.StatusCode = "STATUS_SUCCESS"
    }

    hidden 
    SetCompleted ([string]$code) {
        $this.Status = "Completed"
        $this.AddLog("[HVUpdateVM].SetCompleted(1) - Code: $code")
        $this.StatusCode = $code
    }
    #endregion GETTERS and SETTERS

    ## VALIDATORS ##
    #region
    
    [object]
    ValidateVM($VM) {
        $this.AddLog("[HVUpdateVM].ValidateVM - Begin")
        $this.AddLog("[HVUpdateVM].ValidateVM - Validating $($VM.Name)")
        # get list of VMs on the host
        $this.AddLog("[HVUpdateVM].ValidateVM - Try to resolve the VM object.")
        if ( $VM -is [string]) {
            $this.AddLog("[HVUpdateVM].ValidateVM - Resolving VM with a string name.")
            $vmObj = Get-VM -Name $VM -EA SilentlyContinue
        } elseif ( $VM.GetType().Name -eq "VirtualMachine" ) {
            $this.AddLog("[HVUpdateVM].ValidateVM - Resolving VM as a VirtualMachine object.")
            $vmObj = Get-VM -Name $VM.Name
        } else {
            $this.AddLog("[HVUpdateVM].ValidateVM - Invalid VM type:`n$($VM | Format-List | Out-String)`n")
            $this.SetError("INVALID_VM_OBJECT")
            return $null
        }

        # add the VM if it is in the list, otherwise set error.
        if ( $vmObj ) {
            $this.AddLog("[HVUpdateVM].ValidateVM - $($vmObj.Name) was found.")
            $this.AddLog("[HVUpdateVM].ValidateVM - End")
            return $vmObj 
        } else {
            $this.AddLog("[HVUpdateVM].ValidateVM - $($VM.Name) was NOT found.")
            $this.SetError("VM_NOT_FOUND")
            $this.AddLog("[HVUpdateVM].ValidateVM - End")
            return $null
        }
    }

    [string]
    ValidateSecretName([string]$secretName) {
        # get list of secrets in the vault
        $this.AddLog("[HVUpdateVM].ValidateSecretName - Begin")
        $this.AddLog("[HVUpdateVM].ValidateSecretName - Validating secret: $secretName")

        # unlock the vault
        $this.AddLog("[HVUpdateVM].ValidateSecretName - Unlocking vault.")
        Unlock-SecretStore -Password $script:VaultPassword

        # this only works when libGlobal has been imported
        $this.AddLog("[HVUpdateVM].ValidateSecretName - Getting all secrets in $script:VaultName secrets.")
        $secrets = Get-SecretInfo -Name * -Vault $script:VaultName
        $this.AddLog("[HVUpdateVM].ValidateSecretName - Number of secrets found: $($secrets.Count)")

        # add the VM if it is in the list, otherwise set error.
        if ( $secretName -in $secrets.Name ) {
            $this.AddLog("[HVUpdateVM].ValidateSecretName - $SecretName was found.")
            $this.AddLog("[HVUpdateVM].ValidateSecretName - End")
            return $secretName
        } else {
            $this.AddLog("[HVUpdateVM].ValidateSecretName - $SecretName was NOT found.")
            $this.SetError("SECRET_NOT_FOUND")
            $this.AddLog("[HVUpdateVM].ValidateSecretName - End")
            return $null
        }
    }

    [string]
    ValidateOSFamily() {
        [HVUpdateOperatingSystem]$family = "Windows"


        return $family
    }

    #endregion

    ## WORKERS ##
    #region

    [bool]
    UpdateVM() {
        $this.AddLog("[HVUpdateVM].UpdateVM - Begin")
        $this.SetRunning()

        # make sure a connection to the VM is possible
        $this.AddLog("[HVUpdateVM].UpdateVM - Test VM connection.")
        $canConnect = $this.TestVMConnection()

        if ( -NOT $canConnect) {
            $this.AddLog("[HVUpdateVM].UpdateVM - End")
            return $false
        }

        $this.AddLog("[HVUpdateVM].UpdateVM - Can connect to the VM.")

        # establish the connection
        $connected = $this.ConnectToVM()

        if ( -NOT $connected) {
            $this.AddLog("[HVUpdateVM].UpdateVM - End")
            return $false
        }

        $this.AddLog("[HVUpdateVM].UpdateVM - VM PowerShell Remoting session is connected.")

        # copy the update script, if needed.
        if ( $this.OS -eq "Windows" ) {
            $scriptCopied = $this.CopyScript()

            if ( -NOT $scriptCopied) {
                $this.DisconnectFromVM()
                $this.AddLog("[HVUpdateVM].UpdateVM - End")
                return $false
            }

            $this.AddLog("[HVUpdateVM].UpdateVM - Update-Windows.ps1 has been copied.")
        }

        # update the VM as a thread job
        $updateVM = $this.InitScript()

        if ( -NOT $updateVM) {
            $this.DisconnectFromVM()
            $this.AddLog("[HVUpdateVM].UpdateVM - End")
            return $false
        }

        if ( -NOT $this.AsJob ) {
            $this.AddLog("[HVUpdateVM].UpdateVM - Update complete.")
            $this.DisconnectFromVM()
            $this.AddLog("[HVUpdateVM].UpdateVM - VM PD session disconnected.")
        }
        
        $this.AddLog("[HVUpdateVM].UpdateVM - End")
        return $true
    }

    [bool]
    TestVMConnection(){
        $this.AddLog("[HVUpdateVM].TestVMConnection - Begin")

        # PowerShell Direct is used to connect to VMs for Windows and unknown. This requires credentials.
        # SSH is used for Linux and alternate connection methods. This required a keyfile and a connection string.

        # unlock the vault
        Unlock-SecretStore -Password $script:VaultPassword

        $whoami = $null

        # try all secrets when none set
        # if any of these works the VM is running Windows
        if ( [string]::IsNullOrEmpty($this.SecretName) -and $null -eq $this.Credential -and ($this.OS -eq "Unknown" -or $this.OS -eq "Windows") ) {
            $secrets = Get-SecretInfo -Name * -Vault $script:VaultName | Where-Object Name -notmatch "KeyFile"
            $this.AddLog("[HVUpdateVM].TestVMConnection - Testing $($secrets.Count) secrets.")

            :secret foreach ( $secret in $secrets ) {
                $tmpCred = Get-Secret -Name $secret.Name -Vault $script:VaultName
                $this.AddLog("[HVUpdateVM].TestVMConnection - Testing: $($secret.Name)")

                try {
                    $this.AddLog("[HVUpdateVM].TestVMConnection - Getting computername.")
                    $whoami = Invoke-Command -VMId $this.VM.Id -Credential $tmpCred -ScriptBlock { $env:COMPUTERNAME } -EA Stop
                    $this.AddLog("[HVUpdateVM].TestVMConnection - whoami: $whoami")

                    # if the script reaches this then the whoami worked and we save the secretname and credential
                    $this.AddLog("[HVUpdateVM].TestVMConnection - Saving secret to class.")
                    $this.SecretName = $secret.Name
                    $this.AddLog("[HVUpdateVM].TestVMConnection - Saving credential to class.")
                    $this.Credential = $tmpCred
                    $this.AddLog("[HVUpdateVM].TestVMConnection - OS is Windows.")
                    $this.OS = "Windows"

                    # exit the loop
                    break secret
                }
                catch {
                    $this.AddLog("[HVUpdateVM].TestVMConnection - Could not connect with secret: $($secret.Name)")
                }
            }
        } elseif ( $this.Credential -and ($this.OS -eq "Unknown" -or $this.OS -eq "Windows") ) {
            $this.AddLog("[HVUpdateVM].TestVMConnection - Testing existing credential.")
            try {
                $this.AddLog("[HVUpdateVM].TestVMConnection - Getting computername.")
                $whoami = Invoke-Command -VMId $this.VM.Id -Credential $this.Credential -ScriptBlock { $env:COMPUTERNAME } -EA Stop
                $this.AddLog("[HVUpdateVM].TestVMConnection - whoami: $whoami")

                $this.AddLog("[HVUpdateVM].TestVMConnection - OS is Windows.")
                $this.OS = "Windows"
            }
            catch {
                $this.AddLog("[HVUpdateVM].TestVMConnection - Could not connect with class credential.")
                $whoami = $null
            }        
        } elseif ( -NOT [string]::IsNullOrEmpty($this.SecretName) -and ($this.OS -eq "Unknown" -or $this.OS -eq "Windows") ) {
            $this.AddLog("[HVUpdateVM].TestVMConnection - Testing existing secret.")
            $tmpCred = Get-Secret -Name $this.SecretName -Vault $script:VaultName -EA SilentlyContinue
            $this.AddLog("[HVUpdateVM].TestVMConnection - Testing: $($this.SecretName)")

            try {
                $this.AddLog("[HVUpdateVM].TestVMConnection - Getting computername.")
                $whoami = Invoke-Command -VMId $this.VM.Id -Credential $tmpCred -ScriptBlock { $env:COMPUTERNAME } -EA Stop
                $this.AddLog("[HVUpdateVM].TestVMConnection - whoami: $whoami")
                $this.AddLog("[HVUpdateVM].TestVMConnection - Saving credential to class.")
                $this.Credential = $tmpCred

                $this.AddLog("[HVUpdateVM].TestVMConnection - OS is Windows.")
                $this.OS = "Windows"
            }
            catch {
                $this.AddLog("[HVUpdateVM].TestVMConnection - Could not connect with class secret: $($this.SecretName)")
                $whoami = $null
            }   
        } else {
            $this.AddLog("[HVUpdateVM].TestVMConnection - WinRM connections failed. Will test SSH.")
            $whoami = $null
        }

        # try an SSH connection if WinRM fails.
        if ( -NOT $whoami ) {
            $this.AddLog("[HVUpdateVM].TestVMConnection - Performing SSH connection tests.")
            if ( [string]::IsNullOrEmpty($this.SecretName) -and $null -eq $this.Credential ) {
                $secrets = Get-SecretInfo -Name * -Vault $script:VaultName | Where-Object Name -match "KeyFile"
                $this.AddLog("[HVUpdateVM].TestVMConnection - Testing $($secrets.Count) secrets.")
    
                :secret foreach ( $secret in $secrets ) {
                    $tmpCred = Get-Secret -Name $secret.Name -Vault $script:VaultName -AsPlainText
                    $this.AddLog("[HVUpdateVM].TestVMConnection - Testing: $($secret.Name)")
    
                    try {
                        $this.AddLog("[HVUpdateVM].TestVMConnection - Getting distro details.")
                        $parameters = @{
                            KeyFilePath = $tmpCred
                            HostName    = $secret.Metadata.Values
                        }
                        
                        # ssh connections can be to Windows or Linux, so do some cross-platform PowerShell magic!
                        [scriptblock]$sbOsDetect = {
                            if ($IsWindows) {
                                return ([PSCustomObject]@{
                                    whoami = "$(whoami)"
                                    OS     = "Windows"
                                })
                            } elseif ($IsLinux) {
                                return ([PSCustomObject]@{
                                    whoami = "$(whoami)"
                                    OS     = "$(uname -a)"
                                })
                            } elseif ($IsMacOS) {
                                return ([PSCustomObject]@{
                                    whoami = "$(whoami)"
                                    OS     = "MacOS"
                                })
                            }

                        }

                        $results = Invoke-Command @parameters -ScriptBlock $sbOsDetect -ErrorAction Stop

                        $this.AddLog("[HVUpdateVM].TestVMConnection - results:`n$($results | Format-List | Out-String)`n")

                        $whoami = $results.whoami
    
                        # if the script reaches this then the whoami worked and we save the secretname and credential
                        $this.SecretName = $secret.Name
                        $this.AddLog("[HVUpdateVM].TestVMConnection - Saved secretName: $($this.SecretName)")

                        $this.SSHParameters = $parameters
                        $this.AddLog("[HVUpdateVM].TestVMConnection - Saving SSHParameters:`n$($this.SSHParameters | Format-Table | Out-String)`n")

                        # what distro family is this?
                        $rawOS = $results.OS
                        $this.AddLog("[HVUpdateVM].TestVMConnection - rawOS: $rawOS")
                        if ($rawOS -match "Windows") {
                            $this.OS = "Windows"
                            $this.AddLog("[HVUpdateVM].TestVMConnection - OS set to Windows family.")
                        } elseif ( ([DebianBasedDistros].GetEnumNames() | Where-Object { $rawOS -match $_ }) ) {
                            $this.OS = "Debian"
                            $this.AddLog("[HVUpdateVM].TestVMConnection - OS set to Debian family.")
                        } elseif ( ([FedoraBasedDistros].GetEnumNames() | Where-Object { $rawOS -match $_ }) ) {
                            $this.OS = "Fedora"
                            $this.AddLog("[HVUpdateVM].TestVMConnection - OS set to Fedora family.")
                        } elseif ($rawOS -match "macOS") {
                            $this.OS = "Unknown"
                            $this.AddLog("[HVUpdateVM].TestVMConnection - macOS is unsupport: $rawOS")
                        } elseif ( $rawOS -match "Arch" ) {
                            $this.OS = "Unknown"
                            $this.AddLog("[HVUpdateVM].TestVMConnection - Arch Linux is unsupport: $rawOS")
                        } else {
                            $this.OS = "Unknown"
                            $this.AddLog("[HVUpdateVM].TestVMConnection - OS family is unknown or unsupport: $rawOS")
                        }

                        $this.AddLog("[HVUpdateVM].TestVMConnection - OS is $($this.OS.ToString()).")
    
                        # exit the loop
                        break secret
                    }
                    catch {
                        $this.AddLog("[HVUpdateVM].TestVMConnection - Could not connect with secret: $($secret.Name)")
                    }        
                }       
            } elseif ( -NOT [string]::IsNullOrEmpty($this.SecretName) ) {
                $this.AddLog("[HVUpdateVM].TestVMConnection - Testing existing secret.")
                $tmpCred = Get-Secret -Name $this.SecretName -Vault $script:VaultName  -AsPlainText -EA SilentlyContinue
                $secret = Get-SecretInfo -Name $this.SecretName -Vault $script:VaultName
                $this.AddLog("[HVUpdateVM].TestVMConnection - Testing: $($this.SecretName)")
    
                try {
                    $this.AddLog("[HVUpdateVM].TestVMConnection - Getting distro details.")
                    $parameters = @{
                        KeyFilePath = $tmpCred
                        HostName    = $secret.Metadata.Values
                    }
                    
                    # ssh connections can be to Windows or Linux, so do some cross-platform PowerShell magic!
                    [scriptblock]$sbOsDetect = {
                        if ($IsWindows) {
                            return ([PSCustomObject]@{
                                whoami = "$(whoami)"
                                OS     = "Windows"
                            })
                        } elseif ($IsLinux) {
                            return ([PSCustomObject]@{
                                whoami = "$(whoami)"
                                OS     = "$(uname -a)"
                            })
                        } elseif ($IsMacOS) {
                            return ([PSCustomObject]@{
                                whoami = "$(whoami)"
                                OS     = "MacOS"
                            })
                        }

                    }

                    $results = Invoke-Command @parameters -ScriptBlock $sbOsDetect -ErrorAction Stop

                    $this.AddLog("[HVUpdateVM].TestVMConnection - results:`n$($results | Format-List | Out-String)`n")

                    $whoami = $results.whoami

                    # if the script reaches this then the whoami worked and we save the secretname and credential
                    $this.SecretName = $secret.Name
                    $this.AddLog("[HVUpdateVM].TestVMConnection - Saved secretName: $($this.SecretName)")

                    $this.SSHParameters = $parameters
                    $this.AddLog("[HVUpdateVM].TestVMConnection - Saving SSHParameters:`n$($this.SSHParameters | Format-Table | Out-String)`n")

                    # what distro family is this?
                    $rawOS = $results.OS
                    $this.AddLog("[HVUpdateVM].TestVMConnection - rawOS: $rawOS")
                    if ($rawOS -match "Windows") {
                        $this.OS = "Windows"
                        $this.AddLog("[HVUpdateVM].TestVMConnection - OS set to Windows family.")
                    } elseif ( ([DebianBasedDistros].GetEnumNames() | Where-Object { $rawOS -match $_ }) ) {
                        $this.OS = "Debian"
                        $this.AddLog("[HVUpdateVM].TestVMConnection - OS set to Debian family.")
                    } elseif ( ([FedoraBasedDistros].GetEnumNames() | Where-Object { $rawOS -match $_ }) ) {
                        $this.OS = "Fedora"
                        $this.AddLog("[HVUpdateVM].TestVMConnection - OS set to Fedora family.")
                    } elseif ($rawOS -match "macOS") {
                        $this.OS = "Unknown"
                        $this.AddLog("[HVUpdateVM].TestVMConnection - macOS is unsupport: $rawOS")
                    } elseif ( $rawOS -match "Arch" ) {
                        $this.OS = "Unknown"
                        $this.AddLog("[HVUpdateVM].TestVMConnection - Arch Linux is unsupport: $rawOS")
                    } else {
                        $this.OS = "Unknown"
                        $this.AddLog("[HVUpdateVM].TestVMConnection - OS family is unknown or unsupport: $rawOS")
                    }

                    $this.AddLog("[HVUpdateVM].TestVMConnection - OS is $($this.OS.ToString()).")
                } catch {
                    $this.AddLog("[HVUpdateVM].TestVMConnection - Could not connect with class secret: $($this.SecretName)")
                    $whoami = $null
                }   
            } else {
                $this.AddLog("[HVUpdateVM].TestVMConnection - Failed to connect with SSH and keyfile secrets.")
                $whoami = $null
            }
        }

        $this.AddLog("[HVUpdateVM].TestVMConnection - whoami: $whoami")

        if ( $whoami ) {
            $this.AddLog("[HVUpdateVM].TestVMConnection - End")
            return $true
        } else {
            # set error if the connection failed
            $this.SetError("VM_CONNECTION_TEST_FAILURE")
            $this.AddLog("[HVUpdateVM].TestVMConnection - End")
            return $false
        }
        
    }

    [bool]
    ConnectToVM() {
        $this.AddLog("[HVUpdateVM].ConnectToVM - Begin")
        $this.AddLog("[HVUpdateVM].ConnectToVM - Connect the PSSession.")

        # return true if already connected
        if ( $this.Session ) {
            if ( $this.Session.State -eq "Opened" -and $this.Session.Availability -eq "Available" ) {
                $this.AddLog("[HVUpdateVM].ConnectToVM - Already connected.")
                return $true
            }
        }

        if ($this.Credential) {
            try {
                $this.AddLog("[HVUpdateVM].ConnectToVM - Connect to WinRM session.")
                $this.Session = New-PSSession -VMId $this.VM.Id -Credential $this.Credential -Name $this.SessionName -EA Stop
                $this.AddLog("[HVUpdateVM].ConnectToVM - Connected.")
            } catch {
                $this.AddLog("Failed to connect to the VM: $_")
                if ($this.Status -ne "Error") { $this.SetError("VM_CONNECTION_FAILED") }
                return $false
            }
        } elseif ($this.SSHParameters) {
            try {
                $this.AddLog("[HVUpdateVM].ConnectToVM - Connect to SSH session.")
                # create a parameter or this won't work
                $parameter = $this.SSHParameters
                $this.Session = New-PSSession @parameter -EA Stop
                $this.AddLog("[HVUpdateVM].ConnectToVM - Connected.")
            } catch {
                $this.AddLog("Failed to connect to the VM: $_")
                if ($this.Status -ne "Error") { $this.SetError("VM_CONNECTION_FAILED") }
                return $false
            }
        } else {
            $this.AddLog("[HVUpdateVM].ConnectToVM - Unknown connection type or unsupported operating system.")
            if ($this.Status -ne "Error") { $this.SetError("VM_CONNECTION_FAILED") }
            return $false
        }

        $this.AddLog("[HVUpdateVM].ConnectToVM - End")
        return $true
    }

    [bool]
    DisconnectFromVM() {
        $this.AddLog("[HVUpdateVM].DisconnectFromVM - Begin")

        # return true is there is no session
        if ( -NOT $this.Session ) {
            $this.AddLog("[HVUpdateVM].DisconnectFromVM - Already disconnected.")
            return $true
        }

        # disconnect the session
        $loops = 0
        do {
            try {
                $this.AddLog("[HVUpdateVM].DisconnectFromVM - Remove session.")
                $null = $this.Session | Remove-PSSession -EA Stop
            }
            catch {
                $this.AddLog("[HVUpdateVM].DisconnectFromVM - Failed to disconnect session: $_")
            }

            # fail safe exit condition
            if ($loops -lt 10) {
                $loops++
            } else {
                $this.AddLog("[HVUpdateVM].DisconnectFromVM - Disconnect timeout failure.")
                # do not throw an error if this fails
                #if ($this.Status -ne "Error") { $this.SetError("VM_DISCONNECT_TIMEOUT") }
                return $false
            }
        } until ( $this.Session.State -eq "Closed" )

        $this.AddLog("[HVUpdateVM].DisconnectFromVM - Null session.")
        $this.Session = $null

        $this.AddLog("[HVUpdateVM].DisconnectFromVM - End")
        return $true
    }

    [bool]
    CopyScript() {
        # copies the current version of the update script.
        # don't worry about if it's there, just overwrite any existing file.
        # it's lazy, but this is a private module and doesn't need to be very smart.
        $this.AddLog("[HVUpdateVM].CopyScript - Begin")

        # make sure there's a credential first, bail if not
        if ( -NOT $this.Credential ) {
            $this.AddLog("[HVUpdateVM].CopyScript - No credential in the class.")
            $this.SetError("COPY_TRIED_WITH_NO_CREDENTIAL")
            $this.AddLog("[HVUpdateVM].CopyScript - End")
            return $false
        }

        # connect to the session if it is not established
        $connected = $this.ConnectToVM()

        if ( -NOT $connected ) {
            $this.SetError("COPY_FAIL_NO_CONNECTION")
            return $false
        }

        # check for a local copy of the Update-Windows.ps1
        # this is built to run from the module or script root, not the lib dir underneath.
        # do check in PWD... mainly for testing.
        # do not hunt for the file, just fail
        $this.AddLog("[HVUpdateVM].CopyScript - Looking for Update-Windows.ps1 in $PSScriptRoot.")
        $uwScriptFile = Get-Item "$script:RootPath\Update-Windows.ps1" -EA SilentlyContinue

        if ( -NOT $uwScriptFile ) {
            $this.AddLog("[HVUpdateVM].CopyScript - UW script not found. Looking in $($PWD.Path).")
            # try PWD
            $uwScriptFile = Get-Item "$($PWD.Path)\Update-Windows.ps1" -EA SilentlyContinue

            if ( -NOT $uwScriptFile ) {
                $this.AddLog("[HVUpdateVM].CopyScript - Failed to find the Update-Windows.ps1 file.")
                $this.SetError("UW_SCRIPT_NOT_FOUND")
                $this.AddLog("[HVUpdateVM].CopyScript - End")
                return $false
            }
        }

        $this.AddLog("[HVUpdateVM].CopyScript - UW script found at: $($uwScriptFile.FullName)")

        # copy the script
        try {
            $this.AddLog("[HVUpdateVM].CopyScript - Create the remote path for the script.")
            Invoke-Command -Session $this.Session -ScriptBlock { if (-NOT (Test-Path "C:\Scripts\UpdateWindows\lib")) { $null = mkdir "C:\Scripts\UpdateWindows\lib" -Force -EA SilentlyContinue } } -EA Stop

            $this.AddLog("[HVUpdateVM].CopyScript - Copy the script.")
            Copy-Item -ToSession $this.Session -Path "$($uwScriptFile.FullName)" -Destination "C:\Scripts\UpdateWindows" -Force -EA Stop
            Copy-Item -ToSession $this.Session -Path "$($uwScriptFile.DirectoryName)\lib\libGlobal_wu.ps1" -Destination "C:\Scripts\UpdateWindows\lib\libGlobal.ps1" -Force -EA Stop
            Copy-Item -ToSession $this.Session -Path "$($uwScriptFile.DirectoryName)\lib\libLogging.ps1" -Destination "C:\Scripts\UpdateWindows\lib\libLogging.ps1" -Force -EA Stop
        } catch {
            $this.AddLog("HVUpdateVM].CopyScript - The UW script copy failed: $_")
            $this.SetError("COPY_UW_SCRIPT_FAILED")
            $this.AddLog("[HVUpdateVM].CopyScript - End")
            return $false
        }

        $this.AddLog("[HVUpdateVM].CopyScript - End")
        return $true
    }

    [bool]
    InitScript() {
        $this.AddLog("[HVUpdateVM].InitScript - Begin")

        $this.AddLog("[HVUpdateVM].InitScript - Run the remote script.")

        if ( $this.OS -eq "Windows" ) {

            [scriptblock]$sbUpdate = {
                # where are all the files
                $dir = "C:\Scripts\UpdateWindows"

                # go to the script root
                Set-Location "$dir"

                # paramters for the update process
                $procSplat = @{
                    FilePath               = "powershell" 
                    ArgumentList           = "-NoProfile -NoLogo -ExecutionPolicy Bypass -File `"C:\Scripts\UpdateWindows\Update-Windows.ps1`""
                    WorkingDirectory       = "$dir"
                    RedirectStandardError  = "$dir\stdErr.txt"
                    RedirectStandardOutput = "$dir\stdOut.txt"
                    PassThru               = $true
                }

                # start update
                $pwshPID = Start-Process @procSplat

                # wait for the update to complete
                do {
                    Start-Sleep 1
                } until ( -NOT ( Get-Process -Id $pwshPID.Id -EA SilentlyContinue ) )

                # get stdOut and stdError
                $stdOut = Get-Content "$dir\stdOut.txt"
                $stdErr = Get-Content "$dir\stdErr.txt"

                # return the std outputs
                $std = [PSCustomObject]@{
                    Out = $stdOut
                    Err = $stdErr
                }

                return $std
            }

            $scriptResult = $false
            if ( $this.AsJob ) {
                $this.AddLog("[HVUpdateVM].InitScript - Run update script as job.")
                $scriptResult = $this.RunScriptAsJob($sbUpdate)
            } else {
                $this.AddLog("[HVUpdateVM].InitScript - Run update script serially.")
                $scriptResult = $this.RunScript($sbUpdate)
            }

            $this.AddLog("[HVUpdateVM].InitScript - End")
            return $scriptResult
        } elseif ( $this.OS -eq "Debian" ) {
            [scriptblock]$sbUpdate = {
                pwsh
                mkdir -p update_logs
                $filename = "update_$(Get-Date -Format "yyyyMMdd_HHmmss").log"
                sudo apt-get update | Out-File "./update_logs/$filename" -Force
                sudo apt-get upgrade --yes --quiet | Out-File "./update_logs/$filename" -Force -Append
                return (Get-Content "./update_logs/$filename")
            }

            $scriptResult = $false
            if ( $this.AsJob ) {
                $this.AddLog("[HVUpdateVM].InitScript - Run update script as job.")
                $scriptResult = $this.RunScriptAsJob($sbUpdate)
            } else {
                $this.AddLog("[HVUpdateVM].InitScript - Run update script serially.")
                $scriptResult = $this.RunScript($sbUpdate)

                # add results to class
                if ( $scriptResult ) {
                    $this.Result = $scriptResult
                }
            }

            $this.AddLog("[HVUpdateVM].InitScript - End")
            return $true
        } else {
            $this.AddLog("[HVUpdateVM].InitScript - Unknown or unsupported operating system: $($this.VM.Name)")
            $this.SetError("UNKNOWN_OPERATING_SYSTEM")
            return $false
        }
    }

    [bool]
    RunScript([scriptblock]$sbJob) {
        $this.AddLog("[HVUpdateVM].RunScript - Begin")
        try {
            $std = Invoke-Command -Session $this.Session -ScriptBlock $sbJob -EA Stop
        } catch {
            $this.AddLog("[HVUpdateVM].RunScript - Failed to execute the remote script as a job: $_")
            $this.SetError("UPDATE_FAILED_JOB_DID_NOT_START")
            $this.AddLog("[HVUpdateVM].RunScript - End")
            return $false
        }

        $this.AddLog("[HVUpdateVM].RunScript - std output:`nstdOut:`n`n$($std.Out)`n`nstdErr:`n`n$($std.Err)`n")

        # search for keyword rebootRequired: in std.Out
        if ($std.Out -match "rebootRequired:") {
            if ( $std.Out -match "rebootRequired:True" ) {
                $this.RebootRequired = $true
            } else {
                $this.RebootRequired = $false
            }

            $this.AddLog("[HVUpdateVM].RunScript - reboot needed: $($this.RebootRequired)")

            $this.Result = $std.Out
            $this.SetCompleted()
        } else {
            $this.SetError("UPDATE_FAILED_REBOOT_UNKNOWN")
            $this.Result = $std.Err
            $this.RebootRequired = $false
            $this.AddLog("[HVUpdateVM].RunScript - End")
            return $false
        }

        $this.AddLog("[HVUpdateVM].RunScript - Reboot needed: $($this.RebootRequired)")

        $this.AddLog("[HVUpdateVM].RunScript - End")
        return $true
    }

    [bool]
    RunScriptAsJob([scriptblock]$sbJob) {
        $this.AddLog("[HVUpdateVM].RunScriptAsJob - Begin")
        try {
            $this.Job = Invoke-Command -Session $this.Session -ScriptBlock $sbJob -AsJob -JobName $this.JobName -ThrottleLimit $this.ThrottleLimit -EA Stop 
        } catch {
            $this.AddLog("[HVUpdateVM].RunScriptAsJob - Failed to execute the remote script as a job: $_")
            $this.SetError("UPDATE_FAILED_ASJOB_DID_NOT_START")
            $this.AddLog("[HVUpdateVM].RunScriptAsJob - End")
            return $false
        }

        $this.AddLog("[HVUpdateVM].RunScriptAsJob - End")
        return $true
    }

    UpdateJob() {
        $this.AddLog("[HVUpdateVM].UpdateJob - Begin")
        # update the class status
        if ($this.Job.State -eq "Completed") {
            $this.AddLog("[HVUpdateVM].UpdateJob - Set completed.")
            $this.SetCompleted()
            $this.AddLog("[HVUpdateVM].UpdateJob - Getting results.")
            $this.Result = $this.Job | Receive-Job -Keep
            $this.AddLog("[HVUpdateVM].UpdateJob - Disconnect from the VM.")
            $this.DisconnectFromVM()

            # update reboot requirement
            if ( $this.Result.Out -match "rebootRequired:True" ) {
                $this.RebootRequired = $true
            } else {
                $this.RebootRequired = $false
            }
            $this.AddLog("[HVUpdateVM].UpdateJob - RebootRequired: $($this.RebootRequired)")

        } elseif ($this.Job.State -eq "Failed") {
            $this.AddLog("[HVUpdateVM].UpdateJob - Job failed. Set error.")
            $this.SetError("JOB_FAILURE")
            $this.AddLog("[HVUpdateVM].UpdateJob - Getting results.")
            $this.Result = $this.Job | Receive-Job -Keep
            $this.AddLog("[HVUpdateVM].UpdateJob - Disconnect from the VM.")
            $this.DisconnectFromVM()
        } elseif ($this.Job.State -eq "Running" -and $this.Status -ne "Running") {
            $this.AddLog("[HVUpdateVM].UpdateJob - Job running. Set status to running.")
            $this.SetRunning()
        }
        $this.AddLog("[HVUpdateVM].UpdateJob - End")
    }

    [bool]
    RebootIfRequired() {
        $this.AddLog("[HVUpdate].RebootIfRequired - Begin")
        if ($this.RebootRequired) { 
            $connected = $this.ConnectToVM()

            if ($connected -and $this.Credential) {
                try {
                    $this.AddLog("[HVUpdate].RebootIfRequired - Rebooting $($this.VM.Name)")
                    #Restart-Computer -ComputerName $this.VM.Name -Credential $this.Credential -Force -ErrorAction Stop    
                    $null = Invoke-Command -Session $this.Session -ScriptBlock { Restart-Computer -Force }
                    $this.AddLog("[HVUpdate].RebootIfRequired - Reboot has successfully been initiated.")
                } catch {
                    $this.AddLog("[HVUpdate].RebootIfRequired - Reboot failed: $_")
                    # this condition does not change the class error state
                    return $false
                }
            # Linux is not autorebooted. If I find a way to determine if a reboot is required I'll add it.  
            } else {
                $this.AddLog("[HVUpdate].RebootIfRequired - Could not connect to the VM or no valid credential. Manual reboot required.")
                return $false
            }
        } else {
            $this.AddLog("[HVUpdate].RebootIfRequired - A reboot is not required.")
            return $null
        }

        $null = $this.DisconnectFromVM()
        
        $this.AddLog("[HVUpdate].RebootIfRequired - End")
        return $true
    }

    #endregion

    ## Utility ##
    #region UTILITY
    # joins an array with spaces
    [string]
    hidden
    JoinArgsArray() {
        [string]$joined = $this.ArgumentList -join " "
        $this.AddLog("[HVUpdateVM].JoinArgsArray - Joined: $joined")
        return $joined
    }

    # get a timestamp
    [string]
    hidden
    Timestamp() {
        return (Get-Date -Format "yyyyMMdd-HH:mm:ss.ffff")
    }

    # write an event to the class log
    # don't use AddLog inside of AddLog
    hidden
    AddLog([string]$txt) {
        if ( -NOT [string]::IsNullOrEmpty($txt) ) { 
            Write-Verbose "$txt"
            $txt = "$($this.Timestamp())`: $txt" 
            
            # using Add() fails for some reason.
            #$this.Log.Add($txt)
            
            $this.Log += $txt
        }
    }

    # get random characters to make a name unique
    [string] hidden
    GetRandChar([int]$NumChar) {
        [string]$chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        [string]$str = ''
        for ($i = 0; $i -lt $NumChar; $i++) {
            [int]$salt = Get-Random -Minimum 5 -Maximum 20
            [int]$pepper = -1
            for ($j = 0; $j -lt $salt; $j++) {
                $pepper = Get-Random -Minimum $chars.Length -Maximum 1000
            }

            $charIdx = $pepper % $chars.Length

            $str += $chars[$charIdx]
        }

        $this.AddLog("[HVUpdateVM].GetRandChar - Random chars: $str")
        return $str
    }

    [bool]
    hidden
    IsSupportedArrayType($test) {
        $this.AddLog("[HVUpdateVM].IsSupportedArrayType(1) - Begin")
        $this.AddLog("[HVUpdateVM].IsSupportedArrayType(1) - Type:`n$($this.ArgumentList.GetType() | Out-String)")
        if ( $test -is [array] `
                -or $test -is [arrayList] `
                -or $test.GetType().Name -is 'List`1' `
                -or $test -is [hashtable]
            ) {
            $this.AddLog("[HVUpdateVM].IsSupportedArrayType(1) - Is supported array.")
            $this.AddLog("[HVUpdateVM].IsSupportedArrayType(1) - End")
            return $true
        } else {
            $this.AddLog("[HVUpdateVM].IsSupportedArrayType(1) - Is not a supported array.")
            $this.AddLog("[HVUpdateVM].IsSupportedArrayType(1) - End")
            return $false
        }
        $this.AddLog("[HVUpdateVM].IsSupportedArrayType(1) - End")
    }

    [bool]
    hidden
    IsSupportedArrayType() {
        $this.AddLog("[HVUpdateVM].IsSupportedArrayType() - Begin")
        if ( $null -eq $this.ArgumentList ) {
            $this.AddLog("[HVUpdateVM].IsSupportedArrayType() - Args are NULL. Return false.")
            return $false
        }

        $this.AddLog("[HVUpdateVM].IsSupportedArrayType() - Type:`n$($this.ArgumentList.GetType() | Out-String)")
        if ( $this.ArgumentList -is [array] `
                -or $this.ArgumentList -is [arrayList] `
                -or $this.ArgumentList.GetType().Name -eq 'List`1' `
                -or $this.ArgumentList -is [hashtable]
            ) {
            $this.AddLog("[HVUpdateVM].IsSupportedArrayType() - Is supported array.")
            $this.AddLog("[HVUpdateVM].IsSupportedArrayType() - End")
            return $true
        } else {
            $this.AddLog("[HVUpdateVM].IsSupportedArrayType() - Is not a supported array.")
            $this.AddLog("[HVUpdateVM].IsSupportedArrayType() - End")
            return $false
        }
    }
    #endregion UTILITY

    ## CONVERTERS ##
    #region CONVERTERS

    ConvertCsvToObject() {
        # this method must not change the status to Error if it fails.
        # and must not throw a terminating error.
        $this.AddLog("[HVUpdateVM].ConvertCsvToObject() - Begin")
        try {
            $this.AddLog("[HVUpdateVM].ConvertCsvToObject() - Converting the CSV to an object.")
            $convObj = $this.Result | ConvertFrom-Csv -EA Stop
            $this.AddLog("[HVUpdateVM].ConvertCsvToObject() - Success! Save the object to Result.")
            $this.Result = $convObj
        } catch {
            Write-Warning "Failed to convert the CSV result to an object: $_"
        }
        $this.AddLog("[HVUpdateVM].ConvertCsvToObject() - End")
    }

    #endregion CONVERTERS

    ## OUTPUT ##
    #region OUTPUT
    Write([string]$Filepath, [HVUpdateWriteType]$Type) {
        # write results to disk
        $this.AddLog("[HVUpdateVM].Write(2) - Begin")
        
        if ( $Type -eq "Force" ) {
            $this.AddLog("[HVUpdateVM].Write(2) - Write with Force.")
            $this.Result | Format-Table -AutoSize | Out-String | Out-File "$Filepath" -Force
        } else {
            $this.AddLog("[HVUpdateVM].Write(2) - Write with Append.")
            $this.Result | Format-Table -AutoSize | Out-String | Out-File "$Filepath" -Append
        }
        $this.AddLog("[HVUpdateVM].Write(2) - End")
    }

    Write([string]$Filepath) {
        # write results to disk - default to append
        $this.AddLog("[HVUpdateVM].Write(1) - Begin")
        $this.AddLog("[HVUpdateVM].Write(1) - Write with Append.")
        $this.Result | Format-Table -AutoSize | Out-String | Out-File "$Filepath" -Append
        $this.AddLog("[HVUpdateVM].Write(1) - End")
    }

    WriteLog([string]$Filepath, [HVUpdateWriteType]$Type) {
        # write results to disk
        $this.AddLog("[HVUpdateVM].WriteLog(2) - Begin")
        
        if ( $Type -eq "Force" ) {
            $this.AddLog("[HVUpdateVM].WriteLog(2) - Write with Force.")
            $this.AddLog("[HVUpdateVM].WriteLog(2) - End")
            $this.Log | Format-Table -AutoSize | Out-String | Out-File "$Filepath" -Force
        } else {
            $this.AddLog("[HVUpdateVM].WriteLog(2) - Write with Append.")
            $this.AddLog("[HVUpdateVM].WriteLog(2) - End")
            $this.Log | Format-Table -AutoSize | Out-String | Out-File "$Filepath" -Append
        }
    }

    WriteLog([string]$Filepath) {
        # write results to disk - default to append
        $this.AddLog("[HVUpdateVM].WriteLog(1) - Begin")
        $this.AddLog("[HVUpdateVM].WriteLog(1) - Write with Append.")
        $this.AddLog("[HVUpdateVM].WriteLog(1) - End")
        $this.Log | Format-Table -AutoSize | Out-String | Out-File "$Filepath" -Append
    }

    [string]
    ToString() {
        return ($this | Format-List | Out-String)
    }

    [string]
    ToShortString() {
        return ($this | Format-List -Property Command, Status, StatusCode | Out-String)
    }

    [string]
    ToShortLineString() {
        return ("Command: $($this.Command); Status: $($this.Status); StatusCode: $($this.StatusCode)")
    }

    #endregion OUTPUT

    #endregion
}


# format the class TypeData so the Format-Table and Format-List output is more human readable.

$TypeData = @{
    TypeName = 'HVUpdateVM'
    MemberType = 'ScriptProperty'
    MemberName = 'VMName'
    Value = {$this.VM.Name}
    DefaultDisplayPropertySet = 'VMName','OS','SecretName','Status','AsJob','RebootRequired'
}

if ( (Get-TypeData -TypeName HVUpdateVM | ForEach-Object { $_.Members.Count }) -le 0 ) {
    Update-TypeData @TypeData # -EA SilentlyContinue
}










    <#
    [bool]
    RunScript() {
        $this.AddLog("[HVUpdateVM].InitScript - Begin")

        # run the script as a job and monitor
        try {
            $this.AddLog("[HVUpdateVM].InitScript - Running script as ThreadJob: $($this.JobName)")

            [scriptblock]$sbUpdate = {
                $session = $args[0]

                Set-Location "C:\Scripts\UpdateWindows"
                $result = Invoke-Command -Session $session -ScriptBlock { powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Scripts\UpdateWindows\Update-Windows.ps1" -EA Stop }

                return $result
            }
            
            $this.AddLog("[HVUpdateVM].InitScript - Start job.")
            $this.Job = Start-ThreadJob -Name $this.JobName -ScriptBlock $sbUpdate -ArgumentList $this.Session -ThrottleLimit 4
        } catch {
            $this.AddLog("[HVUpdateVM].InitScript - Failed to start update job: $_")
            $this.SetError("JOB_START_FAILED")
        }

        if ($this.Status -ne "Error") {
            $this.AddLog("[HVUpdateVM].InitScript - Waiting on the job to complete.")
            $null = $this.Job | Get-Job | Wait-Job
            $this.AddLog("[HVUpdateVM].InitScript - Job complete.")
            
            # get job result
            $this.AddLog("[HVUpdateVM].InitScript - Receiving job data.")
            [List[Object]]$jobRes = $this.Job | Get-Job | Receive-Job
            $this.AddLog("[HVUpdateVM].InitScript - Job results:`n$($jobRes | Format-Table | Out-String)")
        
            # add job output to this.Result
            if ( $jobRes ) {
                $this.AddLog("[HVUpdateVM].InitScript - jobRes:`n$($jobRes | Format-Table | Out-String)")
                $this.Result = $jobRes
            } else {
                $this.SetError("JOB_EXECUTION_FAILURE")
            }

            # cleanup the job
            $this.AddLog("[HVUpdateVM].InitScript - Removing the job.")
            $this.Job | Remove-Job
            
            # compelte or error the job
            if ($this.Job.State -eq "Completed") {
                $this.AddLog("[HVUpdateVM].InitScript - Set status to completed.")
                $this.SetCompleted()
            } elseif ( $this.Status -ne "Error" ) {
                $this.AddLog("[HVUpdateVM].InitScript - Set status to error.")
                $this.SetError("JOB_UNKNOWN_STATE")
            }
        } else {
            $this.AddLog("[HVUpdateVM].InitScript - End")
            return $false
        }

        $this.AddLog("[HVUpdateVM].InitScript - End")
        return $true
    }
    #>
