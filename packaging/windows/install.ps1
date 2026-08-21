# Установка службы перечня 272-ФЗ на Windows.
#
#   .\install.ps1
#   .\install.ps1 -Port 8080 -CdiDir D:\cdi\inbox -OpenFirewall
#
# Запускать в консоли PowerShell от имени администратора.
# Повторный запуск обновляет установку, сохраняя данные и config.yaml.

[CmdletBinding()]
param(
    [string] $InstallDir = (Join-Path $env:ProgramFiles 'Perechen272FZ'),
    [string] $DataDir    = (Join-Path $env:ProgramData 'Perechen272FZ'),
    [string] $CdiDir     = '',
    [int]    $Port       = 8080,
    [switch] $OpenFirewall
)

$ErrorActionPreference = 'Stop'
$taskName = 'Perechen272FZ'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal] $identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'нужны права администратора: запустите PowerShell «от имени администратора»'
}

# Путь Windows в yaml — только в одинарных кавычках: обратный слэш там
# литерал, а внутренняя кавычка удваивается.
function ConvertTo-YamlString([string] $value) {
    "'" + $value.Replace("'", "''") + "'"
}

$bundle = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $bundle 'bin\perechen.exe'))) {
    throw "в комплекте нет bin\perechen.exe: $bundle"
}

if (-not $CdiDir) { $CdiDir = Join-Path $DataDir 'cdi-inbox' }
$configPath = Join-Path $DataDir 'config.yaml'
$logPath    = Join-Path $DataDir 'logs\perechen.log'

# Задача может быть запущена: останавливаем перед заменой файлов.
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host '==> останавливаем текущую задачу'
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    # Планировщик отпускает файл не мгновенно.
    Start-Sleep -Seconds 2
}

Write-Host "==> файлы в $InstallDir"
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
foreach ($item in 'bin', 'lib', 'web', 'assets', 'packaging') {
    $source = Join-Path $bundle $item
    if (-not (Test-Path $source)) { continue }
    $target = Join-Path $InstallDir $item
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    Copy-Item $source $target -Recurse
}
foreach ($file in 'README.md', 'config.example.yaml') {
    $source = Join-Path $bundle $file
    if (Test-Path $source) { Copy-Item $source (Join-Path $InstallDir $file) -Force }
}

Write-Host '==> каталоги данных'
foreach ($dir in $DataDir, (Join-Path $DataDir 'downloads'),
                 (Join-Path $DataDir 'published'), (Join-Path $DataDir 'logs'),
                 $CdiDir) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

Write-Host "==> конфигурация $configPath"
if (Test-Path $configPath) {
    Write-Host '    файл уже есть — оставляем как есть'
}
else {
    # Пути Windows содержат обратные слэши: в YAML берём их в одинарные
    # кавычки, иначе \P и \c читаются как escape-последовательности.
    # Пути правим построчно, а не -replace: в строке замены знак доллара
    # значим для регулярных выражений, а он встречается в UNC-путях
    # административных ресурсов (\\server\d$\cdi).
    $lines = Get-Content (Join-Path $bundle 'config.example.yaml') -Encoding UTF8
    $text = foreach ($line in $lines) {
        switch -Regex ($line) {
            '^DATA_DIR:'      { 'DATA_DIR: '     + (ConvertTo-YamlString $DataDir); break }
            '^CDI_DROP_DIR:'  { 'CDI_DROP_DIR: ' + (ConvertTo-YamlString $CdiDir);  break }
            '^#?\s*LOG_FILE:' { 'LOG_FILE: '     + (ConvertTo-YamlString $logPath); break }
            '^PORT:'          { "PORT: $Port"; break }
            default           { $line }
        }
    }
    # Строго UTF-8 без BOM: разбор yaml на стороне службы спотыкается о BOM,
    # а Set-Content -Encoding UTF8 в Windows PowerShell 5.1 его добавляет.
    [System.IO.File]::WriteAllLines(
        $configPath, [string[]] $text, (New-Object System.Text.UTF8Encoding $false))
    # В файле пароли SMTP и basic-auth: доступ только SYSTEM и администраторам.
    # SID вместо имён — они переведены в русской Windows.
    & icacls $configPath /inheritance:r /grant:r '*S-1-5-18:(R)' '*S-1-5-32-544:(F)' |
        Out-Null
}

Write-Host "==> задача автозапуска «$taskName»"
# Служба Windows требует от программы протокола SCM, у консольного бинарника
# его нет. Задача планировщика от SYSTEM даёт то же самое: старт при загрузке
# ОС без входа пользователя и перезапуск после сбоя.
$action = New-ScheduledTaskAction `
    -Execute (Join-Path $InstallDir 'bin\perechen.exe') `
    -Argument ('--config "{0}"' -f $configPath) `
    -WorkingDirectory $InstallDir
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
    -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description 'Сервис перечня «нежелательных организаций» (272-ФЗ)' `
    -Force | Out-Null

if ($OpenFirewall) {
    Write-Host "==> правило брандмауэра на порт $Port"
    $ruleName = "Perechen272FZ (TCP $Port)"
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $Port | Out-Null
}

Write-Host '==> запуск'
Start-ScheduledTask -TaskName $taskName

$listening = $false
foreach ($attempt in 1..15) {
    Start-Sleep -Seconds 1
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/health" `
            -UseBasicParsing -TimeoutSec 3 | Out-Null
        $listening = $true; break
    }
    catch {
        # 401 значит, что сервер поднялся и требует пароль — это успех.
        if ($_.Exception.Response -and
            [int]$_.Exception.Response.StatusCode -eq 401) { $listening = $true; break }
    }
}

if (-not $listening) {
    Write-Warning 'служба не ответила за 15 секунд. Журнал:'
    if (Test-Path $logPath) { Get-Content $logPath -Tail 30 }
    Write-Warning "Состояние задачи: (Get-ScheduledTask -TaskName $taskName).State"
    exit 1
}

Write-Host ''
Write-Host 'Установлено.'
Write-Host "  программа:      $InstallDir"
Write-Host "  данные:         $DataDir"
Write-Host "  папка CDI:      $CdiDir"
Write-Host "  конфигурация:   $configPath   <- задайте SMTP, получателей, пароль"
Write-Host "  журнал:         $logPath"
Write-Host "  интерфейс:      http://$($env:COMPUTERNAME):$Port"
Write-Host ''
Write-Host 'Дальше:'
Write-Host "  notepad $configPath"
Write-Host "  Stop-ScheduledTask $taskName ; Start-ScheduledTask $taskName"
Write-Host "  Get-Content '$logPath' -Wait -Tail 20"
Write-Host "  & '$InstallDir\bin\perechen.exe' paths --config '$configPath'"
