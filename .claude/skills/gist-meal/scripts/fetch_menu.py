"""GIST 학생식당 게시판에서 오늘 날짜가 포함된 주간 식단표 첨부파일(PDF/이미지)을 내려받는다.

사용법: python fetch_menu.py [--date YYYY-MM-DD] [--out _workspace]
출력: {out}/{date}/manifest.json 과 식당별 pdf/이미지/텍스트 파일
"""
import argparse
import datetime as dt
import html
import json
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

BASE = "https://www.gist.ac.kr/kr/html/sub05/{code}.html"
# 게시판의 ?mode=D 첨부 다운로드는 2026-10 말부터 /error/(404)로 리다이렉트된다.
# PDF는 글 안의 PDF 뷰어가 쓰는 경로로, 이미지는 본문 미리보기(?mode=IMG) 경로로 받는다.
PDF_URL = "https://www.gist.ac.kr/_prog/download/index.php?d_type=3&site_dvs_cd=kr&bbs_cd={code}&filename={file}"
BOARDS = [
    {"key": "cafeteria1", "name": "제1학생식당", "code": "050601"},
    {"key": "cafeteria2", "name": "제2학생식당", "code": "050602"},
]
# 최신 글 몇 개까지 오늘 날짜를 찾아볼지. 다음 주 식단이 미리 올라와 있어도 이번 주 글까지 닿도록 여유를 둔다.
MAX_POSTS = 4
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
PDFTOTEXT_FALLBACKS = [
    r"C:\Program Files\Git\mingw64\bin\pdftotext.exe",
    r"C:\Program Files (x86)\Git\mingw64\bin\pdftotext.exe",
]


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code} {e.reason}: {url}") from e


def list_posts(code: str) -> list[dict]:
    page = get(BASE.format(code=code)).decode("utf-8", "replace")
    posts = []
    # 게시글 카드: <a href='?mode=V&amp;no=224156'> ... <h2><span>제목</span></h2>
    for m in re.finditer(r"<a href='\?mode=V&amp;no=(\d+)'>(.*?)</a>", page, re.S):
        title = re.search(r"<h2><span>(.*?)</span></h2>", m.group(2), re.S)
        posts.append({"no": m.group(1), "title": html.unescape(title.group(1).strip()) if title else ""})
    return posts[:MAX_POSTS]


def list_attachments(code: str, no: str) -> tuple[list[dict], str | None]:
    """첨부 목록과 PDF 뷰어가 가리키는 서버 파일명을 돌려준다."""
    page = get(f"{BASE.format(code=code)}?mode=V&no={no}").decode("utf-8", "replace")
    files = []
    for m in re.finditer(r"href='\?mode=D&amp;no=(\d+)&amp;file_id=(\d+)' title='([^']+)'", page):
        files.append({"file_id": m.group(2), "name": html.unescape(m.group(3))})
    # <iframe ... src="/module/pdf_viewer/web/viewer_bbs.html?code=050601&site_dvs_cd=kr&fileId=2026...pdf">
    viewer = re.search(r"viewer_bbs\.html\?[^\"']*?fileId=([^\"'&]+\.pdf)", page, re.I)
    return files, (viewer.group(1) if viewer else None)


def find_pdftotext() -> str | None:
    found = shutil.which("pdftotext")
    if found:
        return found
    return next((p for p in PDFTOTEXT_FALLBACKS if Path(p).exists()), None)


def pdf_text(pdftotext: str | None, pdf: Path) -> str:
    if not pdftotext:
        return ""
    out = subprocess.run([pdftotext, "-layout", "-enc", "UTF-8", str(pdf), "-"], capture_output=True)
    return out.stdout.decode("utf-8", "replace")


def mentions_date(text: str, day: dt.date) -> bool:
    m, d = day.month, day.day
    patterns = [
        rf"(?<!\d){m}/{d}(?!\d)",           # 제1학생식당: "Thu 10/22"
        rf"(?<!\d){m}\s*월\s*{d}\s*일",      # 제2학생식당: "10월 22일 (목)"
        rf"(?<!\d){m}\.\s*{d}(?!\d)",
    ]
    return any(re.search(p, text) for p in patterns)


def fetch_board(board: dict, day: dt.date, outdir: Path, pdftotext: str | None) -> dict:
    result = {**board, "found": False, "post_no": None, "post_title": None, "post_url": None,
              "pdf": None, "image": None, "text": None, "error": None}
    code = board["code"]
    for post in list_posts(code):
        atts, pdf_file = list_attachments(code, post["no"])
        img_att = next((a for a in atts if a["name"].lower().endswith((".png", ".jpg", ".jpeg"))), None)
        if not pdf_file:
            continue
        pdf_path = outdir / f"{board['key']}.pdf"
        pdf_path.write_bytes(get(PDF_URL.format(code=code, file=pdf_file)))
        text = pdf_text(pdftotext, pdf_path)
        # 텍스트 추출이 안 되면 날짜 확인이 불가하므로 제목의 기간으로 대신 판단할 수 없다 → 최신 글을 후보로 남긴다.
        if text and not mentions_date(text, day):
            continue
        result.update(found=bool(text), post_no=post["no"], post_title=post["title"],
                      post_url=f"{BASE.format(code=code)}?mode=V&no={post['no']}", pdf=str(pdf_path))
        if text:
            txt_path = outdir / f"{board['key']}.txt"
            txt_path.write_text(text, encoding="utf-8")
            result["text"] = str(txt_path)
        else:
            result["error"] = "pdftotext 없음: 날짜 일치 여부 미확인, 최신 글을 사용"
        if img_att:
            ext = Path(img_att["name"]).suffix.lower()
            img_path = outdir / f"{board['key']}{ext}"
            img_path.write_bytes(get(f"{BASE.format(code=code)}?mode=IMG&no={post['no']}&file_id={img_att['file_id']}"))
            result["image"] = str(img_path)
        return result
    pdf_leftover = outdir / f"{board['key']}.pdf"
    if pdf_leftover.exists():
        pdf_leftover.unlink()
    result["error"] = f"최신 글 {MAX_POSTS}개 중 {day.month}/{day.day}이(가) 포함된 식단표 없음"
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="YYYY-MM-DD (기본: 오늘)")
    ap.add_argument("--out", default=str(Path(__file__).resolve().parents[4] / "_workspace"))
    args = ap.parse_args()
    day = dt.date.fromisoformat(args.date) if args.date else dt.date.today()
    outdir = Path(args.out) / day.isoformat()
    outdir.mkdir(parents=True, exist_ok=True)
    pdftotext = find_pdftotext()

    boards = []
    for board in BOARDS:
        try:
            boards.append(fetch_board(board, day, outdir, pdftotext))
        except Exception as e:  # 한 식당이 실패해도 다른 식당은 계속 처리한다
            boards.append({**board, "found": False, "error": f"{type(e).__name__}: {e}"})

    manifest = {"date": day.isoformat(), "weekday": "월화수목금토일"[day.weekday()], "boards": boards}
    manifest_path = outdir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"manifest": str(manifest_path), **manifest}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
