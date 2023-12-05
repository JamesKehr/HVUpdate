# HVUpdate
Manages updates for Windows Server Hyper-V VMs for small and lab environments.

# Instructions

__*These are the basic steps for the beta/preview release of HVUpdate*__

1. Copy the scripts to the Hyper-V host.
2. Open an elevated (Run as administrator) PowerShell 7.3+ terminal or console window.
    a. PowerShell 7.3 is required. It can be installed on Windows Server and Client.
    b. Windows Terminal is optional but recommended. Terminal can be installed on WS2022.
3. Create the HVUpdate vault by running this command:
   
   ```powershell
   .\Add-HVUpdateCredentialVault.ps1
   ```

    a. Try resetting the SecretStore if you get an error enabling the vault. This will remove all secrets that have been added, so be careful!

    ```powershell
    Reset-SecretStore -Force -PassThru -Interaction None
    ```

    b. To reset just the HVUpdate vault use this command. Caution! This will remove any secrets added to the HVUpdate vault.

   ```powershell
   .\Remove-HVUpdateCredentialVault.ps1
   ```

4. Add VM credentials to the vault.
    a. Windows VMs only need a username and password.

    Single credential:

   ```powershell
   .\Add-HVUpdateCredential.ps1 -Credential (Get-Credential)
   ```

    Multiple credentials via the credential add wizard:

    ```powershell
   .\Add-HVUpdateCredential.ps1
   ```


    b. Linux systems use SSH and require an connection string, a keyfile, PowerShell, and changes to sshd_config. 
      1. See Notes.txt for Linux setup. 
      2. Add the keyfile and SSH connection string as a KeyFile HVUpdate credential.

    ```powershell
   .\Add-HVUpdateCredential.ps1 -KeyFile "<full path to pem file>" -SSHPath '<user>@[IP|hostname|FQDN]'
   ```

   ```powershell
   # Example
   .\Add-HVUpdateCredential.ps1 -KeyFile "C:\Users\user\AppData\Local\HVUpdate\server-kp.pem" -SSHPath 'bawb@gateway'
   ```

5. Start the update process.

```powershell
.\Start-HVUpdate.ps1
```

6. You can watch the progress by looking in the Logs folder at the newest log file.
    a. This command will read the newest log file, from the script folder, and update the console as new lines are added.

    ```powershell
    gci ".\Logs" -Filter "HVUpdate_202*.log" | sort -Descending | select -First 1 | % { gc "$($_.FullName)" -wait }
    ```
