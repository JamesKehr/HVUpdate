### Vault Password Section ###
#region

# FUNCTION  : New-Password
# PURPOSE   : Generates a cryptographically strong secure key (password).

function New-Password {
    # how many characters are in the secure key
    param( 
        [int]$length = 64
    )

    Write-Debug "New-Password: Starting."
    # create the set of characters that will be used for the secure key
    Write-Debug "New-Password: Generating base characters for SecureKey."
    $lowerCaseLetters = [UInt32][char]"a"..[UInt32][char]"z"
    $domain = $lowerCaseLetters

    $upperCaseLetters = [UInt32][char]"A"..[UInt32][char]"Z"
    $domain += $upperCaseLetters

    $numbers = [UInt32][char]"0"..[UInt32][char]"9"
    $domain += $numbers

    #$symbols = [UInt32[]]('!#$%&()*+,-./'.ToCharArray())
    #$symbols += 58..64  # ':;<=>?@'
    #$symbols += 91..96   # '[\]^_`'
    #$symbols += 123..126    # '{|}~'
    $domain += $symbols

    Write-Debug "New-Password: Running calculations."
    $numberOfPossiblePasswords = [BigInt]::Pow($domain.Length, $Length)
    $bitsOfEntropy = [Math]::Log($numberOfPossiblePasswords)/[Math]::Log(2.0)

    if ($bitsOfEntropy -eq [double]::PositiveInfinity)
    {
        Write-Debug "New-Password: Length is too long."
        return
    }

    $bitsToGenerate = [UInt32]([Math]::Ceiling($bitsOfEntropy))
    $bytesToGenerate = ($bitsToGenerate + 7) -shr 3

    # bias is bounded by number of extra bytes generated. +1 byte yields a bound of 1/256.
    $largest_value_allowed = [BigInt]::Pow(256, $bytesToGenerate) - [BigInt]::ModPow(256, $bytesToGenerate, $numberOfPossiblePasswords)

    Write-Debug "New-Password: Generating the key."
    $randomBytes = New-Object byte[] $bytesToGenerate
    $random = New-Object Security.Cryptography.RNGCryptoServiceProvider

    do
    {
        $passwordRequirementsMet = $true

        do
        {
            $random.GetBytes($randomBytes)

            # add an extra 0 at the end (the most significant byte) to guarantee that we treat this as a positive number
            $randomBytesPositive = [byte[]]($randomBytes + [byte]0)

            # now, get the integer value of this array of random bytes
            $randomValue = [BigInt]$randomBytesPositive

            if ($Verbose)
            {
                if ($randomValue -gt $largest_value_allowed)
                {
                    Write-Debug("Getting a new number because:`n    {0}`n    {1}`n" -f $randomValue.ToString("N0"), $largest_value_allowed.ToString("N0"))
                }
            }

        } while ($randomValue -gt $largest_value_allowed);

        # now, generate the password
        $password = New-Object Text.StringBuilder

        $lowerCaseCharactersPresent = $false
        $upperCaseCharactersPresent = $false
        $numberCharactersPresent = $false
        $symbolCharactersPresent = $false

        for ($i=0 ; $i -lt $Length ; $i++)
        {
            $index = $randomValue % ($domain.Length)
            $character = $domain[$index]

            if ($lowerCaseLetters -contains $character) { $lowerCaseCharactersPresent = $true}
            if ($upperCaseLetters -contains $character) { $upperCaseCharactersPresent = $true}
            if ($numbers -contains $character)          { $numberCharactersPresent = $true}
            if ($symbols -contains $character)          { $symbolCharactersPresent = $true}

            $randomValue = $randomValue / $domain.Length

            $null=$password.Append([char]$character)
        }

        if ( (-not $lowerCaseCharactersPresent) -and (-not $upperCaseCharactersPresent) -and (-NOT $numberCharactersPresent) -and (-NOT $symbolCharactersPresent) )
        {
            if ($Verbose) { Write-Debug "Trying again because something is missing" }
            $passwordRequirementsMet = $false
        }

        if ($Verbose)
        {
            Write-Debug("Left over value`: {0}" -f $randomValue.ToString("N0"))
            $crackTime = ([double]$numberOfPossiblePasswords / (1000000000.0 * 60.0 * 60.0 * 24.0 * 365.24))
            Write-Debug("Your password has {0} bits of entropy, and there are {1} possible passwords." -f $bitsOfEntropy, $numberOfPossiblePasswords.ToString("N0"))
            Write-Debug("It would take {0} years to brute-force crack (at 1 attempt per nanosecond)." -f $crackTime.ToString("N"))
        }

    } while (-not $passwordRequirementsMet)

    $random = $null

    Write-Debug "New-Password: Work complete!"
    return $password.ToString()
} #end New-Password

function Set-FileHardening {
    param ($path)

    Write-Debug "Set-FileHardening: Hardening security."
    # get the root permissions
    $rootACL = Get-ACL $path

    # if dirUser is inherited we need to break inheritance
    if (($rootACL.Access.IsInherited | Sort-Object -Unique | Where-Object { $_ -eq $True }))
    {
        # https://docs.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.objectsecurity.setaccessruleprotection?view=netframework-4.7.2#System_Security_AccessControl_ObjectSecurity_SetAccessRuleProtection_System_Boolean_System_Boolean_
        $rootACL.SetAccessRuleProtection($true, $true)

        # apply inheritance break
        Set-ACL -Path $path -AclObject $rootACL

        # update rootACL
        $rootACL = Get-ACL $path

        # report results
        if (-NOT ($rootACL.Access.IsInherited | Sort-Object -Unique | Where-Object { $_ -eq $True }))
        {
            Write-Debug "Set-FileHardening: Inheritance was successfully broken on $path`."
        } 
        else 
        {
            Write-Debug "Set-FileHardening: Warning! Inheritance was not broken on $path`."
        }
    }

    Write-Debug "Set-FileHardening: Removing access to all but SYSTEM."
    # strip out all users that are not SYSTEM
    $rootACL.Access | ForEach-Object {
        if ($_.IdentityReference.Value -ne 'NT AUTHORITY\SYSTEM' -and $_.IdentityReference.Value -ne 'BUILTIN\Administrators')
        {
            $rootACL.RemoveAccessRuleSpecific($_)
        }
    }

    # change owner to SYSTEM
    Write-Debug "Set-FileHardening: Set owner to SYSTEM."
    $sysAcc = New-Object -TypeName System.Security.Principal.NTAccount -ArgumentList "NT AUTHORITY\SYSTEM"
    $rootACL.SetOwner($sysAcc)
    $admsAcc = New-Object -TypeName System.Security.Principal.NTAccount -ArgumentList "BUILTIN\Administrators"
    $rootACL.SetOwner($admsAcc)

    # update the ACL with permissions and owner changes
    try 
    {
        Set-ACL -Path $path -AclObject $rootACL -EA Stop    
    }
    catch 
    {
        Write-Debug "Set-FileHardening: WARNING! Failed to harden the file $path`. This shouldn't cause any execution issues, but file security may be slightly less robust."
    }
    
    Write-Debug "Set-FileHardening: Work complete!"
} #end Set-FileHardening


function New-DecryptFile {
    param ($strKey, $path)

    Write-Debug "New-DecryptFile: Starting"

    ## Decrypt credentials
    # create a here-string that will be converted to a scriptblock with the appropriate details
    Write-Debug "New-DecryptFile: Generating the encoded decrypt file."
    $sbP1 = @"
# static path to the credentials hash file
`$path = "$path"

# generate the key using a hash so it's always the same, without writing anything to file
try 
{
    [string]`$strKey = '$strKey'

"@

    $sbP2 = @'
    $hasher = New-Object System.Security.Cryptography.SHA256Managed
    $toHash = [System.Text.Encoding]::UTF8.GetBytes($strKey)
    $SecureKey = $hasher.ComputeHash($toHash)   
}
catch 
{
    return $null
}

# extract the user and pass securestrings
$file = Get-Content $path

# convert the encrypted string to a securestring
$encUser = $file[0] | ConvertTo-SecureString -key $SecureKey
$encDomain = $file[1] | ConvertTo-SecureString -key $SecureKey
$encPass = $file[2] | ConvertTo-SecureString -key $SecureKey

# convert username to plain text
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($encUser)
$user = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

# convert domain to plain text
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($encDomain)
$domain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

# convert domain to plain text
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($encPass)
$pass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

return @($user, $domain, $pass)
'@

    $strSb = $sbP1 + $sbP2

    # convert the string to scriptblock
    $decodeCreds = [scriptblock]::Create($strSb)

    # generate a random filename
    $outPath = [io.Path]::Combine("$env:LOCALAPPDATA\HVUpdate", [io.Path]::GetRandomFileName())

    # creating the encoded command and saving it to a secure location
    Write-Debug "New-DecryptFile: Encoding command and saving to secure location."
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($decodeCreds)
    $encodedCommand = [Convert]::ToBase64String($bytes)
    $encodedCommand | Out-File $outPath -Encoding ascii

    Write-Debug "New-DecryptFile: Hardening the file."
    Set-FileHardening -path $outPath

    Write-Debug "New-DecryptFile: Work complete!"
    return "$outPath"
} #end New-DecryptFile


function New-SecureCredential {
    ## Create a secure key for encrypt/decrypt
    # generate the key using a hash so the credentials can be decrypted on any system
    Write-Debug "New-SecureCredential: Starting"

    try 
    {
        Write-Debug "New-SecureCredential: Generating a secure key."
        [string]$strKey = New-Password
        $hasher = New-Object System.Security.Cryptography.SHA256Managed
        $toHash = [System.Text.Encoding]::UTF8.GetBytes($strKey)
        $SecureKey = $hasher.ComputeHash($toHash)   
    }
    catch 
    {
        Write-Debug "New-SecureCredential: Failed to create a securekey."
        return $null
    }

    ## Get and encode credentials
    $creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "HVUpdateVault", $(New-Password | ConvertTo-SecureString -AsPlainText -Force)

    # exit if a PSCredential object is not passed
    if ($creds -isnot [System.Management.Automation.PSCredential]) 
    {
        Write-Debug "New-SecureCredential: Invalid credentials. Must pass a PSCredential object (Get-Credential)"
        return $null
    }

    # static path to the credentials hash file
    $path = [io.Path]::Combine("$env:LOCALAPPDATA\HVUpdate", [io.Path]::GetRandomFileName())

    # convert user, domain, and pass to securestring and export to file
    [string]$user = $creds.GetNetworkCredential().UserName
    $encUser = $user | ConvertTo-SecureString -AsPlainText -Force
    $encUser | ConvertFrom-SecureString -key $SecureKey | Out-File $path

    if ( -NOT [string]::IsNullOrEmpty( $creds.GetNetworkCredential().Domain) ) 
    {
        [string]$domain = $creds.GetNetworkCredential().Domain
        $encDomain = $domain | ConvertTo-SecureString -AsPlainText -Force
        $encDomain | ConvertFrom-SecureString -key $SecureKey | Out-File $path -Append
    }

    [string]$pass = $creds.GetNetworkCredential().Password
    $encPass = $pass | ConvertTo-SecureString -AsPlainText -Force
    $encPass | ConvertFrom-SecureString -key $SecureKey | Out-File $path -Append

    ## now strip out all permissions on the file except for SYSTEM, which is the context the task runs under
    Set-FileHardening -path $path

    ## create the decrypt file
    $result = New-DecryptFile -strKey $strKey -path $path

    return $result
} #end New-SecureCredential


function Get-HVUpdateVaultPassword {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $PassFile = $null
    )

    if ( [string]::IsNullOrEmpty($PassFile) ) {
        Write-Debug "Creating new password file."
        $PassFile = New-SecureCredential
        Write-Debug "New PassFile: $PassFile"

        if (-NOT $PassFile)
        {
            Write-Debug "Critical Error! Could not create secure credentails: $PassFile"
            exit
        }
    }

    Write-Debug "passFile: $PassFile"
    $encCommand = Get-Content $PassFile
    $flatCreds = powershell -NoProfile -NoLogo -EncodedCommand $encCommand

    if ($flatCreds[1] -ne "") {
        $creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "$($flatCreds[1])\$($flatCreds[0])", $($flatCreds[2] | ConvertTo-SecureString -AsPlainText -Force)
    } else {
        $creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "$($flatCreds[0])", $($flatCreds[2] | ConvertTo-SecureString -AsPlainText -Force)
    }

    Remove-Variable flatCreds

    $value = [PSCustomObject]@{
        Password = $creds.Password
        PassFile = $PassFile
    }

    return $value
    
}

#endregion


function Update-RequiredModules {
        # make sure the modules are installed
        $modules = 'Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore'

        foreach ($mod in $modules) {
            log "Update-RequiredModules - Checking module: $mod"
            $modFnd = Get-Module -ListAvailable $mod -EA SilentlyContinue
    
            if ( -NOT $modFnd) {
                log "Update-RequiredModules - $mod is not installed."
                try {
                    log "Update-RequiredModules - Installing $mod."
                    $null = Install-Module $mod -Force -EA Stop
                    log "Update-RequiredModules - $mod has been installed."
                }
                catch {
                    log "Update-RequiredModules - Failed to install a required module ($mod): $_"
                    return ( Write-Error "Failed to install a required module ($mod): $_" -EA Stop )
                }
            } else {
                # run a module update
                log "Update-RequiredModules - Updating module: $mod"
                $null = Update-Module $mod -EA SilentlyContinue
            }
        }
}

function New-HVUpdateConfElement {
    return ([PSCustomObject]@{
        VMName     = $null
        SecretName = $null
        OSFamily   = $null
        LastUpdate = $null
        VMState    = ""
        TempSkip   = $false
        Exclude    = $false
        NoReboot   = $false
        HVUpdateVM = $null
    })
}

<#

    "VMName": "MGMT-DNS",
    "SecretName": "VMCred_Administrator_087642",
    "OSFamily": "Windows",
    "LastUpdate": "2023-11-14T20:18:33.2735258+00:00",
    "VMState": null,
    "TempSkip": false,
    "Exclude": false,
    "NoReboot": false

#>