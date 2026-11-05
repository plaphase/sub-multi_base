#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-/opt/multisub-panel}"
CONFIG_DIR="${CONFIG_DIR:-/etc/multisub-panel}"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/panel.env}"
DATA_DIR="${DATA_DIR:-/var/lib/multisub-panel}"
LOG_DIR="${LOG_DIR:-/var/log/multisub-panel}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/multisub-panel}"
PANEL_PORT="${PANEL_PORT:-18082}"
SERVICE_USER="${SERVICE_USER:-multisub-panel}"
SERVICE_GROUP="${SERVICE_GROUP:-$SERVICE_USER}"
STATE_FILE="${STATE_FILE:-/run/multisub-panel-install.state}"
SERVICE_FILE="/etc/systemd/system/multisub-panel.service"
NGINX_SITE="/etc/nginx/sites-available/multisub-panel"
NGINX_LINK="/etc/nginx/sites-enabled/multisub-panel"
STATE_CREATED=0

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

info() {
    printf '[INFO] %s\n' "$1"
}

cleanup() {
    if [[ "$STATE_CREATED" -eq 1 ]]; then
        rm -f -- "$STATE_FILE"
    fi
}
trap cleanup EXIT

[[ "$EUID" -eq 0 ]] || fail "Для установки требуются права root. Запусти: sudo bash installer/install.sh"
[[ "$STATE_FILE" == /* && ! -L "$STATE_FILE" ]] || fail "STATE_FILE должен быть абсолютным обычным путём."
[[ ! -e "$STATE_FILE" ]] || fail "Файл состояния уже существует: $STATE_FILE"
[[ "$PANEL_PORT" =~ ^[0-9]+$ ]] || fail "Некорректный порт панели."
(( PANEL_PORT >= 1 && PANEL_PORT <= 65535 )) || fail "Порт панели должен быть в диапазоне 1–65535."

printf '%s\n' '======================================'
printf '%s\n' '       MultiSub Panel Installer'
printf '%s\n' '======================================'
printf '\n'

printf '[1/6] Проверка системы...\n'
bash "$SCRIPT_DIR/preflight.sh"

printf '\n[2/6] Выбор режима и проверка данных...\n'
if bash "$SCRIPT_DIR/select-mode.sh"; then
    STATE_CREATED=1
else
    rc=$?
    if [[ "$rc" -eq 10 ]]; then
        info "Установка отменена. Изменений не выполнено."
        exit 0
    fi
    exit "$rc"
fi

[[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] || fail "Файл состояния не создан."
[[ "$(stat -c '%U:%G' -- "$STATE_FILE")" == "root:root" ]] || fail "Файл состояния должен принадлежать root:root."
[[ "$(stat -c '%a' -- "$STATE_FILE")" == "600" ]] || fail "Файл состояния должен иметь права 600."

STATE_OUTPUT="$(python3 "$SCRIPT_DIR/lib/read-state.py" "$STATE_FILE")" ||
    fail "Не удалось прочитать выбранный режим установки."
mapfile -t STATE_VALUES <<< "$STATE_OUTPUT"
[[ "${#STATE_VALUES[@]}" -eq 3 ]] || fail "Некорректный файл состояния."

MODE="$(printf '%s' "${STATE_VALUES[0]}" | base64 -d)" || fail "Некорректный режим установки."
DATA_DIR="$(printf '%s' "${STATE_VALUES[1]}" | base64 -d)" || fail "Некорректный каталог данных."
if [[ "${STATE_VALUES[2]}" == "-" ]]; then
    SOURCE_DATA_DIR=""
else
    SOURCE_DATA_DIR="$(printf '%s' "${STATE_VALUES[2]}" | base64 -d)" ||
        fail "Некорректный каталог исходных данных."
fi
rm -- "$STATE_FILE"
STATE_CREATED=0

validate_managed_path() {
    local name="$1" value="$2" current="/" component
    local -a parts

    [[ "$value" =~ ^/[a-zA-Z0-9._/-]+$ ]] ||
        fail "$name содержит недопустимые символы: $value"
    [[ "$value" != "/" && "$value" != */ && "$value" != *//* ]] ||
        fail "Некорректный формат пути $name: $value"
    IFS='/' read -r -a parts <<< "$value"
    for component in "${parts[@]}"; do
        [[ -n "$component" ]] || continue
        [[ "$component" != "." && "$component" != ".." ]] ||
            fail "$name содержит недопустимый компонент: $component"
        current="${current%/}/$component"
        [[ ! -L "$current" ]] || fail "Путь $name проходит через символическую ссылку: $current"
    done
}

validate_managed_path APP_DIR "$APP_DIR"
validate_managed_path CONFIG_DIR "$CONFIG_DIR"
validate_managed_path DATA_DIR "$DATA_DIR"
validate_managed_path LOG_DIR "$LOG_DIR"
validate_managed_path BACKUP_DIR "$BACKUP_DIR"
[[ "$CONFIG_FILE" == "$CONFIG_DIR/panel.env" ]] || fail "CONFIG_FILE должен указывать на $CONFIG_DIR/panel.env."
case "$DATA_DIR/" in
    /home/*|/root/*|/tmp/*|/var/tmp/*|/run/*)
        fail "Каталог данных должен находиться вне системных временных каталогов и домашних каталогов."
        ;;
esac

if [[ "${INSTALLER_DRY_RUN:-0}" != "1" ]]; then
    [[ ! -e "$APP_DIR" && ! -L "$APP_DIR" ]] || fail "Каталог приложения уже существует: $APP_DIR"
    [[ ! -e "$CONFIG_DIR" && ! -L "$CONFIG_DIR" ]] || fail "Каталог конфигурации уже существует: $CONFIG_DIR"
    [[ ! -e "$LOG_DIR" && ! -L "$LOG_DIR" ]] || fail "Каталог журналов уже существует: $LOG_DIR"
    [[ ! -e "$SERVICE_FILE" && ! -L "$SERVICE_FILE" ]] || fail "Systemd-служба уже существует: $SERVICE_FILE"
    [[ ! -e "$NGINX_SITE" && ! -L "$NGINX_SITE" ]] || fail "Сайт Nginx уже существует: $NGINX_SITE"
    [[ ! -e "$NGINX_LINK" && ! -L "$NGINX_LINK" ]] || fail "Сайт Nginx уже включён: $NGINX_LINK"
    ! getent passwd "$SERVICE_USER" >/dev/null || fail "Пользователь службы уже существует: $SERVICE_USER"
    ! getent group "$SERVICE_GROUP" >/dev/null || fail "Группа службы уже существует: $SERVICE_GROUP"
fi

PUBLIC_HOST="${PUBLIC_HOST:-}"
if [[ -z "$PUBLIC_HOST" ]]; then
    read -r -p "Домен или IPv4-адрес для доступа к панели: " PUBLIC_HOST
fi
python3 - "$PUBLIC_HOST" <<'PY' || fail "Укажи корректное доменное имя или IPv4-адрес."
import ipaddress
import re
import sys

value = sys.argv[1]
try:
    ipaddress.IPv4Address(value)
except ipaddress.AddressValueError:
    labels = value.rstrip(".").split(".")
    if not value or len(value) > 253 or any(
        not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
        for label in labels
    ):
        raise SystemExit(1)
PY

printf '\n[WARN] В этом режиме панель будет доступна по HTTP без шифрования. Не используй его для передачи настоящих паролей через Интернет.\n'
HTTP_CONFIRM="${INSTALLER_CONFIRM_HTTP:-}"
if [[ -z "$HTTP_CONFIRM" ]]; then
    read -r -p "Продолжить HTTP-установку для теста? [y/N]: " HTTP_CONFIRM
fi
[[ "$HTTP_CONFIRM" =~ ^([Yy]|[Yy][Ee][Ss])$ ]] || fail "Установка HTTP отменена."

if [[ "${INSTALLER_DRY_RUN:-0}" == "1" ]]; then
    printf '\n[DRY RUN] Режим: %s\n' "$MODE"
    printf '[DRY RUN] Каталог данных: %s\n' "$DATA_DIR"
    printf '[DRY RUN] Каталог приложения: %s\n' "$APP_DIR"
    printf '[DRY RUN] URL: http://%s\n' "$PUBLIC_HOST"
    printf '[DRY RUN] Изменений в системе не выполнено.\n'
    exit 0
fi

printf '\n[3/6] Установка системных зависимостей...\n'
bash "$SCRIPT_DIR/lib/install-dependencies.sh"

printf '\n[4/6] Подготовка пользователя, данных и приложения...\n'
SERVICE_USER="$SERVICE_USER" SERVICE_GROUP="$SERVICE_GROUP" \
    bash "$SCRIPT_DIR/lib/create-service-user.sh"
if [[ "$MODE" == "existing" ]]; then
    SOURCE_DATA_DIR="$SOURCE_DATA_DIR" DATA_DIR="$DATA_DIR" BACKUP_DIR="$BACKUP_DIR" \
        bash "$SCRIPT_DIR/lib/copy-existing-data.sh"
fi
SERVICE_USER="$SERVICE_USER" SERVICE_GROUP="$SERVICE_GROUP" DATA_DIR="$DATA_DIR" LOG_DIR="$LOG_DIR" \
    bash "$SCRIPT_DIR/lib/prepare-directories.sh" "$MODE"
APP_DIR="$APP_DIR" SOURCE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)" \
    bash "$SCRIPT_DIR/lib/install-application.sh"

printf '\n[5/6] Создание конфигурации и запуск службы...\n'
APP_DIR="$APP_DIR" CONFIG_DIR="$CONFIG_DIR" CONFIG_FILE="$CONFIG_FILE" DATA_DIR="$DATA_DIR" \
    LOG_DIR="$LOG_DIR" PANEL_PORT="$PANEL_PORT" PANEL_PUBLIC_URL="http://$PUBLIC_HOST" \
    bash "$SCRIPT_DIR/lib/create-config.sh"

SERVICE_USER="$SERVICE_USER" SERVICE_GROUP="$SERVICE_GROUP" APP_DIR="$APP_DIR" \
    CONFIG_FILE="$CONFIG_FILE" DATA_DIR="$DATA_DIR" LOG_DIR="$LOG_DIR" \
    bash "$SCRIPT_DIR/lib/install-systemd-service.sh"
systemctl enable --now multisub-panel.service || {
    systemctl status --no-pager --full multisub-panel.service >&2 || true
    journalctl -u multisub-panel.service -n 40 --no-pager >&2 || true
    fail "Не удалось запустить systemd-службу."
}

HEALTH_OK=0
for _ in {1..30}; do
    if [[ "$(curl --connect-timeout 2 -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PANEL_PORT/health" 2>/dev/null || true)" == "200" ]]; then
        HEALTH_OK=1
        break
    fi
    sleep 1
done
if [[ "$HEALTH_OK" -ne 1 ]]; then
    systemctl status --no-pager --full multisub-panel.service >&2 || true
    journalctl -u multisub-panel.service -n 40 --no-pager >&2 || true
    fail "Панель не ответила на локальную проверку /health."
fi

printf '\n[6/6] Настройка Nginx и проверка доступа...\n'
PUBLIC_HOST="$PUBLIC_HOST" PANEL_PORT="$PANEL_PORT" bash "$SCRIPT_DIR/lib/install-nginx-site.sh"

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    if ! ufw status 2>/dev/null | grep -Eq '^80/tcp[[:space:]]+ALLOW'; then
        ufw allow 80/tcp
    fi
fi

NGINX_HTTP_CODE="$(curl --connect-timeout 2 -sS -o /dev/null -w '%{http_code}' \
    -H "Host: $PUBLIC_HOST" http://127.0.0.1/health || true)"
[[ "$NGINX_HTTP_CODE" == "200" ]] || fail "Nginx не проксировал /health (HTTP $NGINX_HTTP_CODE)."

printf '\n[OK] Установка завершена.\n'
printf '[INFO] Панель: http://%s\n' "$PUBLIC_HOST"
printf '[INFO] Администратор: прочитай PANEL_USERNAME в %s\n' "$CONFIG_FILE"
printf '[INFO] Случайный пароль сохранён в %s (права 600).\n' "$CONFIG_FILE"
printf '[WARN] HTTP не шифрует логин, пароль или сессионную cookie; оставь сайт только для теста до настройки HTTPS.\n'
