# Android 디버그 APK 만들기 (docs/android-build.md).
# 필요: Godot 4.7.2 콘솔 실행 파일과 같은 버전의 export templates, JDK 17, Android SDK(build-tools·platform).
# JDK·SDK 경로와 디버그 키는 Godot 편집기 설정(%APPDATA%\Godot\editor_settings-4.7.tres)에 있다. 저장소에는 넣지 않는다.
# 사용: .\tools\build-android.ps1 [-Install]   (-Install: 연결된 기기에 adb로 설치)
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Install,
    [string]$Sdk = $env:ANDROID_HOME
)
$repo = Split-Path $PSScriptRoot -Parent
$runGodot = Join-Path $PSScriptRoot "run-godot.ps1"
$outDir = Join-Path $repo "build\android"
$apk = Join-Path $outDir "gyeol-prototype-debug.apk"
New-Item -ItemType Directory -Force $outDir | Out-Null

# 새 자산·설정이 있으면 먼저 불러오기 캐시를 만든다.
& $runGodot -Timeout 300 --headless --editor --path (Join-Path $repo "game") --import | Out-Null
& $runGodot -Timeout 900 --headless --path (Join-Path $repo "game") --export-debug "Android" "../build/android/gyeol-prototype-debug.apk" |
    Where-Object { $_ -match 'ERROR|Signed|build tools' }
if (-not (Test-Path $apk)) { Write-Output "APK를 만들지 못했습니다."; exit 1 }
$hash = (Get-FileHash $apk -Algorithm SHA256).Hash
Write-Output ("APK: {0} ({1:N0} bytes) SHA256 {2}" -f $apk, (Get-Item $apk).Length, $hash)

if ($Install) {
    if (-not $Sdk) { $Sdk = "C:\Users\my\AndroidDev\sdk" }
    $adb = Join-Path $Sdk "platform-tools\adb.exe"
    & $adb devices
    & $adb install -r $apk
}
