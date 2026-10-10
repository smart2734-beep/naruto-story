# Godot를 시간 제한과 함께 실행한다. 스크립트 오류로 헤드리스 실행이 멈추지 않게 하려는 개발용 도우미.
# 사용: .\tools\run-godot.ps1 -Timeout 300 --headless --path game ++ --autotest
#   PowerShell이 '--'를 먹어 버리므로, Godot의 사용자 인자 구분자는 '++'로 적는다.
[CmdletBinding(PositionalBinding = $false)]
param(
    [int]$Timeout = 300,
    [string]$Godot = $env:GODOT_CONSOLE,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$GodotArgs
)
if (-not $Godot) { $Godot = "C:\Users\my\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" }
$out = [IO.Path]::GetTempFileName()
$err = [IO.Path]::GetTempFileName()
$quoted = $GodotArgs | ForEach-Object { if ($_ -eq '++') { '--' } else { $_ } } | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
$p = Start-Process -FilePath $Godot -ArgumentList $quoted -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
if (-not $p.WaitForExit($Timeout * 1000)) {
    $p.Kill()
    Get-Content -Encoding utf8 $out, $err
    Write-Output "TIMEOUT after $Timeout s"
    exit 124
}
Get-Content -Encoding utf8 $out, $err
exit $p.ExitCode
