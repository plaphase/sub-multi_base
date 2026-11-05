#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail "Требуются права root."
PUBLIC_HOST="${PUBLIC_HOST:-}"
PANEL_PORT="${PANEL_PORT:-18082}"
[[ "$PUBLIC_HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ || "$PUBLIC_HOST" =~ ^[0-9]+(\.[0-9]+){3}$ ]] ||
    fail "Некорректное доменное имя или IPv4-адрес."
[[ "$PANEL_PORT" =~ ^[0-9]+$ ]] || fail "Некорректный порт панели."
(( PANEL_PORT >= 1 && PANEL_PORT <= 65535 )) || fail "Порт панели должен быть в диапазоне 1–65535."

AVAILABLE_DIR="/etc/nginx/sites-available"
ENABLED_DIR="/etc/nginx/sites-enabled"
SITE_FILE="$AVAILABLE_DIR/multisub-panel"
SITE_LINK="$ENABLED_DIR/multisub-panel"
[[ -d "$AVAILABLE_DIR" && ! -L "$AVAILABLE_DIR" ]] || fail "Не найден обычный каталог $AVAILABLE_DIR."
[[ -d "$ENABLED_DIR" && ! -L "$ENABLED_DIR" ]] || fail "Не найден обычный каталог $ENABLED_DIR."
[[ ! -e "$SITE_FILE" && ! -L "$SITE_FILE" ]] || fail "Конфигурация Nginx уже существует: $SITE_FILE"
[[ ! -e "$SITE_LINK" && ! -L "$SITE_LINK" ]] || fail "Ссылка сайта Nginx уже существует: $SITE_LINK"

TEMP_FILE="$(mktemp "$AVAILABLE_DIR/.multisub-panel.XXXXXX")"
SITE_CREATED=0
LINK_CREATED=0
cleanup() {
    rm -f -- "$TEMP_FILE"
    if [[ "$LINK_CREATED" -eq 1 ]]; then
        rm -f -- "$SITE_LINK"
    fi
    if [[ "$SITE_CREATED" -eq 1 ]]; then
        rm -f -- "$SITE_FILE"
    fi
}
trap cleanup EXIT

cat > "$TEMP_FILE" <<'NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name @PUBLIC_HOST@;

    server_tokens off;
    client_max_body_size 10m;

    location / {
        proxy_pass http://127.0.0.1:@PANEL_PORT@;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout 120s;
    }
}
NGINX

python3 - "$TEMP_FILE" "$PUBLIC_HOST" "$PANEL_PORT" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("@PUBLIC_HOST@", sys.argv[2]).replace("@PANEL_PORT@", sys.argv[3])
if "@" in text:
    raise SystemExit("Не все значения шаблона Nginx заменены.")
path.write_text(text, encoding="utf-8")
PY

chown root:root "$TEMP_FILE"
chmod 0644 "$TEMP_FILE"
ln -- "$TEMP_FILE" "$SITE_FILE" || fail "Не удалось безопасно создать конфигурацию сайта."
SITE_CREATED=1
ln -s -- "$SITE_FILE" "$SITE_LINK" || fail "Не удалось включить сайт Nginx."
LINK_CREATED=1

nginx -t || fail "Проверка конфигурации Nginx завершилась ошибкой."
rm -- "$TEMP_FILE"
TEMP_FILE=""

if systemctl is-active --quiet nginx; then
    systemctl reload nginx || fail "Не удалось перезагрузить Nginx."
else
    systemctl enable --now nginx || fail "Не удалось включить Nginx."
fi

SITE_CREATED=0
LINK_CREATED=0
trap - EXIT
printf '[OK] HTTP reverse proxy Nginx настроен для %s.\n' "$PUBLIC_HOST"
