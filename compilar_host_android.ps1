$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$guestAssets = Join-Path $projectRoot 'assets\guest_web'
$webBuild = Join-Path $projectRoot 'build\web'

if (-not $guestAssets.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destino de assets inválido.'
}

Set-Location -LiteralPath $projectRoot
New-Item -ItemType Directory -Force -Path $guestAssets | Out-Null

Get-ChildItem -LiteralPath $guestAssets -Force |
    Where-Object { $_.Name -ne '.gitkeep' } |
    Remove-Item -Recurse -Force

Write-Host '1/3 - Preparando dependências...'
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar as dependências.' }

Write-Host '2/3 - Compilando a página dos participantes...'
flutter build web --release --pwa-strategy=none
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar a versão web.' }

Copy-Item -Path (Join-Path $webBuild '*') -Destination $guestAssets -Recurse -Force

Write-Host '3/3 - Compilando o aplicativo Android do anfitrião...'
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o APK.' }

Write-Host ''
Write-Host 'Compilação concluída.' -ForegroundColor Green
Write-Host 'APK: build\app\outputs\flutter-apk\app-release.apk'
