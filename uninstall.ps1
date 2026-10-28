<#
GIST 학식 알림 제거: 작업 스케줄러 등록과 카카오톡 인증 정보를 지운다. 폴더 자체는 직접 지우면 된다.
'로그인 없이 실행'으로 설치했다면 작업 삭제에 관리자 승인이 필요해 자동으로 요청한다.
#>
param([string]$TaskPrefix = "GIST", [switch]$NonInteractive)

$Root = $PSScriptRoot
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$failed = @()
foreach ($meal in @("Breakfast", "Lunch", "Dinner")) {
    foreach ($kind in @("Menu", "Popup")) {
        $name = "$TaskPrefix-$meal-$kind"
        if (-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)) { continue }
        try {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
            Write-Host "[삭제] $name" -ForegroundColor Yellow
        } catch { $failed += $name }
    }
}
if ($failed.Count -gt 0) {
    if ($IsAdmin) { Write-Host "[실패] 삭제하지 못한 작업: $($failed -join ', ')" -ForegroundColor Red }
    else {
        Write-Host "관리자 권한이 필요한 작업이 있습니다. '사용자 계정 컨트롤' 창에서 [예]를 눌러 주세요." -ForegroundColor Yellow
        $args2 = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-TaskPrefix", $TaskPrefix)
        if ($NonInteractive) { $args2 += "-NonInteractive" }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $args2 -Wait
        exit 0
    }
}
foreach ($p in @("$Root\.secrets", "$Root\config.cmd")) {
    if (Test-Path $p) { Remove-Item -Recurse -Force $p; Write-Host "[삭제] $p" -ForegroundColor Yellow }
}
Write-Host "`n제거가 끝났습니다. 이제 이 폴더를 지워도 됩니다." -ForegroundColor Cyan
if (-not $NonInteractive) { Read-Host "Enter를 누르면 닫힙니다" | Out-Null }
