#Requires -RunAsAdministrator

# Liest IPv4-Adresse, Subnetzmaske und Gateway vom Benutzer ein und setzt diese
# auf der einzigen aktiven Netzwerkschnittstelle des Systems.

function Read-IPv4Address {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    while ($true) {
        $value = Read-Host $Prompt

        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Warning "Eingabe darf nicht leer sein."
            continue
        }

        $parsedIp = $null
        if ([System.Net.IPAddress]::TryParse($value.Trim(), [ref]$parsedIp) -and
            $parsedIp.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
            return $parsedIp.IPAddressToString
        }

        # Hinweis, falls die Eingabe kein valides IPv4-Format hat.
        Write-Warning "Bitte eine gültige IPv4-Adresse eingeben (z.B. 192.168.178.10)."
    }
}

function Convert-SubnetMaskToPrefixLength {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SubnetMask
    )

    $parts = $SubnetMask.Split('.', [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -ne 4) {
        throw "Subnetzmaske muss aus genau vier Oktetten bestehen."
    }

    $binaryString = ''
    foreach ($part in $parts) {
        $octet = 0
        if (-not [byte]::TryParse($part.Trim(), [ref]$octet)) {
            throw "Ungültiges Oktett '$part' in Subnetzmaske."
        }

        # Subnetzmaske in ein 32-bit-Bitmuster überführen.
        $binaryString += [Convert]::ToString($octet, 2).PadLeft(8, '0')
    }

    if ($binaryString -match '01') {
        throw "Subnetzmasken müssen durchgehende 1-Bits enthalten (z.B. 255.255.255.0)."
    }

    return ($binaryString -replace '0', '').Length
}

# Interaktive Eingaben.
$ipAddress = Read-IPv4Address -Prompt "IPv4-Adresse eingeben"
$subnetMask = Read-IPv4Address -Prompt "Subnetzmaske eingeben"
$gateway = Read-IPv4Address -Prompt "Standardgateway eingeben"

try {
    # Prefixlänge aus der Subnetzmaske berechnen.
    $prefixLength = Convert-SubnetMaskToPrefixLength -SubnetMask $subnetMask
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
if ($adapters.Count -eq 0) {
    Write-Error "Es wurde keine aktive Netzwerkschnittstelle gefunden."
    exit 1
}

if ($adapters.Count -gt 1) {
    Write-Error "Es wurden mehrere aktive Netzwerkschnittstellen gefunden. Bitte nur eine Schnittstelle aktiv lassen."
    exit 1
}

$adapter = $adapters[0]
Write-Host "Konfiguriere Schnittstelle '$($adapter.Name)' (IfIndex $($adapter.IfIndex))..." -ForegroundColor Cyan

try {
    # DHCP deaktivieren, damit die statischen Werte gesetzt werden können.
    Set-NetIPInterface -InterfaceIndex $adapter.IfIndex -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop

    # Bestehende IPv4-Adressen entfernen, bevor neue Adresse + Netzmaske gesetzt werden.
    Get-NetIPAddress -InterfaceIndex $adapter.IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    # Neue IPv4-Adresse, Prefix und Gateway anwenden.
    New-NetIPAddress -InterfaceIndex $adapter.IfIndex `
        -IPAddress $ipAddress `
        -PrefixLength $prefixLength `
        -DefaultGateway $gateway `
        -AddressFamily IPv4 `
        -ErrorAction Stop | Out-Null

    Write-Host "IP-Konfiguration erfolgreich aktualisiert." -ForegroundColor Green
} catch {
    Write-Error "Fehler beim Anwenden der Netzwerkkonfiguration: $($_.Exception.Message)"
    exit 1
}
