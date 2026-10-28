---
name: gist-meal
description: "GIST 제1·제2학생식당 게시판에서 오늘(또는 지정한 날짜)의 아침·점심·저녁 중 한 끼 식단을 찾아 메모장으로 화면에 띄운다. 인자로 breakfast/lunch/dinner를 받는다. '오늘 아침 뭐야', '오늘 점심 뭐야', '저녁식단 보여줘', '학식', 'GIST 식단', '/gist-meal breakfast', '/gist-meal lunch', '/gist-meal dinner' 요청과 매일 08:00(아침)·11:30(점심)·17:30(저녁) 예약 실행에 사용한다. '다시 띄워줘', '내일 점심', '제2식당만 다시 읽어줘', '메뉴가 틀렸어 다시 확인해줘' 같은 재실행·수정 요청에도 사용한다."
---

# GIST 아침·점심·저녁식단 알림 (오케스트레이터)

## 실행 모드: 서브에이전트 위임
수집 → (식당별 병렬) 추출 → 표시 순서가 고정이고 에이전트끼리 대화할 필요가 없으므로 단발 서브에이전트로 위임한다.

| 단계 | 담당 | 산출물 |
|------|------|--------|
| 1. 수집 | `menu-fetcher` 서브에이전트 | `_workspace/{date}/manifest.json`, pdf/이미지/텍스트 |
| 2. 추출 | `menu-extractor` 서브에이전트 × 2 (병렬) | `_workspace/{date}/cafeteria{1,2}_{meal}.json` |
| 3. 표시 | 메인이 스크립트 실행 | `output/{meal}_{date}.txt` + 메모장 |

경로는 모두 이 프로젝트 루트(설치 폴더) 기준이다.

## 절차

### 0단계: 끼니·날짜와 기존 결과 확인
- 끼니(`{meal}`): 인자가 `breakfast`/`lunch`/`dinner`면 그대로. 인자가 없으면 요청 문장에서 판단하고("아침"·"조식"→breakfast, "점심"·"중식"→lunch, "저녁"·"석식"→dinner), 그래도 없으면 현재 시각 10시 전은 breakfast, 15시 전은 lunch, 이후는 dinner.
- 날짜: 지정하지 않으면 오늘(로컬 날짜). 이하 `{date}`는 `YYYY-MM-DD`.
- `_workspace/{date}/manifest.json`이 있고 두 식당 모두 `found: true`면 1단계를 건너뛴다. 아침 실행 때 받은 파일을 점심·저녁 실행이 다시 쓰는 경우다.
- 두 `{key}_{meal}.json`이 이미 있고 사용자가 "다시 띄워줘"만 요청했으면 3단계만 실행한다.
- "다시 확인해줘", "메뉴가 틀렸어"처럼 판독 오류를 지적하면 해당 식당의 `{key}_{meal}.json`을 지우고 그 식당만 2단계부터 다시 실행한다.

### 1단계: 수집
`Agent(subagent_type: "menu-fetcher", prompt: "날짜 {date}의 식단표를 수집하라.")`
- 반환 결과에서 manifest 경로와 식당별 found 여부를 확인한다.

### 2단계: 추출 (병렬)
**한 메시지에서** 두 Agent를 동시에 호출한다.
- `Agent(subagent_type: "menu-extractor", prompt: "식당 제1학생식당, key cafeteria1, 날짜 {date}, 끼니 {meal}, manifest _workspace/{date}/manifest.json. .claude/skills/menu-extraction/SKILL.md를 먼저 읽고 그 절차대로 메뉴를 추출해 저장하라.")`
- `Agent(subagent_type: "menu-extractor", prompt: "식당 제2학생식당, key cafeteria2, ...")`
- `found: false`인 식당도 호출한다. 에이전트가 `not_found` JSON을 남겨야 표시 단계에서 사유를 보여 줄 수 있다.

### 3단계: 표시
`python .claude/skills/gist-meal/scripts/show_menu.py --meal {meal} --date {date}`
- 텍스트 파일을 만들고 메모장을 띄운다. 출력된 파일 경로를 확인한다.
- 마지막으로 사용자에게 식당별 메뉴를 한 줄씩 요약해 답한다.

## 오류 처리
| 상황 | 대응 |
|------|------|
| 수집 실패(네트워크·사이트 구조 변경) | fetcher가 한 번 재시도한다. 그래도 실패하면 `show_menu.py --meal {meal} --fallback`으로 게시판 링크를 띄우고 원인을 보고한다. |
| 한 식당만 found: false | 정상 진행. 주말의 제1학생식당은 원래 없다. 메모장에 사유가 표시된다. |
| 추출 에이전트 실패 | 한 번 다시 호출한다. 다시 실패하면 그 식당 없이 3단계를 진행한다(메모장에 "식단 정보를 찾지 못했습니다"와 출처 링크가 표시됨). |
| 사용량 한도·인증 만료·권한 거부 | 재시도하지 않고 `show_menu.py --meal {meal} --fallback`을 실행한 뒤 원인을 보고한다. |
| 판독 결과가 `uncertain` | 그대로 표시한다(메모장에 원문 확인 권장 문구가 붙는다). 추측으로 고치지 않는다. |

## 예약 실행
Windows 작업 스케줄러가 `run_meal.cmd {meal}`을 실행한다: `GIST-Breakfast-Menu`(매일 08:00, breakfast), `GIST-Lunch-Menu`(매일 11:30, lunch), `GIST-Dinner-Menu`(매일 17:30, dinner). 이 파일은 `claude -p "/gist-meal {meal}"`를 호출하고, Claude가 결과 파일을 만들지 못하면 `show_menu.py --fallback`을 대신 실행한다. 그 다음 `kakao_send.py send --meal {meal}`로 카카오톡 '나에게 보내기'를 전송한다(식당당 1건, 실패 시 `--fallback`으로 링크만). '로그인 없이 실행'으로 설치하면 `-Menu` 작업이 S4U(화면 없음)로 `run_meal.cmd {meal} nopopup`을 실행하고(환경변수 `GIST_NO_POPUP=1` → show_menu가 메모장을 열지 않음), `-Popup` 작업이 로그인 상태일 때 `show_popup.cmd`로 결과 파일을 연다. 카톡 전송은 예약 실행에서만 하며, 대화 중 수동으로 이 스킬을 실행할 때는 보내지 않는다. 토큰: `.secrets/kakao.json`(만료 시 자동 갱신, 약 2개월 미사용 시 `kakao_send.py auth` 재실행 필요). 로그: `logs/{date}_{meal}.log`.

## 테스트 시나리오
### 정상 흐름 (저녁)
1. 2026-10-22(목) dinner 실행 → 두 식당 모두 found.
2. 제2학생식당: 흑미밥, 크림스프, 생선까스 & 타르S, 비엔나칠리볶음, 열무된장겉절이, 식빵크루통, 배추김치.

### 정상 흐름 (아침)
1. 2026-10-22(목) breakfast 실행.
2. 제1학생식당: 백미밥, 콩나물국, 계란찜, 돈육메알장조림, 치킨너겟*머스타드, 배추김치, 시리얼*우유, 토스트*잼, 야채샐러드 (셀프 라면코너 안내 제외).
3. 제2학생식당: 쌀밥 & 김치볶음밥, 소고기미역국, 계란후라이, 미트볼떡볶음, 오이지무침, 배추김치, 야채샐러드, 시리얼&요거트, 토스트&잼.

### 정상 흐름 (점심)
1. 2026-10-22(목) lunch 실행.
2. 제1학생식당 일품: 숯불맛고기국수, 타코야끼 / 한식: 백미밥, 콩나물국, 토마토치즈떡갈비, 순대양배추찜/초장, 야채겉절이, 배추김치.
3. 제2학생식당 일품: 지코바치밥, 마늘바게트 / 한식: 흑미밥, 소고기미역국, 치킨까스유린기, 메추리알장조림, 불닭버섯볶음, 부추무침, 깍두기.

### 오류 흐름
1. 2026-10-25(일) 실행 → 제1학생식당 found: false("…10/25이 포함된 식단표 없음").
2. 제1 추출 에이전트가 `not_found` JSON을 저장하고, 메모장에는 제1은 사유, 제2는 메뉴가 표시된다. 점심은 제2 일품이 `---`이므로 한식만 표시된다.
