#!/usr/bin/env python3
"""
PMemories CI — listener bota Telegram (strona VPS).

15.09.2026 — rozbudowane z samego przycisku "🔧 Napraw" (poprzednia wersja)
o menu komend, skan na żądanie i wybór języka PL/EN. Długo odpytuje
(long-polling) Telegram `getUpdates` i reaguje na:

  - komendę /scan [ios|android]   — odpala pełny build+testy TERAZ
                       (workflow_dispatch na `ci.yml`), nie czekając na
                       push/PR/harmonogram. Bez argumentu = iOS (domyślne,
                       dla wstecznej kompatybilności z dniem, gdy istniało
                       tylko jedno repo).
  - komendę /status [ios|android]  — pokazuje wynik ostatniego runu CI
  - komendę /lang    — przyciski PL/EN, zmienia język wiadomości CI DLA
                       OBU repo naraz (zapisuje jako zmienną repo GitHub
                       `CI_LANG` w każdym z nich, którą czytają oba `ci.yml`)
  - komendę /help i /start — pokazuje to menu
  - callback_query "fix:<repo>:<run_id>" — przycisk "🔧 Napraw"/"🔧 Fix"
    pod wiadomością o błędzie, odpala `auto-fix.yml` W WŁAŚCIWYM repo z
    tym run_id. Wstecznie kompatybilne ze STARYM formatem "fix:<run_id>"
    (bez repo — sprzed 15.09.2026, kiedy istniało tylko PMemories-iOS)
    poprzez `_parse_fix_payload`.

15.09.2026, ten sam dzień — rozszerzone o DRUGIE repo (`PMemories-Android`,
nowo założone) po tym jak user poprosił o CI "jak mamy na iOS" — jeden bot,
jeden token, dwa repo, wybierane przez opcjonalny argument komendy albo
prefiks w `callback_data`.

Jedno źródło prawdy dla języka: zmienna repo GitHub `CI_LANG` w KAŻDYM z
dwóch repo (nie osobny plik na VPS) — bot i workflow czytają jedną wartość
per repo, zero ryzyka rozjazdu między VPS a GitHub Actions. `/lang`
ustawia ją w obu na raz (jeden wybór językowy dla usera, nie osobno per
platforma).

Wymaga zmiennych środowiskowych: TELEGRAM_BOT_TOKEN, GITHUB_TOKEN (scope
`repo` + `workflow`, ten sam co reszta pipeline'u, działający na oba repo
bo to ten sam właściciel/konto).
"""
import json
import os
import time
import urllib.request
import urllib.error

TELEGRAM_BOT_TOKEN = os.environ["TELEGRAM_BOT_TOKEN"]
GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
OFFSET_FILE = os.environ.get("OFFSET_FILE", "/opt/pmemories-ci-bot/offset.txt")

TG_API = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}"

# Dwa repo, jeden bot — "ios" zostaje DOMYŚLNYM aliasem (komendy bez
# argumentu / stary format callback_data sprzed drugiego repo).
REPOS = {
    "ios": "piotrekmarkowski/PMemories-iOS",
    "android": "piotrekmarkowski/PMemories-Android",
}
DEFAULT_REPO_KEY = "ios"

TEXT = {
    "pl": {
        "help": (
            "🤖 PMemories CI bot\n\n"
            "/scan [ios|android] — uruchom pełny skan błędów teraz (domyślnie iOS)\n"
            "/status [ios|android] — pokaż wynik ostatniego skanu\n"
            "/lang — zmień język (PL/EN, dotyczy obu platform)\n"
            "/help — to menu\n\n"
            "Automatycznie: skanuję przy każdym pushu/PR (iOS i Android osobno) "
            "i codziennie o 12:00 (UK). Przy błędzie dostaniesz wiadomość z "
            "przyciskiem 🔧 Napraw."
        ),
        "scan_started": "🔍 Uruchamiam pełny skan ({repo})... dam znać za ok. 2-3 minuty.",
        "scan_error": "❌ Nie udało się uruchomić skanu: {err}",
        "status_none": "Nie znalazłem żadnego runu CI ({repo}).",
        "status_line": "{emoji} Ostatni skan ({repo}): {status}\n{url}",
        "unknown_cmd": "Nie znam tej komendy — wpisz /help",
        "unknown_target": "Nie znam platformy \"{target}\" — użyj ios albo android.",
        "lang_prompt": "Wybierz język powiadomień CI (dla iOS i Android):",
        "lang_set": "Ustawiono: Polski 🇵🇱",
        "fix_started": "Naprawa uruchomiona 🔧",
        "fix_error": "Błąd: {err}",
    },
    "en": {
        "help": (
            "🤖 PMemories CI bot\n\n"
            "/scan [ios|android] — run a full error scan now (defaults to iOS)\n"
            "/status [ios|android] — show the last scan result\n"
            "/lang — change language (PL/EN, applies to both platforms)\n"
            "/help — this menu\n\n"
            "Automatic: I scan on every push/PR (iOS and Android separately) "
            "and daily at 12:00 (UK). On failure you'll get a message with a "
            "🔧 Fix button."
        ),
        "scan_started": "🔍 Starting a full scan ({repo})... I'll report back in ~2-3 minutes.",
        "scan_error": "❌ Couldn't start the scan: {err}",
        "status_none": "No CI runs found ({repo}).",
        "status_line": "{emoji} Last scan ({repo}): {status}\n{url}",
        "unknown_cmd": "Unknown command — type /help",
        "unknown_target": "Unknown platform \"{target}\" — use ios or android.",
        "lang_prompt": "Choose the CI notification language (applies to both iOS and Android):",
        "lang_set": "Set to: English 🇬🇧",
        "fix_started": "Fix started 🔧",
        "fix_error": "Error: {err}",
    },
}

STATUS_EMOJI = {"success": "✅", "failure": "❌"}


def tg_call(method, payload, timeout=20):
    # 15.09.2026 — złapany na żywo prawdziwy bug: `getUpdates` prosi Telegram
    # o przytrzymanie połączenia do `timeout` sekund (long-polling), ale
    # domyślny timeout GNIAZDA klienta (20s) był KRÓTSZY niż to o co prosimy
    # serwer (30s) — więc regularnie wywalało "read operation timed out"
    # zanim serwer zdążył odpowiedzieć. `main()` woła to teraz z osobnym,
    # dłuższym timeoutem dla `getUpdates` konkretnie.
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{TG_API}/{method}", data=data, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        # 15.09.2026 — pierwsza wersja gubiła treść odpowiedzi Telegrama przy
        # 400/403 itp. (sam kod "HTTP Error 400: Bad Request" bez `description`
        # z body) — złapane na żywo, nie dało się zdiagnozować co konkretnie
        # odrzucił Telegram. `e.read()` daje realny powód (np. zły chat_id,
        # zła struktura `reply_markup`).
        body = e.read().decode(errors="replace")
        print(f"tg_call({method}) HTTP {e.code}: {body}", flush=True)
        raise


def gh_call(method, path, payload=None):
    url = f"https://api.github.com{path}"
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {GITHUB_TOKEN}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            body = resp.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        body = e.read().decode(errors="replace")
        print(f"gh_call({method} {path}) HTTP {e.code}: {body}", flush=True)
        raise


def _resolve_repo(key):
    """Zwraca (repo_key, repo_full_name) albo (None, None) jeśli nieznany alias."""
    key = (key or DEFAULT_REPO_KEY).lower()
    if key not in REPOS:
        return None, None
    return key, REPOS[key]


def get_lang(repo_key):
    # `CI_LANG` to zwykła zmienna repo (Settings → Secrets and variables →
    # Actions → Variables), nie sekret — jawnie widoczna, bez ryzyka.
    repo = REPOS[repo_key]
    result = gh_call("GET", f"/repos/{repo}/actions/variables/CI_LANG")
    if result and "value" in result:
        return result["value"] if result["value"] in TEXT else "pl"
    return "pl"


def set_lang_everywhere(lang):
    """Ustawia `CI_LANG` w OBU repo naraz — jeden wybór językowy dla usera."""
    for repo in REPOS.values():
        payload = {"name": "CI_LANG", "value": lang}
        existing = gh_call("GET", f"/repos/{repo}/actions/variables/CI_LANG")
        if existing is None:
            gh_call("POST", f"/repos/{repo}/actions/variables", payload)
        else:
            gh_call("PATCH", f"/repos/{repo}/actions/variables/CI_LANG", {"value": lang})


def send_message(chat_id, text, reply_markup=None):
    payload = {"chat_id": chat_id, "text": text}
    if reply_markup:
        payload["reply_markup"] = reply_markup
    tg_call("sendMessage", payload)


def dispatch_workflow(repo, workflow_file, ref="main", inputs=None):
    payload = {"ref": ref}
    if inputs:
        payload["inputs"] = inputs
    gh_call("POST", f"/repos/{repo}/actions/workflows/{workflow_file}/dispatches", payload)


def latest_run(repo, workflow_file):
    data = gh_call("GET", f"/repos/{repo}/actions/workflows/{workflow_file}/runs?per_page=1")
    runs = (data or {}).get("workflow_runs", [])
    return runs[0] if runs else None


def register_menu():
    # Nazwy komend uniwersalne (angielskie, jak wymaga Telegram), krótkie
    # opisy dwujęzyczne — sam wybrany język PL/EN dotyczy TREŚCI wiadomości
    # CI, nie samych nazw komend w menu "/".
    tg_call(
        "setMyCommands",
        {
            "commands": [
                {"command": "scan", "description": "🔍 Skan teraz / Scan now [ios|android]"},
                {"command": "status", "description": "📊 Ostatni wynik / Last result [ios|android]"},
                {"command": "lang", "description": "🌐 Język / Language"},
                {"command": "help", "description": "❓ Menu / Help"},
            ]
        },
    )


def handle_command(chat_id, text):
    parts = text.split()
    cmd = parts[0].lstrip("/").split("@")[0].lower()
    arg = parts[1] if len(parts) > 1 else None

    # Język wiadomości bierzemy z domyślnego repo (iOS) — obie zmienne
    # CI_LANG trzymamy zsynchronizowane przez `/lang`, więc to bezpieczne
    # uproszczenie zamiast odpytywać dwa razy dla samego menu.
    lang = get_lang(DEFAULT_REPO_KEY)
    t = TEXT[lang]

    if cmd == "scan":
        repo_key, repo = _resolve_repo(arg)
        if repo is None:
            send_message(chat_id, t["unknown_target"].format(target=arg))
            return
        try:
            dispatch_workflow(repo, "ci.yml")
            send_message(chat_id, t["scan_started"].format(repo=repo_key))
        except Exception as e:
            send_message(chat_id, t["scan_error"].format(err=e))
    elif cmd == "status":
        repo_key, repo = _resolve_repo(arg)
        if repo is None:
            send_message(chat_id, t["unknown_target"].format(target=arg))
            return
        run = latest_run(repo, "ci.yml")
        if not run:
            send_message(chat_id, t["status_none"].format(repo=repo_key))
            return
        conclusion = run.get("conclusion") or run["status"]
        emoji = STATUS_EMOJI.get(conclusion, "⏳")
        send_message(chat_id, t["status_line"].format(emoji=emoji, repo=repo_key, status=conclusion, url=run["html_url"]))
    elif cmd == "lang":
        keyboard = {
            "inline_keyboard": [[
                {"text": "🇵🇱 Polski", "callback_data": "lang:pl"},
                {"text": "🇬🇧 English", "callback_data": "lang:en"},
            ]]
        }
        send_message(chat_id, t["lang_prompt"], reply_markup=keyboard)
    elif cmd in ("start", "help"):
        send_message(chat_id, t["help"])
    else:
        send_message(chat_id, t["unknown_cmd"])


def _parse_fix_payload(data):
    """"fix:<run_id>" (stary format, sprzed drugiego repo) LUB
    "fix:<repo_key>:<run_id>" (nowy) — zwraca (repo_key, repo, run_id)."""
    rest = data[len("fix:"):]
    if ":" in rest:
        repo_key, run_id = rest.split(":", 1)
    else:
        repo_key, run_id = DEFAULT_REPO_KEY, rest
    resolved_key, repo = _resolve_repo(repo_key)
    return resolved_key, repo, run_id


def handle_callback(cb):
    data = cb.get("data", "")
    chat_id = cb["message"]["chat"]["id"]
    message_id = cb["message"]["message_id"]
    callback_id = cb["id"]

    if data.startswith("fix:"):
        lang = get_lang(DEFAULT_REPO_KEY)
        t = TEXT[lang]
        repo_key, repo, run_id = _parse_fix_payload(data)
        if repo is None:
            tg_call(
                "answerCallbackQuery",
                {"callback_query_id": callback_id, "text": t["unknown_target"].format(target=repo_key), "show_alert": True},
            )
            return
        try:
            dispatch_workflow(repo, "auto-fix.yml", inputs={"run_id": run_id})
            tg_call("answerCallbackQuery", {"callback_query_id": callback_id, "text": t["fix_started"]})
            tg_call(
                "editMessageReplyMarkup",
                {"chat_id": chat_id, "message_id": message_id, "reply_markup": {"inline_keyboard": []}},
            )
        except Exception as e:
            tg_call(
                "answerCallbackQuery",
                {"callback_query_id": callback_id, "text": t["fix_error"].format(err=e), "show_alert": True},
            )
    elif data.startswith("lang:"):
        new_lang = data.split(":", 1)[1]
        if new_lang not in TEXT:
            new_lang = "pl"
        set_lang_everywhere(new_lang)
        tg_call("answerCallbackQuery", {"callback_query_id": callback_id, "text": TEXT[new_lang]["lang_set"]})
        tg_call(
            "editMessageText",
            {"chat_id": chat_id, "message_id": message_id, "text": TEXT[new_lang]["lang_set"]},
        )
    else:
        tg_call("answerCallbackQuery", {"callback_query_id": callback_id})


def load_offset():
    try:
        with open(OFFSET_FILE) as f:
            return int(f.read().strip())
    except Exception:
        return 0


def save_offset(offset):
    with open(OFFSET_FILE, "w") as f:
        f.write(str(offset))


POLL_TIMEOUT = 30


def main():
    register_menu()
    offset = load_offset()
    print("PMemories CI bot listener wystartował (iOS + Android).", flush=True)
    while True:
        try:
            # timeout gniazda klienta MUSI być dłuższy niż `timeout` który
            # prosimy serwer przytrzymać (patrz komentarz przy `tg_call`).
            resp = tg_call(
                "getUpdates", {"offset": offset, "timeout": POLL_TIMEOUT}, timeout=POLL_TIMEOUT + 10
            )
        except Exception as e:
            print(f"getUpdates error: {e}", flush=True)
            time.sleep(5)
            continue
        for update in resp.get("result", []):
            offset = update["update_id"] + 1
            save_offset(offset)
            try:
                if "callback_query" in update:
                    handle_callback(update["callback_query"])
                elif "message" in update and "text" in update["message"]:
                    text = update["message"]["text"]
                    chat_id = update["message"]["chat"]["id"]
                    if text.startswith("/"):
                        handle_command(chat_id, text)
            except Exception:
                import traceback
                print(f"handler error:\n{traceback.format_exc()}", flush=True)


if __name__ == "__main__":
    main()
