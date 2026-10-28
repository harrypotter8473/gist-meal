"""추출된 아침·점심·저녁식단을 카카오톡 '나에게 보내기'로 전송한다.

사용법:
  python kakao_send.py auth --key REST_API_KEY [--secret CLIENT_SECRET]   # 최초 1회: 브라우저 로그인·동의
  python kakao_send.py send --meal breakfast|lunch|dinner [--date YYYY-MM-DD] [--fallback]
  python kakao_send.py test                                               # 연결 확인용 메시지 1건
토큰 저장: {프로젝트}/.secrets/kakao.json (access token은 만료 시 refresh token으로 자동 갱신)
"""
import argparse
import datetime as dt
import http.server
import json
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from show_menu import BOARD_URLS, MEAL_LABELS, ROOT, WEEKDAYS, load_json  # noqa: E402

SECRETS = ROOT / ".secrets" / "kakao.json"
PORT = 8765
REDIRECT_URI = f"http://localhost:{PORT}/callback"
AUTH_URL = "https://kauth.kakao.com/oauth/authorize"
TOKEN_URL = "https://kauth.kakao.com/oauth/token"
MEMO_URL = "https://kapi.kakao.com/v2/api/talk/memo/default/send"
# 텍스트 템플릿의 text는 최대 200자다. 넘으면 카카오가 거부하므로 식당별로 나눠 보내고, 그래도 넘치면 자른다.
TEXT_LIMIT = 200


def post_form(url: str, data: dict, token: str | None = None) -> dict:
    req = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode(), method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded;charset=utf-8")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        raise RuntimeError(f"HTTP {e.code} {url}: {body}") from None


def save_tokens(conf: dict, tok: dict) -> None:
    now = int(time.time())
    conf["access_token"] = tok["access_token"]
    conf["expires_at"] = now + int(tok.get("expires_in", 0)) - 60
    # refresh token은 만료가 1개월 이내로 남았을 때만 새로 내려온다.
    if tok.get("refresh_token"):
        conf["refresh_token"] = tok["refresh_token"]
        conf["refresh_expires_at"] = now + int(tok.get("refresh_token_expires_in", 0))
    SECRETS.parent.mkdir(parents=True, exist_ok=True)
    SECRETS.write_text(json.dumps(conf, ensure_ascii=False, indent=2), encoding="utf-8")


def load_conf() -> dict:
    conf = load_json(SECRETS)
    if not conf or not conf.get("refresh_token"):
        raise RuntimeError(f"카카오 인증 정보가 없습니다. 먼저 `python kakao_send.py auth --key ...`를 실행하세요. ({SECRETS})")
    return conf


def token_request(conf: dict, extra: dict) -> dict:
    data = {"client_id": conf["rest_api_key"], **extra}
    if conf.get("client_secret"):
        data["client_secret"] = conf["client_secret"]
    return post_form(TOKEN_URL, data)


def access_token(conf: dict, force_refresh: bool = False) -> str:
    if not force_refresh and conf.get("expires_at", 0) > time.time():
        return conf["access_token"]
    tok = token_request(conf, {"grant_type": "refresh_token", "refresh_token": conf["refresh_token"]})
    save_tokens(conf, tok)
    return conf["access_token"]


def send_text(conf: dict, text: str, url: str) -> None:
    if len(text) > TEXT_LIMIT:
        text = text[: TEXT_LIMIT - 1] + "…"
    template = {"object_type": "text", "text": text,
                "link": {"web_url": url, "mobile_web_url": url}, "button_title": "식단표 보기"}
    data = {"template_object": json.dumps(template, ensure_ascii=False)}
    try:
        post_form(MEMO_URL, data, access_token(conf))
    except RuntimeError as e:
        if "HTTP 401" not in str(e):
            raise
        post_form(MEMO_URL, data, access_token(conf, force_refresh=True))


def cafeteria_text(menu: dict | None, board: dict, label: str) -> str:
    # 200자 제한 안에 들도록 구역별로 한 줄씩, 항목은 쉼표로 잇는다.
    if menu and menu.get("status") in ("ok", "uncertain"):
        lines = []
        for section in menu.get("sections") or []:
            items = section.get("items") or []
            if items:
                prefix = f"[{section['name']}] " if section.get("name") else ""
                lines.append(prefix + ", ".join(items))
        if lines:
            if menu["status"] == "uncertain":
                lines.append("(일부 판독 불확실)")
            return "\n".join(lines)
    if menu and menu.get("status") == "closed":
        return f"오늘 {label}은 운영하지 않습니다."
    return (menu or {}).get("note") or board.get("error") or "식단 정보를 찾지 못했습니다."


def cmd_send(meal: str, day: dt.date, fallback: bool) -> None:
    conf = load_conf()
    label = MEAL_LABELS[meal]
    head = f"🍚 {day.month}/{day.day}({WEEKDAYS[day.weekday()]}) {label}"
    ws = ROOT / "_workspace" / day.isoformat()
    boards = {b["name"]: b for b in (load_json(ws / "manifest.json") or {}).get("boards", [])}
    for name, list_url in BOARD_URLS.items():
        board = boards.get(name, {})
        url = board.get("post_url") or list_url
        if fallback:
            body = "자동 추출에 실패했습니다. 버튼을 눌러 직접 확인해 주세요."
        else:
            menu = load_json(ws / f"{board['key']}_{meal}.json") if board.get("key") else None
            body = cafeteria_text(menu, board, label)
        send_text(conf, f"{head} · {name}\n{body}", url)
        print(f"sent: {name}")


def cmd_auth(key: str, secret: str | None) -> None:
    conf = {"rest_api_key": key, "client_secret": secret or "", "redirect_uri": REDIRECT_URI}
    got = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            got.update({k: v[0] for k, v in qs.items()})
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            msg = "인증 완료. 이 창을 닫아도 됩니다." if "code" in got else f"인증 실패: {got}"
            self.wfile.write(f"<h2>{msg}</h2>".encode("utf-8"))

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(("localhost", PORT), Handler)
    threading.Thread(target=server.handle_request, daemon=True).start()
    url = AUTH_URL + "?" + urllib.parse.urlencode(
        {"client_id": key, "redirect_uri": REDIRECT_URI, "response_type": "code", "scope": "talk_message"})
    print(f"브라우저에서 카카오 로그인·동의를 진행하세요. 자동으로 열리지 않으면 이 주소를 여세요:\n{url}")
    webbrowser.open(url)
    deadline = time.time() + 300
    while "code" not in got and "error" not in got and time.time() < deadline:
        time.sleep(0.5)
    server.server_close()
    if "code" not in got:
        raise RuntimeError(f"인가 코드를 받지 못했습니다: {got or '시간 초과(5분)'}")
    tok = token_request(conf, {"grant_type": "authorization_code", "redirect_uri": REDIRECT_URI, "code": got["code"]})
    save_tokens(conf, tok)
    print(f"토큰 저장 완료: {SECRETS}")


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("auth")
    a.add_argument("--key", required=True)
    a.add_argument("--secret")
    s = sub.add_parser("send")
    s.add_argument("--meal", choices=MEAL_LABELS, required=True)
    s.add_argument("--date")
    s.add_argument("--fallback", action="store_true")
    sub.add_parser("test")
    args = ap.parse_args()
    try:
        if args.cmd == "auth":
            cmd_auth(args.key, args.secret)
        elif args.cmd == "test":
            send_text(load_conf(), "GIST 식단 알림 연결 테스트입니다.", BOARD_URLS["제2학생식당"])
            print("sent: test")
        else:
            day = dt.date.fromisoformat(args.date) if args.date else dt.date.today()
            cmd_send(args.meal, day, args.fallback)
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    sys.exit(main())
