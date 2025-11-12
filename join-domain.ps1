#Requires -RunAsAdministrator

# .Skript zum Joinen einer Windows-Installation an die Domäne contoso.local.
# Fragt Benutzername und Kennwort ab, erstellt entsprechende Credentials und
# führt anschließend den Domain Join aus. Ein Neustart wird bewusst nicht
# ausgelöst, damit das Skript während des Unattended-Setups sicher läuft.

$domainFqdn = 'contoso.local'
$domainNetbios = $domainFqdn.Split('.')[0]

function Read-NonEmptyString {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    while ($true) {
        $value = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }

        Write-Warning "Eingabe darf nicht leer sein."
    }
}

$usernameInput = Read-NonEmptyString -Prompt "Domänenkonto (z.B. $domainNetbios\\Administrator oder nur Benutzername)"
$password = Read-Host "Kennwort" -AsSecureString

if ($usernameInput -notmatch '^[^\\]+\\[^\\]+$') {
    # Benutzer hat vermutlich nur den Namen angegeben -> Domänenpräfix ergänzen.
    $username = "$domainNetbios\$usernameInput"
} else {
    $username = $usernameInput
}

$credential = New-Object System.Management.Automation.PSCredential($username, $password)

try {
    Write-Host "Führe Domain Join zu '$domainFqdn' durch ..." -ForegroundColor Cyan
    Add-Computer -DomainName $domainFqdn -Credential $credential -ErrorAction Stop
    Write-Host "Domain Join erfolgreich." -ForegroundColor Green
} catch {
    Write-Error "Domain Join fehlgeschlagen: $($_.Exception.Message)"
    exit 1
}

Write-Host "Bitte das System nach Abschluss des Setups manuell neu starten, damit der Domain Join vollständig wirksam wird." -ForegroundColor Yellow
