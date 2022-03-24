
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

    Return information about list of computers specified in ComputerName parameter
.EXAMPLE 
    PS C:\> .\Get-SystemInfo.ps1 -TranscriptPath ~\transcripts\

    Create transcript file for script execution
.EXAMPLE 
    PS C:\> Get-ADComputer -Filter * | Select-Object -ExpandProperty Name | .\Get-SystemInfo.ps1
    
    Pass ComputerName parameter values with pipeline

.NOTES
  Version:                  1.1
  Author:                   kk601
  Creation Date:            14/01/2022
  Modificaton Date:         24/03/2022
  Recomended PS version:    7.*
  Purpose/Change:           Add support for passing parameters with pipeline
#>
[CmdletBinding()]
param (
    [Parameter(ValueFromPipeline=$true)]
    [ValidateScript({Resolve-DnsName -Name $_ -Type A})]
    [string[]] $ComputerName,
    [Parameter()]
    [string] $TranscriptPath
)
begin {
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
    $Date = get-Date -Format "MM_dd_yyyy_HH-mm"
    If ($TranscriptPath) {Start-Transcript -Path "$TranscriptPath\$Date.txt"}
    if (!$ComputerName) {$ComputerName = "localhost"}
}
process {
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
            @{Name="FreePhysicalMemory (MB)";Expression={[int]($_.FreePhysicalMemory/1KB)}},
            @{Name="TotalVisibleMemorySize (MB)";Expression={[int]($_.TotalVisibleMemorySize/1KB)}} 

        $OsInfo | Add-member -MemberType AliasProperty -Name FreeMemory -Value "FreePhysicalMemory (MB)"
        $OsInfo | Add-member -MemberType AliasProperty -Name TotalMemory -Value "TotalVisibleMemorySize (MB)"

        Write-Output "System information:", ($OsInfo | Select-Object * -ExcludeProperty FreeMemory,TotalMemory | format-list) 
        Show-PrecentageBar -Value $OsInfo.FreeMemory -TotalValue $OsInfo.TotalMemory -Label "Memory usage:" -ErrorAction Stop

        #System volume info
        $OsVolumeInfo = Get-CimInstance  -CimSession $CimSesion CIM_StorageVolume | Where-Object DriveLetter -eq "C:" |
            Select-object DriveLetter,FileSystem,
            @{Name="Capacity (GB)";Expression={[math]::Round($_.Capacity/1GB,3)}},
            @{Name="FreeSpace (GB)";Expression={[math]::Round($_.FreeSpace/1GB,3)}}

        $OsVolumeInfo | Add-member -MemberType AliasProperty -Name FreeSpace -Value "FreeSpace (GB)"
        $OsVolumeInfo | Add-member -MemberType AliasProperty -Name Capacity -Value "Capacity (GB)"

        Write-Output "OS volume information:", ($OsVolumeInfo | Select-Object * -ExcludeProperty FreeSpace,Capacity | Format-table)
        Show-PrecentageBar -Value $OsVolumeInfo.FreeSpace -TotalValue $OsVolumeInfo.Capacity -Label "OS drive freespace:" -ErrorAction Stop

        #Network adapters overview
        $NetAdaptersInfo = Get-NetIPConfiguration -CimSession $CimSesion | Select-Object InterfaceAlias,
            @{n="IPvAddress";e={$_.IPv4Address.ipaddress}},
            @{n="DNSServer";e={$_.DNSServer.Serveraddresses}}

        Write-Output "Network adapters:", $NetAdaptersInfo | Format-table
        Write-Output "------------------------------------"
    }
}
end {
    if ($TranscriptPath) {Stop-Transcript}
    Remove-Variable CimSesion, CimCredentials, TranscriptPath -ErrorAction Ignore
}