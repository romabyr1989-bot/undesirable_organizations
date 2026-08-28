# Сборка комплекта поставки для Windows.
#
#   .\scripts\build.ps1                          # собрать всё в dist\
#   .\scripts\build.ps1 -SkipUi                  # только сервер
#   .\scripts\build.ps1 -SqliteDll C:\sqlite3.dll  # своя библиотека SQLite
#   .\scripts\build.ps1 -Seed C:\perechen.xlsx     # свой стартовый файл
#   .\scripts\build.ps1 -NoSeed                    # без стартовых данных
#
# Результат: dist\perechen-<версия>-windows-<арх>\ и .zip рядом.
# Кросс-компиляции у Dart нет: комплект для Windows собирается на Windows.

[CmdletBinding()]
param(
    [switch] $SkipUi,
    [string] $SqliteDll = '',
    [switch] $NoSqliteDownload,
    [string] $Seed = '',
    [switch] $NoSeed
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = Split-Path -Parent $PSScriptRoot

function Assert-Command($name, $hint) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "не найден $name ($hint)"
    }
}

Assert-Command dart 'нужен Dart SDK >= 3.5'
if (-not $SkipUi) { Assert-Command flutter 'нужен Flutter >= 3.24, либо -SkipUi' }

$version = (Select-String -Path (Join-Path $root 'apps\server\pubspec.yaml') `
    -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()

switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { $arch = 'x64';   $sqliteArch = 'x64' }
    'ARM64' { $arch = 'arm64'; $sqliteArch = 'arm64' }
    default { $arch = $env:PROCESSOR_ARCHITECTURE.ToLower(); $sqliteArch = 'x64' }
}

$name  = "perechen-$version-windows-$arch"
$stage = Join-Path $root "dist\$name"

Write-Host "==> комплект $name"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
foreach ($dir in 'bin', 'lib', 'assets', 'packaging') {
    New-Item -ItemType Directory -Path (Join-Path $stage $dir) -Force | Out-Null
}

if (-not $SkipUi) {
    Write-Host '==> Flutter Web'
    Push-Location (Join-Path $root 'apps\ui')
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get завершился с ошибкой' }
        # --no-web-resources-cdn: CanvasKit в комплекте (закрытый контур),
        # --pwa-strategy=none: без служебного воркера, кеширующего сборку.
        & flutter build web --release --no-web-resources-cdn --pwa-strategy=none
        # Заглушка поверх пустого файла, который оставляет сборка: снимает
        # регистрацию воркера у браузеров, открывавших сервис раньше.
        Copy-Item "$root/apps/ui/web/sw_killswitch.js" `
            "$root/apps/ui/build/web/flutter_service_worker.js" -Force
        if ($LASTEXITCODE -ne 0) { throw 'flutter build web завершился с ошибкой' }
    } finally { Pop-Location }
}

$webBuild = Join-Path $root 'apps\ui\build\web'
if (-not (Test-Path $webBuild)) { throw "нет собранного UI: $webBuild" }
Copy-Item $webBuild (Join-Path $stage 'web') -Recurse

Write-Host '==> сервер'
Push-Location (Join-Path $root 'apps\server')
try {
    & dart pub get
    if ($LASTEXITCODE -ne 0) { throw 'dart pub get завершился с ошибкой' }
    & dart compile exe 'bin\server.dart' -o (Join-Path $stage 'bin\perechen.exe')
    if ($LASTEXITCODE -ne 0) { throw 'dart compile exe завершился с ошибкой' }
} finally { Pop-Location }

Copy-Item (Join-Path $root 'packages\core\assets\countries_ru.txt') `
    (Join-Path $stage 'assets\countries_ru.txt')
# Недостающее звено цепочки сертификатов первоисточника: в закрытом контуре
# его неоткуда дотянуть, поэтому едет в комплекте.
Copy-Item (Join-Path $root 'apps\server\assets\ca-bundle.pem') `
    (Join-Path $stage 'assets\ca-bundle.pem')

# Стартовые данные: после установки интерфейс не должен встречать
# ответственного пустым списком. Сервис подхватит файл при первом запуске,
# пока база пуста. Не скачалось — комплект соберётся, список наполнится
# первой проверкой сайта.
$seedTarget = Join-Path $stage 'assets\perechen-seed.xlsx'
if ($Seed) {
    if (-not (Test-Path $Seed)) { throw "нет файла: $Seed" }
    Copy-Item $Seed $seedTarget
    Write-Host "    стартовые данные из файла: $Seed"
}
elseif (-not $NoSeed) {
    Write-Host '==> стартовые данные с сайта Минюста'
    $seedUrl = (Select-String -Path (Join-Path $root 'apps\server\config.example.yaml') `
        -Pattern '^MINJUST_EXPORT_URL:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
    try {
        Invoke-WebRequest -Uri $seedUrl -OutFile $seedTarget -UseBasicParsing -TimeoutSec 180
        Write-Host ("    скачано: {0} байт" -f (Get-Item $seedTarget).Length)
    }
    catch {
        Remove-Item $seedTarget -ErrorAction SilentlyContinue
        Write-Warning ("стартовые данные не скачались ({0})." -f $_.Exception.Message)
        Write-Warning 'После установки список будет пуст до первой проверки сайта.'
        Write-Warning 'Свой файл: -Seed <путь>; отказаться совсем: -NoSeed'
    }
}
Copy-Item (Join-Path $root 'apps\server\config.example.yaml') `
    (Join-Path $stage 'config.example.yaml')
Copy-Item (Join-Path $root 'packaging\windows\*') `
    (Join-Path $stage 'packaging') -Recurse
if (Test-Path (Join-Path $root 'README.md')) {
    Copy-Item (Join-Path $root 'README.md') (Join-Path $stage 'README.md')
}

# ------------------------------------------------------------- SQLite
# Системной libsqlite3 в Windows нет. Библиотеку кладём в комплект; если её
# не оказалось, сервис на Windows 10/Server 2016+ откатится на системную
# winsqlite3.dll (см. lib\src\db\sqlite_library.dart).
$libDir = Join-Path $stage 'lib'
if ($SqliteDll) {
    if (-not (Test-Path $SqliteDll)) { throw "нет файла: $SqliteDll" }
    Copy-Item $SqliteDll (Join-Path $libDir 'sqlite3.dll')
    Write-Host "    библиотека SQLite в комплекте: $SqliteDll"
}
elseif (-not $NoSqliteDownload) {
    try {
        Write-Host '==> скачиваем sqlite3.dll с sqlite.org'
        $page = Invoke-WebRequest -Uri 'https://sqlite.org/download.html' -UseBasicParsing
        $line = ($page.Content -split "`n") |
            Where-Object { $_ -match "^PRODUCT,.*sqlite-dll-win-$sqliteArch-" } |
            Select-Object -First 1
        if (-not $line) { throw "на sqlite.org нет сборки win-$sqliteArch" }
        $relative = ($line -split ',')[3]
        $zip = Join-Path $env:TEMP 'sqlite-dll.zip'
        Invoke-WebRequest -Uri "https://sqlite.org/$relative" -OutFile $zip -UseBasicParsing
        $unpacked = Join-Path $env:TEMP 'sqlite-dll'
        if (Test-Path $unpacked) { Remove-Item $unpacked -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $unpacked
        Copy-Item (Join-Path $unpacked 'sqlite3.dll') (Join-Path $libDir 'sqlite3.dll')
        Remove-Item $zip, $unpacked -Recurse -Force
        Write-Host "    библиотека SQLite в комплекте: $relative"
    }
    catch {
        Write-Warning ("sqlite3.dll не скачалась ({0}). " -f $_.Exception.Message)
        Write-Warning 'Комплект соберётся, служба возьмёт системную winsqlite3.dll.'
        Write-Warning 'Свою библиотеку можно добавить: -SqliteDll <путь к sqlite3.dll>'
    }
}

Write-Host '==> проверка комплекта'
& (Join-Path $stage 'bin\perechen.exe') paths
if ($LASTEXITCODE -ne 0) { throw "'perechen paths' завершился с ошибкой" }

Write-Host '==> архив'
$zipPath = Join-Path $root "dist\$name.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $stage -DestinationPath $zipPath

Write-Host ''
Write-Host "Готово:"
Write-Host "  каталог: dist\$name"
Write-Host "  архив:   dist\$name.zip"
Write-Host ''
Write-Host 'Установка службы (в консоли администратора):'
Write-Host "  dist\$name\packaging\install.ps1"
