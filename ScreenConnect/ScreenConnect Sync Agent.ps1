<#
.SYNOPSIS
    Updates the ScreenConnect session on the NinjaOne device to match the NinjaOne Organization and Location information.

.DESCRIPTION
    Queries the current ScreenConnect sessions by name, will match against local IP address and then automatically update the 
    Company and Location information that the Device has in NinjaOne for the organization name and location name in ScreenConnect.
    
    ScreenConnect Access Session information:
    Company  = CustomProperty1
    Site     = CustomProperty2

    NinjaOne Device variables:
    Organization Name = $env:NINJA_ORGANIZATION_NAME
    Location Name     = $env:NINJA_LOCATION_NAME

.NOTES
    Requires the RESTful API Manager extension to be installed on the ScreenConnect server.
    https://docs.connectwise.com/ScreenConnect_Documentation/Developers/RESTful_API_Manager

    For the RESTfulAllowedOrigin the suggestion is to set to the FQDN of the ScreenConnect server.
    Example:
        RESTfulAllowedOrigin = documentation.screenconnect.com

#>

#Temporary set the PS Execution to unrestricted for the process to execute
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process

# Determine the supported TLS versions and set the appropriate security protocol
# Prefer Tls13 and Tls12 if both are available, otherwise just Tls12, or warn if unsupported.
$SupportedTLSversions = [enum]::GetValues('Net.SecurityProtocolType')
if ( ($SupportedTLSversions -contains 'Tls13') -and ($SupportedTLSversions -contains 'Tls12') ) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol::Tls13 -bor [System.Net.SecurityProtocolType]::Tls12
}
elseif ( $SupportedTLSversions -contains 'Tls12' ) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}
else {
    # Warn the user if TLS 1.2 and 1.3 are not supported, which may cause the download to fail
    Write-Host -Object "[Warning] TLS 1.2 and/or TLS 1.3 are not supported on this system. This download may fail!"
    if ($PSVersionTable.PSVersion.Major -lt 3) {
        Write-Host -Object "[Warning] PowerShell 2 / .NET 2.0 doesn't support TLS 1.2."
    }
}

$RESTfulAllowedOrigin = "<SCREENCONNECT_SERVER_WEB_ADDRESS>"
$scfingerprint = "<INSTANCE_IDENTIFIER_FINGERPRINT>"
$RESTfulAuthenticationSecret = "<SECRET>"

#ScreenConnect client service name
$sc = Get-Service "ScreenConnect Client ($($scfingerprint))" -ErrorAction SilentlyContinue

#RESTful API Manager, Base URL and Headers
$rambaseurl = "https://$($RESTfulAllowedOrigin)/App_Extensions/2d558935-686a-4bd0-9991-07539f5fe749/Service.ashx"
$ramheaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$ramheaders.Add("Content-Type", "application/json")
$ramheaders.Add("CTRLAuthHeader", $RESTfulAuthenticationSecret)
$ramheaders.Add("Origin", $RESTfulAllowedOrigin)

$serial = (Get-CimInstance -Class Win32_BIOS).SerialNumber
$lip = ((ipconfig | findstr [0-9].\.)[0]).Split()[-1]

if (!$sc) {
    Exit 0
}
else {
    $guid = Invoke-RestMethod "$($rambaseurl)/GetSessionsByName" -Method 'POST' -Headers $ramheaders -Body "[`"$env:COMPUTERNAME`"]"
    foreach ($g in $guid) {
        if (($g.ActiveConnections) -and ($g.GuestInfo.MachineSerialNumber -match $serial) -and ($g.GuestInfo.PrivateNetworkAddress -match $lip)) {
            if (-not ($g.CustomProperties.CustomProperty1 -eq "$env:NINJA_ORGANIZATION_NAME") -or ($g.CustomProperties.CustomProperty1 -eq "$env:NINJA_LOCATION_NAME")) {
                $sguid = $g.SessionID
                $ramupdate = ConvertTo-Json @("$sguid", ("$env:NINJA_ORGANIZATION_NAME", "$env:NINJA_LOCATION_NAME"))
                Invoke-RestMethod "$($rambaseurl)/UpdateSessionCustomProperties" -Method 'POST' -Headers $ramheaders -Body $ramupdate
            }
        }
    }
}