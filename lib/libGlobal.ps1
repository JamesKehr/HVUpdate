<#
    The Global Header file contains configuration variables and constants that
    are common across all ExoArchive scripts.
#>

# this file sits in <root>\lib, so don't use $PSScriptRoot.
# $RootPath will point to where the root scripts are.
$script:RootPath = Split-Path $PSScriptRoot -Parent

# path to the reports dir
$script:ReportsPath = "$script:RootPath\Reports"

### Logging constants ###

# path to the Logs dir
$script:lPath = "$script:RootPath\Logs"

# log name
$script:lNameRoot = "HVUpdate"


### Vault constants ###

# the vault name
$script:VaultName = "HVUpdateVault"

# path to the vault password file
$script:VaultPassFile = 'C:\Users\jakehr\AppData\Local\HVUpdate\vpnt0lyi.2fo'
# Replaced 11/22/2023 3:42:45 PM : $script:VaultPassFile = $null

# retrieve the vault password
$script:vaultFile = Get-HVUpdateVaultPassword -PassFile "$script:VaultPassFile"
$script:VaultPassword = $script:vaultFile.Password


### VM configuration constants ###
# where the settings file is located.
$script:VmConfDir = "$env:LOCALAPPDATA\HVUpdate"

# where the settings file is located.
$script:VmConf = "$script:VmConfDir\hvupdate.json"
