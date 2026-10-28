## 하네스: GIST 아침·점심·저녁식단 알림

**목표:** GIST 제1·제2학생식당 게시판에서 오늘 아침·점심·저녁식단을 찾아 메모장으로 화면에 띄운다(매일 08:00 아침, 11:30 점심, 17:30 저녁 자동 실행).

**호출 조건:** 학식·아침·점심·저녁식단·GIST 식단 관련 요청을 받으면 `gist-meal` 스킬을 사용한다.

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
| --- | --- | --- | --- |
| 2026-10-22 | Harness v2로 처음 구성 | 전체 | - |
| 2026-10-22 | 점심 추가: 스킬 `gist-dinner`→`gist-meal`(lunch/dinner 인자), 추출 결과를 일품/한식 구역(sections)으로 저장, `run_meal.cmd` + 11:30 예약 | gist-meal, menu-extractor, menu-extraction, show_menu.py | 사용자 요청 |
| 2026-10-22 | 아침 추가: breakfast 끼니, 08:00 예약 | gist-meal, menu-extractor, menu-extraction, show_menu.py, run_meal.cmd | 사용자 요청 |
| 2026-10-22 | 카카오톡 '나에게 보내기' 전송 추가(예약 실행 시) | kakao_send.py, run_meal.cmd, gist-meal | 사용자 요청 |
| 2026-10-22 | 배포 가능하게 정리: install/uninstall 스크립트, config.cmd(경로·카톡 설정), README, .gitignore, 배포 zip | run_meal.cmd, install.ps1, uninstall.ps1, README.md | 다른 사람도 설치해 쓰도록 |
| 2026-10-22 | '로그인 없이 실행' 모드: S4U -Menu 작업 + 로그인 시 메모장 -Popup 작업, 절전 깨우기, 설치·제거 시 관리자 자동 요청 | install.ps1, uninstall.ps1, run_meal.cmd, show_popup.cmd, show_menu.py, README | 사용자 요청 |
| 2026-10-28 | 첨부 다운로드를 `?mode=D`(→/error/ 404)에서 PDF 뷰어 경로·`?mode=IMG`로 변경, 실패 URL을 에러에 기록 | fetch_menu.py | 사이트 변경으로 수집 실패 |
| 2026-10-28 | menu-extractor가 스킬 파일 경로를 직접 Read하도록 명시(Skill 도구 없음, 작업 폴더 밖 Glob 거부) | menu-extractor, gist-meal | 예약 실행에서 스킬을 못 읽음 |
