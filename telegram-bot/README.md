# PMemories CI — bot Telegram (strona VPS)

Ten folder to **kopia źródłowa dla kontroli wersji** — realnie działa na
VPS `root@204.168.216.7`, pod `/opt/pmemories-ci-bot/`. `ci.yml`/`auto-fix.yml`
same w sobie NIC nie wiedzą o tym bocie poza wysyłaniem wiadomości przez
Telegram Bot API i czytaniem zmiennej repo `CI_LANG` — bot na VPS jest
osobnym procesem, długo odpytującym (`long-polling`) Telegram.

## Co robi

- **Menu komend** (`/scan`, `/status`, `/lang`, `/help`) — rejestrowane w
  Telegramie przy starcie (`setMyCommands`).
- `/scan` — odpala `ci.yml` na żądanie (`workflow_dispatch`), niezależnie od
  pushu/PR/harmonogramu.
- `/status` — pokazuje wynik ostatniego runu CI.
- `/lang` — przyciski PL/EN, zmienia zmienną repo `CI_LANG` (czytaną przez
  `ci.yml`/`auto-fix.yml` do wyboru języka wiadomości).
- Przycisk "🔧 Napraw"/"🔧 Fix" pod wiadomością o błędzie — odpala
  `auto-fix.yml` z konkretnym `run_id`.

## Deploy (ręczny, jednorazowy)

```bash
scp telegram-bot/listener.py root@204.168.216.7:/opt/pmemories-ci-bot/listener.py
scp telegram-bot/pmemories-ci-bot.service root@204.168.216.7:/etc/systemd/system/pmemories-ci-bot.service
ssh root@204.168.216.7 "systemctl daemon-reload && systemctl enable pmemories-ci-bot"
```

Potem na VPS trzeba ręcznie stworzyć `/opt/pmemories-ci-bot/env` (NIGDY nie
w repo/git — to sekrety):

```bash
cat > /opt/pmemories-ci-bot/env <<'EOF'
TELEGRAM_BOT_TOKEN=<token bota "PMemories CI">
GITHUB_TOKEN=<token z uprawnieniami repo+workflow>
EOF
chmod 600 /opt/pmemories-ci-bot/env
systemctl start pmemories-ci-bot
systemctl status pmemories-ci-bot
```

`GITHUB_TOKEN` musi mieć zakresy `repo` + `workflow` (to samo co reszta
pipeline'u) — używany do `workflow_dispatch` (`ci.yml`, `auto-fix.yml`) i
do czytania/zapisu zmiennej repo `actions/variables/CI_LANG`.

## Redeploy po zmianie `listener.py`

```bash
scp telegram-bot/listener.py root@204.168.216.7:/opt/pmemories-ci-bot/listener.py
ssh root@204.168.216.7 "systemctl restart pmemories-ci-bot"
```
