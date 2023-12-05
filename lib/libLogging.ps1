<#

This is a library of functions that performs simple logging. There is one log function for each PowerShell stream:

https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_output_streams?view=powershell-7.3

Stream #	Description	    	Write Cmdlet
1	        Success stream		Write-Output
2	        Error stream		Write-Error
3	        Warning stream		Write-Warning
4	        Verbose stream		Write-Verbose
5	        Debug stream		Write-Debug
6	        Information stream	Write-Information


These are light, fast functions that do not check for an existing file and will fail if there is none.

Be careful logging to the Success stream as it can break outputs and returns! Please use Information, 
Warning, Verbose, Error, or Debug unless you know what you are doing.

#>


# creates a timestamp string
function timestamp {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]
        $FileStamp
    )
    if ($FileStamp.IsPresent) {
        return (Get-Date -Format "yyyyMMdd_HHmmss")
    } else {
        return (Get-Date -Format "yyyy-MM-dd_HH:mm:ss.ffff")
    }
    
}

# Generic log command that is a wrapper for logI
# Do no change to logS as it can break outputs and returns!
function log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,
                    ValueFromPipeline=$true)]
        [string]
        $text,

        [Parameter(Mandatory=$true)]
        [string]
        $LogPath,

        [switch]
        $Quiet,
        
        [switch]
        $ToHost,

        [switch]
        $NoNewLine,

        [string]
        [ValidateSet("Black", "DarkBlue", "DarkGreen", "DarkCyan", "DarkRed", "DarkMagenta", "DarkYellow", "Gray", "DarkGray", "Blue", "Green", "Cyan", "Red", "Magenta", "Yellow", "White")]
        $ForeColor = "White"
    )
    logI @PSBoundParameters
}

# Log again the Success stream
function logS {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,
                    ValueFromPipeline=$true)]
        [string]
        $text,

        [Parameter(Mandatory=$true)]
        [string]
        $LogPath,

        [switch]
        $Quiet
    )

    begin {}

    process {
        # write the text to the log file
        Out-File -InputObject "$(timestamp): $text" -FilePath "$LogPath" -Force -Append

        # write to the Success stream
        if ( -NOT $Quiet.IsPresent) {
            Write-Output $text
        }
    }
    
    end {}
}

# Log again the Error stream
# Quiet is not valid here. Error output should never be suppressed.
function logE {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,
                    ValueFromPipeline=$true)]
        [string]
        $text,

        [Parameter(Mandatory=$true)]
        [string]
        $LogPath
    )

    begin {}

    process {
        # write the text to the log file
        Out-File -InputObject "$(timestamp): $text" -FilePath "$LogPath" -Force -Append

        # write to the Error stream
        Write-Error $text
    }
    
    end {}
}

# Log again the Warning stream
# Quiet is not valid here. Warning output should never be suppressed.
function logW {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,
                    ValueFromPipeline=$true)]
        [string]
        $text,

        [Parameter(Mandatory=$true)]
        [string]
        $LogPath
    )

    begin {}

    process {
        # write the text to the log file
        Out-File -InputObject "$(timestamp): $text" -FilePath "$LogPath" -Force -Append

        # write to the Warning stream
        Write-Warning $text
    }
    
    end {}
}

# Log again the Verbose stream
function logV {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,
                    ValueFromPipeline=$true)]
        [string]
        $text,

        [Parameter(Mandatory=$true)]
        [string]
        $LogPath,

        [switch]
        $Quiet
    )

    begin {}

    process {
        # write the text to the log file
        Out-File -InputObject "$(timestamp): $text" -FilePath "$LogPath" -Force -Append

        # write to the Verbose stream
        if ( -NOT $Quiet.IsPresent) {
            Write-Verbose $text
        }
    }
    
    end {}
}

# Log again the Debug stream
function logD {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,
                    ValueFromPipeline=$true)]
        [string]
        $text,

        [Parameter(Mandatory=$true)]
        [string]
        $LogPath,

        [switch]
        $Quiet
    )

    begin {}

    process {
        # write the text to the log file
        Out-File -InputObject "$(timestamp): $text" -FilePath "$LogPath" -Force -Append

        # write to the Debug stream
        if ( -NOT $Quiet.IsPresent) {
            Write-Debug $text
        }
    }
    
    end {}
}

# Log again the Information stream
function logI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,
                    ValueFromPipeline=$true)]
        [string]
        $text,

        [Parameter(Mandatory=$true)]
        [string]
        $LogPath,

        [switch]
        $Quiet,
        
        [switch]
        $ToHost,

        [switch]
        $NoNewLine,

        [string]
        [ValidateSet("Black", "DarkBlue", "DarkGreen", "DarkCyan", "DarkRed", "DarkMagenta", "DarkYellow", "Gray", "DarkGray", "Blue", "Green", "Cyan", "Red", "Magenta", "Yellow", "White")]
        $ForeColor = "White"
    )

    begin {}

    process {
        # write the text to the log file
        Out-File -InputObject "$(timestamp): $text" -FilePath "$LogPath" -Force -Append

        # write to the Information stream
        if ($ToHost.IsPresent -and -NOT $Quiet.IsPresent) {
            if ($NoNewLine.IsPresent) {
                Write-Host $text -ForegroundColor $ForeColor -NoNewline
            } else {
                Write-Host $text -ForegroundColor $ForeColor
            }
            
        } elseif ( -NOT $Quiet.IsPresent) {
            Write-Information $text
        }
    }
    
    end {}
}