$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$androidDirectory = Join-Path $projectRoot 'android'
$keystorePath = Join-Path $androidDirectory 'app\og-vibes-upload.jks'
$propertiesPath = Join-Path $androidDirectory 'key.properties'

if ((Test-Path -LiteralPath $keystorePath) -or (Test-Path -LiteralPath $propertiesPath)) {
    throw 'Android signing files already exist. Nothing was overwritten.'
}

$keytool = Get-Command keytool -ErrorAction Stop

function New-SigningPassword {
    $bytes = New-Object byte[] 32
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    } finally {
        $generator.Dispose()
    }
    return 'OG' + [Convert]::ToBase64String($bytes).Replace('+', '-').Replace('/', '_').TrimEnd('=')
}

$storePassword = New-SigningPassword
$keyPassword = $storePassword

$distinguishedName = 'CN=OG Technologies, OU=OG Vibes, O=OG Technologies, L=Ermelo, ST=Mpumalanga, C=ZA'
$argumentLine = '-genkeypair -noprompt' +
    " -keystore `"$keystorePath`"" +
    ' -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000' +
    ' -alias og-vibes-upload' +
    " -storepass $storePassword -keypass $keyPassword" +
    " -dname `"$distinguishedName`""

$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $keytool.Source
$startInfo.Arguments = $argumentLine
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo
[void]$process.Start()
if (-not $process.WaitForExit(60000)) {
    $process.Kill()
    throw 'Keytool timed out while creating the upload keystore.'
}
$keytoolError = $process.StandardError.ReadToEnd()
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $keystorePath)) {
    if ($keytoolError) { Write-Error $keytoolError }
    throw 'Keytool did not create the OG Vibes upload keystore.'
}

$properties = @(
    "storePassword=$storePassword",
    "keyPassword=$keyPassword",
    'keyAlias=og-vibes-upload',
    'storeFile=og-vibes-upload.jks'
)
[System.IO.File]::WriteAllLines($propertiesPath, $properties, [System.Text.UTF8Encoding]::new($false))

Write-Output 'Android release signing is configured.'
Write-Output "Back up these two files securely: $keystorePath and $propertiesPath"
