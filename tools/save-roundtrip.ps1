# 저장 재접속 점검. 시나리오마다
#   (1) write : 새 게임에서 그 지점까지 진행하고, 자동 저장된 상태 그대로 종료
#   (2) verify: 새 Godot 프로세스가 같은 저장 파일을 불러와 상태를 검사
# 메모리 변수 재설정이 아니라 실제 파일과 프로세스 재시작으로 확인한다 (docs/save-and-android-v0.1.md 3장).
# 사용: .\tools\save-roundtrip.ps1 [-Only q4_craft,q5_boss] [-Timeout 240]
[CmdletBinding(PositionalBinding = $false)]
param(
    [string[]]$Only = @(),
    [int]$Timeout = 240
)
$scenarios = @("q1_crate", "q1_reward", "q2_calm", "q2_follow", "q2_contract", "q3_gap", "q3_done",
    "q4_craft", "q4_early", "q4_contract", "q5_drain", "q5_boss", "q5_choice",
    "corrupt_main", "interrupted", "corrupt_all")
if ($Only.Count -gt 0) { $scenarios = @($scenarios | Where-Object { $Only -contains $_ }) }
$runGodot = Join-Path $PSScriptRoot "run-godot.ps1"
$game = Join-Path (Split-Path $PSScriptRoot -Parent) "game"
$results = @()
foreach ($s in $scenarios) {
    $path = "user://savetest_$s.json"
    $w = & $runGodot -Timeout $Timeout --headless --path $game ++ "--save-path=$path" "--save-scenario=$s" "--save-phase=write"
    $wcode = $LASTEXITCODE
    $stage = (($w | Where-Object { $_ -match 'SAVE WRITE DONE' }) -replace '.*stage=(\S+).*', '$1')
    $runs = 1
    if ($s -eq "q5_choice") { $runs = 2 }  # 두 번 연속 불러오기
    for ($i = 1; $i -le $runs; $i++) {
        $v = & $runGodot -Timeout $Timeout --headless --path $game ++ "--save-path=$path" "--save-scenario=$s" "--save-phase=verify"
        $vcode = $LASTEXITCODE
        Write-Output "--- $s (verify $i) ---"
        $v | Where-Object { $_ -match '\[OK\]|\[FAIL\]|SCRIPT ERROR|TIMEOUT' } | ForEach-Object { "  $_" }
        $results += [pscustomobject]@{ scenario = $s; verify_run = $i; saved_stage = $stage; write_exit = $wcode; verify_exit = $vcode }
    }
}
$results | Format-Table -AutoSize | Out-String
$bad = @($results | Where-Object { $_.write_exit -ne 0 -or $_.verify_exit -ne 0 })
Write-Output ("SAVE ROUNDTRIP: {0}/{1} PASS" -f ($results.Count - $bad.Count), $results.Count)
if ($bad.Count -gt 0) { exit 1 } else { exit 0 }
