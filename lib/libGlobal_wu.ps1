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
