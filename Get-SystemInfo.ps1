
<#
.SYNOPSIS
    This is a script to gather computer information.

.DESCRIPTION
    This script is designed to gather and show computer information.
    Information gathered includes:
        Operating system info and memory usage
        Usage of space on systme volume
        Network configuration overview

.EXAMPLE
    PS C:\> .\Get-SystemInfo.ps1

    In this example, when ComputerName parameter is not specified the script is run on localhost.
.EXAMPLE 
    PS C:\> .\Get-SystemInfo.ps1 -ComputerName DC-01,WS-01

    This example returns information about list of computers specified in ComputerName parameters
.NOTES
  Version:        1.0
  Author:         kk601
  Creation Date:  14/01/2022
  Purpose/Change: Initial script development
#>
[CmdletBinding()]
param (
    [ValidateScript({Resolve-DnsName -Name $_ -Type A})]
    [string[]] $ComputerName
)
process {
    function Show-PrecentageBar {
        [cmdletbinding()]
        param (
            [Parameter(Mandatory=$true)]
            [int] $Value,
            [Parameter(Mandatory=$true)]
            [int] $TotalValue,
            [Parameter()]
            [string] $Label
        )
        $BarWidth = ($Host.UI.RawUI.WindowSize.Width) * 0.75
    
        If ($Label) {Write-Host $Label}
        Write-Host "[" -NoNewline
        for ($i = 0; $i -lt $BarWidth; $i++) {
            $Color = If($i/$BarWidth -lt $Value/$TotalValue) {"Green"} Else {"Red"}
            Write-Host ([char]9608) -NoNewline -ForegroundColor $Color
        }
        Write-Host "]",([math]::Round(((($TotalValue - $Value)/$TotalValue)*100),2)),"% used.`n"
    }

    if (!$ComputerName) {$ComputerName = "localhost"}

    foreach ($Computer in $ComputerName) {
        #Check for permissions
        try {
            $CimSesion = New-CimSession -ComputerName $Computer -ErrorAction Stop
        }
        catch [Microsoft.Management.Infrastructure.CimException] 
        {
            if ($null -eq $CimCredentials) {
                Write-Output "This account has no permissions to perform this action, enter other credentials:"
                do {
                    $CimCredentials = Get-Credential -Message "Enter correct credentials:" 
                    $CimSesion = New-CimSession -ComputerName $Computer -Credential $CimCredentials -ErrorAction Ignore
                } until ($null -ne $CimSesion)
            }
            else {
                $CimSesion = New-CimSession -ComputerName $Computer -Credential $CimCredentials -ErrorAction SilentlyContinue 
            }
        }

        Write-Output "Computer: $Computer`n"
        #OS description 
        $OsInfo = Get-CimInstance -CimSession $CimSesion CIM_OperatingSystem -ErrorAction Stop| 
            Select-Object CSName,Status,Caption,LastBootUpTime,
            @{Name="FreePhysicalMemory";Expression={[int]($_.FreePhysicalMemory/1KB)}},
            @{Name="TotalVisibleMemorySize";Expression={[int]($_.TotalVisibleMemorySize/1KB)}}

        Write-Output "System information:", $OsInfo | format-list
        Show-PrecentageBar -Value $OsInfo.FreePhysicalMemory -TotalValue $OsInfo.TotalVisibleMemorySize -Label "Memory usage:"

        #System volume info
        $OsVolumeInfo = Get-CimInstance  -CimSession $CimSesion CIM_StorageVolume | Where-Object DriveLetter -eq "C:" |
            Select-object DriveLetter,FileSystem,
            @{Name="Capacity";Expression={[math]::Round($_.Capacity/1GB,3)}},
            @{Name="FreeSpace";Expression={[math]::Round($_.FreeSpace/1GB,3)}}

        Write-Output "OS volume information:", $OsVolumeInfo | Format-table
        Show-PrecentageBar -Value $OsVolumeInfo.FreeSpace -TotalValue $OsVolumeInfo.Capacity -Label "OS drive freespace:"

        #Network adapters overview
        $NetAdaptersInfo = Get-NetIPConfiguration -CimSession $CimSesion | Select-Object InterfaceAlias,
            @{n="IPvAddress";e={$_.IPv4Address.ipaddress}},
            @{n="DNSServer";e={$_.DNSServer.Serveraddresses}}

        Write-Output "Network adapters:", $NetAdaptersInfo | Format-table
        Write-Output "------------------------------------"
    }
}
End {
    Remove-Variable CimSesion, CimCredentials -ErrorAction Ignore
}