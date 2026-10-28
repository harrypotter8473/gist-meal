<#
GIST 학식 알림 설치 스크립트.
- 필요한 프로그램(Python, Claude Code, pdftotext)을 확인한다.
- 알림 받을 끼니·시각을 정하고 Windows 작업 스케줄러에 등록한다.
- (선택) 카카오톡 '나에게 보내기'를 인증한다.
- (선택) 로그인하지 않아도 전원만 켜져 있으면 실행되게 한다(관리자 승인 필요).
보통은 install.cmd를 더블클릭해서 실행한다. 다시 실행하면 설정을 덮어쓴다.
#>
param(
    [string[]]$Meals,
    [string]$BreakfastTime = "08:00",
    [string]$LunchTime = "11:30",
    [string]$DinnerTime = "17:30",
    [string]$TaskPrefix = "GIST",
    [ValidateSet("ask", "yes", "no")][string]$Kakao = "ask",
    [string]$KakaoKey,
    [string]$KakaoSecret,
    [ValidateSet("ask", "yes", "no")][string]$RunLoggedOff = "ask",
    [switch]$NonInteractive,
    [switch]$SkipTestRun
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$MealNames = [ordered]@{ breakfast = "아침"; lunch = "점심"; dinner = "저녁" }
$DefaultTimes = @{ breakfast = $BreakfastTime; lunch = $LunchTime; dinner = $DinnerTime }

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }
function Fail($msg) { Say "`n[중단] $msg" Red; if (-not $NonInteractive) { Read-Host "Enter를 누르면 닫힙니다" | Out-Null }; exit 1 }
function Ask($question, $default) {
    if ($NonInteractive) { return $default }
    $answer = Read-Host "$question [$default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $default } else { return $answer.Trim() }
}
function AskYesNo($question, $default) {
    $answer = Ask "$question (y/n)" $(if ($default) { "y" } else { "n" })
    return $answer -match '^(y|yes|예|네|ㅇ)'
}

Say "`n=== GIST 학식 알림 설치 ===`n" Cyan

# 1. Python 3.10 이상 (스크립트가 3.10 문법을 쓴다)
$PythonExe = $null
foreach ($candidate in @("python", "py")) {
    if (-not (Get-Command $candidate -ErrorAction SilentlyContinue)) { continue }
    try {
        $out = & $candidate -c "import sys; print(sys.executable); print(sys.version_info >= (3, 10))" 2>$null
        if ($LASTEXITCODE -eq 0 -and $out.Count -ge 2 -and $out[1] -eq "True") { $PythonExe = $out[0]; break }
    } catch { }
}
if (-not $PythonExe) { Fail "Python 3.10 이상이 필요합니다. https://www.python.org/downloads/ 에서 설치할 때 'Add python.exe to PATH'를 체크하세요." }
Say "[확인] Python: $PythonExe" Green

# 2. Claude Code
$ClaudeExe = $null
$cmd = Get-Command claude -ErrorAction SilentlyContinue
if ($cmd) { $ClaudeExe = $cmd.Source }
foreach ($p in @("$env:USERPROFILE\.local\bin\claude.exe", "$env:APPDATA\npm\claude.cmd")) {
    if (-not $ClaudeExe -and (Test-Path $p)) { $ClaudeExe = $p }
}
if (-not $ClaudeExe) { Fail "Claude Code가 필요합니다. https://claude.com/claude-code 안내대로 설치한 뒤, 터미널에서 'claude'를 한 번 실행해 로그인하세요." }
Say "[확인] Claude Code: $ClaudeExe" Green
Say "       (아직 로그인하지 않았다면 터미널에서 'claude'를 한 번 실행해 로그인해 두세요)"

# 3. pdftotext (선택: 없으면 이미지 판독만 한다)
$pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
if (-not $pdftotext) {
    $pdftotext = @("C:\Program Files\Git\mingw64\bin\pdftotext.exe", "C:\Program Files (x86)\Git\mingw64\bin\pdftotext.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
if ($pdftotext) { Say "[확인] pdftotext 있음 (식단표 글자 교차 확인 가능)" Green }
else { Say "[참고] pdftotext가 없습니다. 동작은 하지만 판독 정확도를 높이려면 Git for Windows(https://git-scm.com)를 설치하세요." Yellow }

# 3-1. 로그인하지 않아도 실행 (작업 스케줄러 S4U 방식은 관리자 권한으로만 등록할 수 있다)
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Say "`n--- 실행 조건 ---" Cyan
$LoggedOff = switch ($RunLoggedOff) {
    "yes" { $true } "no" { $false }
    default { AskYesNo "PC에 로그인하지 않아도(전원만 켜져 있으면) 실행할까요? 이때는 메모장 대신 카카오톡으로 알림을 받게 됩니다. (관리자 승인 필요)" $false }
}
if ($LoggedOff -and -not $IsAdmin) {
    Say "관리자 권한이 필요합니다. 잠시 뒤 뜨는 '사용자 계정 컨트롤' 창에서 [예]를 눌러 주세요." Yellow
    $relaunch = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-RunLoggedOff", "yes")
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Key -eq "RunLoggedOff") { continue }
        if ($kv.Value -is [switch]) { if ($kv.Value) { $relaunch += "-$($kv.Key)" } }
        elseif ($kv.Value -is [array]) { $relaunch += "-$($kv.Key)"; $relaunch += ($kv.Value -join ",") }
        else { $relaunch += "-$($kv.Key)"; $relaunch += "`"$($kv.Value)`"" }
    }
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $relaunch -Wait }
    catch { Fail "관리자 권한을 받지 못했습니다. 로그인 상태에서만 실행하려면 install.cmd를 다시 실행해 이 질문에 n으로 답하세요." }
    exit 0
}

# 4. 끼니와 시각
Say "`n--- 알림 시각 설정 ---" Cyan
if (-not $Meals) {
    $Meals = @()
    foreach ($meal in $MealNames.Keys) {
        if (AskYesNo "$($MealNames[$meal]) 식단을 받을까요?" $true) { $Meals += $meal }
    }
}
if ($Meals.Count -eq 0) { Fail "받을 끼니를 하나 이상 골라야 합니다." }
$Times = @{}
foreach ($meal in $Meals) {
    if (-not $MealNames.Contains($meal)) { Fail "알 수 없는 끼니: $meal (breakfast, lunch, dinner 중에서)" }
    $t = Ask "$($MealNames[$meal]) 알림 시각 (HH:mm)" $DefaultTimes[$meal]
    if ($t -notmatch '^([01]\d|2[0-3]):[0-5]\d$') { Fail "시각 형식이 잘못되었습니다: $t (예: 08:00)" }
    $Times[$meal] = $t
}

# 5. 카카오톡 (선택)
Say "`n--- 카카오톡 알림 (선택) ---" Cyan
$UseKakao = switch ($Kakao) { "yes" { $true } "no" { $false } default { AskYesNo "카카오톡 '나에게 보내기'로도 받을까요? (카카오 개발자 앱 설정 필요, README 참고)" $false } }
$KakaoOk = $false
if ($UseKakao) {
    if (-not $KakaoKey) { $KakaoKey = Ask "REST API 키" "" }
    if (-not $KakaoSecret -and -not $NonInteractive) { $KakaoSecret = Read-Host "Client Secret (사용하지 않으면 그냥 Enter)" }
    if ([string]::IsNullOrWhiteSpace($KakaoKey)) {
        Say "[건너뜀] REST API 키가 없어 카카오톡 설정을 건너뜁니다. 나중에 install.cmd를 다시 실행하면 됩니다." Yellow
    } else {
        Say "브라우저가 열리면 카카오 로그인 후 '동의하고 계속하기'를 누르세요."
        $authArgs = @("$Root\.claude\skills\gist-meal\scripts\kakao_send.py", "auth", "--key", $KakaoKey)
        if ($KakaoSecret) { $authArgs += @("--secret", $KakaoSecret) }
        & $PythonExe @authArgs
        if ($LASTEXITCODE -eq 0) {
            & $PythonExe "$Root\.claude\skills\gist-meal\scripts\kakao_send.py" test
            $KakaoOk = ($LASTEXITCODE -eq 0)
        }
        if ($KakaoOk) { Say "[완료] 카카오톡 테스트 메시지를 보냈습니다. '나와의 채팅'을 확인하세요." Green }
        else { Say "[실패] 카카오톡 인증/전송에 실패했습니다. README의 카카오 설정을 확인한 뒤 install.cmd를 다시 실행하세요. (메모장 알림은 정상 설치됩니다)" Yellow }
    }
} elseif (Test-Path "$Root\.secrets\kakao.json") {
    # 이전에 인증해 둔 경우: 묻지 않고 유지할지 결정
    $KakaoOk = AskYesNo "이전에 인증한 카카오톡 정보가 있습니다. 계속 카톡으로 받을까요?" $true
}

if ($LoggedOff -and -not $KakaoOk) {
    Say "[주의] 카카오톡 없이 '로그인 없이 실행'을 켜면, 로그인하지 않은 동안에는 알림을 볼 방법이 없습니다(결과는 output 폴더에 저장됨)." Yellow
}

# 6. 설정 파일 (run_meal.cmd가 읽는다)
$config = @(
    "@echo off",
    "rem Generated by install.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Re-run install.cmd to change.",
    "set `"CLAUDE_EXE=$ClaudeExe`"",
    "set `"PYTHON_EXE=$PythonExe`"",
    "set KAKAO=$(if ($KakaoOk) { 1 } else { 0 })"
)
[IO.File]::WriteAllLines("$Root\config.cmd", $config, (New-Object Text.UTF8Encoding $false))
Say "`n[완료] 설정 저장: $Root\config.cmd" Green

# 7. 작업 스케줄러 등록 (선택하지 않은 끼니의 기존 작업은 지운다)
#   일반 모드: {prefix}-{Meal}-Menu 하나가 로그인 상태에서 메모장까지 띄운다.
#   로그오프 모드: -Menu는 S4U(로그인 없이, 화면 없음)로 식단 판독·카톡·파일 저장만 하고,
#                  -Popup이 로그인 상태일 때만 그 파일을 메모장으로 연다(Claude를 부르지 않음).
$Me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
foreach ($meal in $MealNames.Keys) {
    $title = (Get-Culture).TextInfo.ToTitleCase($meal)
    $menuTask = "$TaskPrefix-$title-Menu"
    $popupTask = "$TaskPrefix-$title-Popup"
    if ($Meals -contains $meal) {
        $trigger = New-ScheduledTaskTrigger -Daily -At $Times[$meal]
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -WakeToRun:$LoggedOff
        if ($LoggedOff) {
            $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"`"$Root\run_meal.cmd`" $meal nopopup`"" -WorkingDirectory $Root
            $principal = New-ScheduledTaskPrincipal -UserId $Me -LogonType S4U -RunLevel Limited
            Register-ScheduledTask -TaskName $menuTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
                -Description "GIST 학식 알림 ($($MealNames[$meal])) - 로그인 없이 실행" -Force | Out-Null
            $popupAction = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start `"`" /min `"$Root\show_popup.cmd`" $meal" -WorkingDirectory $Root
            $popupPrincipal = New-ScheduledTaskPrincipal -UserId $Me -LogonType Interactive -RunLevel Limited
            Register-ScheduledTask -TaskName $popupTask -Action $popupAction -Trigger $trigger -Principal $popupPrincipal `
                -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 20)) `
                -Description "GIST 학식 알림 ($($MealNames[$meal])) - 로그인 상태면 메모장 표시" -Force | Out-Null
            Say "[등록] $menuTask  매일 $($Times[$meal])  (로그인 없이 실행, 절전 중이면 깨움)" Green
            Say "[등록] $popupTask  매일 $($Times[$meal])  (로그인 상태일 때 메모장)" Green
        } else {
            $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start `"`" /min `"$Root\run_meal.cmd`" $meal" -WorkingDirectory $Root
            Register-ScheduledTask -TaskName $menuTask -Action $action -Trigger $trigger -Settings $settings `
                -Description "GIST 학식 알림 ($($MealNames[$meal]))" -Force | Out-Null
            if (Get-ScheduledTask -TaskName $popupTask -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $popupTask -Confirm:$false }
            Say "[등록] $menuTask  매일 $($Times[$meal])" Green
        }
    } else {
        foreach ($name in @($menuTask, $popupTask)) {
            if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $name -Confirm:$false
                Say "[삭제] $name" Yellow
            }
        }
    }
}

# 8. 테스트 실행
if (-not $SkipTestRun -and (AskYesNo "`n지금 한 번 실행해서 확인해 볼까요? (1~2분 걸리고, 메모장이 뜹니다)" $true)) {
    $hour = (Get-Date).Hour
    $testMeal = if ($hour -lt 10) { "breakfast" } elseif ($hour -lt 15) { "lunch" } else { "dinner" }
    Say "$($MealNames[$testMeal]) 식단으로 테스트합니다..."
    $today = Get-Date -Format "yyyy-MM-dd"
    if ($LoggedOff -and ($Meals -contains $testMeal)) {
        # 로그인 없이 도는 실제 작업을 그대로 실행해 본다(권한·로그인 문제를 여기서 잡기 위해).
        $task = "$TaskPrefix-$((Get-Culture).TextInfo.ToTitleCase($testMeal))-Menu"
        Remove-Item "$Root\output\${testMeal}_$today.txt" -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName $task
        Start-Sleep -Seconds 5
        while ((Get-ScheduledTask -TaskName $task).State -eq "Running") { Start-Sleep -Seconds 5 }
        if (Test-Path "$Root\output\${testMeal}_$today.txt") { Start-Process notepad.exe "$Root\output\${testMeal}_$today.txt" }
    } else {
        & cmd.exe /c "`"$Root\run_meal.cmd`" $testMeal"
    }
    if (Test-Path "$Root\output\${testMeal}_$today.txt") { Say "[완료] 테스트 성공. 메모장을 확인하세요." Green }
    else { Say "[확인 필요] 결과 파일이 없습니다. $Root\logs\${today}_$testMeal.log 를 확인하세요. (Claude Code 로그인 여부를 먼저 확인)" Yellow }
}

Say "`n설치가 끝났습니다. 설정을 바꾸려면 install.cmd를, 제거하려면 uninstall.cmd를 실행하세요.`n" Cyan
if (-not $NonInteractive) { Read-Host "Enter를 누르면 닫힙니다" | Out-Null }
