# HVUpdate
Manages updates for Windows Server Hyper-V VMs for small and lab environments.

# Instructions

__*These are the basic steps for the beta/preview release of HVUpdate*__

1. Copy the scripts to the Hyper-V host.
2. Open an elevated (Run as administrator) PowerShell 7.3+ terminal or console window.

   a. PowerShell 7.3 is required. It can be installed on Windows Server and Client.

   b. Windows Terminal is optional but recommended. Terminal can be installed on WS2022.
   
4. Create the HVUpdate vault by running this command:
   
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

5. Add VM credentials to the vault.

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
      
      1. See Linux Notes below for Linux setup. 
      
      2. Add the keyfile and SSH connection string as a KeyFile HVUpdate credential.

    ```powershell
   .\Add-HVUpdateCredential.ps1 -KeyFile "<full path to pem file>" -SSHPath '<user>@[IP|hostname|FQDN]'
   ```

   ```powershell
   # Example
   .\Add-HVUpdateCredential.ps1 -KeyFile "C:\Users\user\AppData\Local\HVUpdate\server-kp.pem" -SSHPath 'bawb@gateway'
   ```

7. Start the update process.

```powershell
.\Start-HVUpdate.ps1
```

6. You can watch the progress by looking in the Logs folder at the newest log file.

   a. This command will read the newest log file, from the script folder, and update the console as new lines are added.

    ```powershell
    gci ".\Logs" -Filter "HVUpdate_202*.log" | sort -Descending | select -First 1 | % { gc "$($_.FullName)" -wait }
    ```

# Windows Notes

PSRemoting must be enabled. Server SKUs should have it enabled by default. Client SKUs may need it enabled manually.

```powershell
Enable-PSRemoting -Force
```

# Linux Notes

1. The hostname must be resolvable from the HV host (i.e. Resolve-DnsName "<hostname>").
    - This may require mDNS to be manually installed on the VM.
    - Ubuntu/Debian-based: sudo apt update && sudo apt install libnss-mdns -y
2. SSH must be configured passwordless with a KeyFile.
    - https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement
    - Logon to the Linux VM as the user that will be used for updates.
        - This user must be a sudoer (Linux administrator).
    - Run this command to generate key files for the user in the home directory:

        ```bash
        cd $HOME
        ssh-keygen -P "" -t rsa -b 4096 -m pem -f $(hostname)-kp
        ```

    - This command will create two files:
        <hostname>-kp
        <hostname>-kp.pub

    - Use this command to copy the public key to the authorized_keys file:

        ```bash
        cat "$(hostname)-kp.pub" >> $HOME/.ssh/authorized_keys
        ```

    - Copy the contents of <hostname>-kp to the Hyper-V host in a PEM file. You can copy/paste through SSH or use a command like this:

        ```bash
        scp user@server:/home/user/<hostname>-kp <Windows path>/<hostname>-kp.pem
        ```
        
        Example:
  
        ```bash
        scp user@gateway:/home/user/gateway-kp C:\Users\MyAdminAccount\AppData\Local\HVUpdate\gateway-kp.pem
        ```

    - Test SSH using the key file: 

        ```
        ssh -i <Windows path>/<hostname>-kp.pem <user>@<server>
        ```
        
        Example:
  
        ```
        ssh -i C:\Users\MyAdminAccount\AppData\Local\HVUpdate\gateway-kp.pem user@gateway\
        ```

    - You should be be prompted for a password. That needs to change.
    - Edit the sudoer file:

        ```bash
        sudo nano /etc/sudoers
        ```

    - Go to the bottom of the file, past the "includedir /etc/sudoers.d" line, and add a line for your user account (replace username with your username):
  
        ```
        username ALL=(ALL) NOPASSWD: ALL
        ```

    - Save and exit: Ctrl+X, y, Enter
    - Logoff of ssh by running: exit
    - SSH back in using the PEM file.
    - Run this command to confirm that passwordless commands are working.

        ```bash
        sudo apt update
        ```

    - Backup the -kp files to a safe place.

3. The KeyFile path and connection string must be added to the HVUpdateVault using: Add-HVUpdateCredential -KeyFile "<path to key file (.pem)>" -SSHPath '<user>@[server|IP|FQDN]'
4. Install PowerShell on the Linux VM.

https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux?view=powershell-7.3

5. Follow these steps to configure Linux sshd to use PowerShell remoting.

https://learn.microsoft.com/en-us/powershell/scripting/learn/remoting/ssh-remoting-in-powershell?view=powershell-7.3#install-the-ssh-service-on-an-ubuntu-linux-computer



