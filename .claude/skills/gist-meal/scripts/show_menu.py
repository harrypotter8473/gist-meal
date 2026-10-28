"""추출된 아침·점심·저녁식단(JSON)을 메모장용 텍스트로 정리해 저장하고 화면에 띄운다.

사용법:
  python show_menu.py --meal breakfast|lunch|dinner [--date YYYY-MM-DD] [--no-open]
  python show_menu.py --meal breakfast|lunch|dinner --fallback   # Claude 실행이 실패했을 때: 게시판 링크와 오류만 띄운다
입력: _workspace/{date}/manifest.json, _workspace/{date}/{key}_{meal}.json
출력: output/{meal}_{date}.txt
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
BOARD_URLS = {
    "제1학생식당": "https://www.gist.ac.kr/kr/html/sub05/050601.html",
    "제2학생식당": "https://www.gist.ac.kr/kr/html/sub05/050602.html",
}
WEEKDAYS = "월화수목금토일"
MEAL_LABELS = {"breakfast": "아침", "lunch": "점심", "dinner": "저녁"}


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def menu_lines(menu: dict) -> list[str]:
    # 점심은 일품/한식처럼 구역이 나뉘고, 저녁은 이름 없는 구역 하나다.
    out = []
    for section in menu.get("sections") or []:
        items = section.get("items") or []
        if not items:
            continue
        if section.get("name"):
            out.append(f"  <{section['name']}>")
            out += [f"    - {item}" for item in items]
        else:
            out += [f"  - {item}" for item in items]
    return out


def build_text(day: dt.date, meal: str, fallback: bool) -> str:
    ws = ROOT / "_workspace" / day.isoformat()
    manifest = load_json(ws / "manifest.json") or {"boards": []}
    boards = {b["name"]: b for b in manifest.get("boards", [])}
    label = MEAL_LABELS[meal]
    lines = [f"GIST 오늘의 {label}식단", f"{day.year}년 {day.month}월 {day.day}일 ({WEEKDAYS[day.weekday()]})", ""]
    if fallback:
        lines += ["※ 자동 추출에 실패했습니다. 아래 링크에서 직접 확인해 주세요.", ""]

    for name, list_url in BOARD_URLS.items():
        board = boards.get(name, {})
        menu = load_json(ws / f"{board.get('key', '')}_{meal}.json") if board.get("key") else None
        body = menu_lines(menu) if menu else []
        lines.append(f"[{name}]")
        if menu and menu.get("status") in ("ok", "uncertain") and body:
            lines += body
            if menu["status"] == "uncertain":
                lines.append("  (일부 항목 판독 불확실 — 원문 확인 권장)")
            if menu.get("note"):
                lines.append(f"  * {menu['note']}")
        elif menu and menu.get("status") == "closed":
            lines.append(f"  오늘 {label}은 운영하지 않습니다.")
        else:
            reason = (menu or {}).get("note") or board.get("error") or "식단 정보를 찾지 못했습니다."
            lines.append(f"  {reason}")
        lines.append(f"  출처: {board.get('post_url') or list_url}")
        lines.append("")
    # 텍스트 모드 쓰기가 \n을 \r\n으로 바꿔 주므로 여기서는 \n만 쓴다.
    return "\n".join(lines)


def open_in_notepad(path: Path) -> None:
    # 부모 프로세스(claude)가 끝나도 메모장이 닫히지 않도록 분리해서 띄운다.
    flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
    try:
        subprocess.Popen(["notepad.exe", str(path)], creationflags=flags | subprocess.CREATE_BREAKAWAY_FROM_JOB,
                         close_fds=True)
    except OSError:
        subprocess.Popen(["notepad.exe", str(path)], creationflags=flags, close_fds=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--meal", choices=MEAL_LABELS, required=True)
    ap.add_argument("--date")
    ap.add_argument("--fallback", action="store_true")
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()
    day = dt.date.fromisoformat(args.date) if args.date else dt.date.today()

    out = ROOT / "output" / f"{args.meal}_{day.isoformat()}.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    # 메모장이 인코딩을 확실히 인식하도록 BOM 포함 UTF-8로 저장한다.
    out.write_text(build_text(day, args.meal, args.fallback), encoding="utf-8-sig")
    print(out)
    # 로그오프 상태에서 도는 예약 작업은 화면이 없으므로 GIST_NO_POPUP=1로 메모장을 띄우지 않는다(show_popup.cmd가 대신 연다).
    if not args.no_open and os.environ.get("GIST_NO_POPUP") != "1":
        open_in_notepad(out)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
