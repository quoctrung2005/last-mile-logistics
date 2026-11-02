param(
    [string]$SdkRoot = 'D:\AndroidSDK',
    [string]$FlutterRoot = 'D:\flutter',
    [string]$AvdName = 'TVD_Shipper'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$appRoot = Join-Path $projectRoot 'app_shipper'
$flutter = Join-Path $FlutterRoot 'bin\flutter.bat'
$adb = Join-Path $SdkRoot 'platform-tools\adb.exe'
foreach ($required in @($flutter, $adb)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing tool: $required" }
}
$studioPaths = @('D:\AndroidStudio', 'C:\Program Files\Android\Android Studio')
$studioRoot = $studioPaths | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'jbr\bin\java.exe') } | Select-Object -First 1
if (-not $studioRoot) { throw 'Android Studio Java runtime was not found.' }
$env:JAVA_HOME = Join-Path $studioRoot 'jbr'
$env:ANDROID_HOME = $SdkRoot
$env:ANDROID_SDK_ROOT = $SdkRoot
$env:ANDROID_AVD_HOME = 'D:\AndroidAVD'
$env:ANDROID_USER_HOME = 'D:\AndroidUserHome'
$env:PUB_CACHE = 'D:\FlutterPubCache'
$env:GRADLE_USER_HOME = 'D:\GradleCache'
$env:Path = (Join-Path $FlutterRoot 'bin') + ';' + (Join-Path $SdkRoot 'platform-tools') + ';' + (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:Path

$apiAvailable = $false
$tcp = New-Object Net.Sockets.TcpClient
try { $apiAvailable = $tcp.ConnectAsync('127.0.0.1', 5038).Wait(1500) -and $tcp.Connected } catch {} finally { $tcp.Dispose() }
if (-not $apiAvailable) {
    throw 'Start the shared backend first: .\tools\start-shared-api.ps1'
}

$device = 'emulator-5554'
$devices = & $adb devices
if (-not ($devices -match '^emulator-5554\s')) {
    $emulator = Join-Path $SdkRoot 'emulator\emulator.exe'
    Start-Process -FilePath $emulator -ArgumentList @('-avd', $AvdName, '-port', '5554', '-memory', '2048', '-cores', '2', '-no-snapshot-save') -WindowStyle Normal | Out-Null
}
Write-Host 'Waiting for Android...'
$ready = $false
for ($attempt = 0; $attempt -lt 180; $attempt++) {
    $boot = & $adb -s $device shell getprop sys.boot_completed 2>$null
    if ($LASTEXITCODE -eq 0 -and "$boot".Trim() -eq '1') { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ready) { throw 'Android did not finish starting. Check the emulator window.' }

Push-Location $appRoot
try {
    & $flutter run -d $device --dart-define=API_BASE_URL=http://10.0.2.2:5038
    if ($LASTEXITCODE -ne 0) { throw 'The shipper app did not start successfully.' }
} finally {
    Pop-Location
}
