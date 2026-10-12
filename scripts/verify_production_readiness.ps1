$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

$requiredFiles = @(
    'android\key.properties',
    'android\app\og-vibes-upload.jks',
    'android\app\google-services.json',
    'config\release.json',
    'web\firebase-messaging-sw.js'
)

$missing = $requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_) }
if ($missing) {
    Write-Output 'Missing production files:'
    $missing | ForEach-Object { Write-Output " - $_" }
    throw 'Production readiness check stopped.'
}

$releaseConfig = Get-Content -LiteralPath 'config\release.json' -Raw | ConvertFrom-Json
foreach ($name in @('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'FIREBASE_WEB_API_KEY', 'FIREBASE_WEB_VAPID_KEY')) {
    if (-not $releaseConfig.$name -or $releaseConfig.$name -match 'REPLACE|CHANGE_ME') {
        throw "config/release.json is missing $name"
    }
}

$manifest = Get-Content -LiteralPath 'android\app\src\main\AndroidManifest.xml' -Raw
if ($manifest.Contains('usesCleartextTraffic="true"')) {
    throw 'Android cleartext traffic is still enabled.'
}

$gradle = Get-Content -LiteralPath 'android\app\build.gradle.kts' -Raw
if ($gradle.Contains('signingConfig = signingConfigs.getByName("debug")')) {
    throw 'Android release builds are still using the debug key.'
}

$env:FLUTTER_ALREADY_LOCKED = 'true'
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
flutter test --no-pub
if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }

Write-Output 'OG Vibes production readiness checks passed.'
