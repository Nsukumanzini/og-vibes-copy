$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

$releaseConfig = 'config\release.json'
if (-not (Test-Path -LiteralPath $releaseConfig)) {
    throw "Missing $releaseConfig. Add the public release configuration before building."
}

# Windows Application Control can block Flutter's font-subset.exe. Keeping the
# complete icon fonts avoids that executable while preserving every app icon.
flutter build web `
    --release `
    --no-wasm-dry-run `
    --no-tree-shake-icons `
    --dart-define-from-file=$releaseConfig

if ($LASTEXITCODE -ne 0) {
    throw 'Student web release build failed.'
}

# Keep the static-host routing rules and Vercel project link with the generated
# web release so deploying from build\web always targets the student app.
Copy-Item -LiteralPath 'web\vercel.json' -Destination 'build\web\vercel.json' -Force
if (Test-Path -LiteralPath '.vercel\project.json') {
    New-Item -ItemType Directory -Path 'build\web\.vercel' -Force | Out-Null
    Copy-Item -LiteralPath '.vercel\project.json' -Destination 'build\web\.vercel\project.json' -Force
}

Write-Output 'Student web release is ready in build\web.'
