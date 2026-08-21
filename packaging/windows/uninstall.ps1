# Удаление службы перечня 272-ФЗ с Windows.
#
#   .\uninstall.ps1           # снять задачу и программу, данные оставить
#   .\uninstall.ps1 -Purge    # удалить вместе с данными и настройками
#
# Запускать в консоли PowerShell от имени администратора.

[CmdletBinding()]
param(
    [string] $InstallDir = (Join-Path $env:ProgramFiles 'Perechen272FZ'),
    [string] $DataDir    = (Join-Path $env:ProgramData 'Perechen272FZ'),
    [switch] $Purge
)

$ErrorActionPreference = 'Stop'
$taskName = 'Perechen272FZ'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal] $identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'нужны права администратора: запустите PowerShell «от имени администратора»'
}

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

Get-NetFirewallRule -DisplayName 'Perechen272FZ*' -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }

if ($Purge) {
    if (Test-Path $DataDir) { Remove-Item $DataDir -Recurse -Force }
    Write-Host 'Удалено вместе с данными и настройками.'
}
else {
    Write-Host "Служба снята. Данные и настройки оставлены: $DataDir"
}
