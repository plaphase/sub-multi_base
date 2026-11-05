#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_DIR="${CONFIG_DIR:-/etc/multisub-panel}"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/panel.env}"
APP_DIR="${APP_DIR:-/opt/multisub-panel}"
DATA_DIR="${DATA_DIR:-/var/lib/multisub-panel}"
LOG_DIR="${LOG_DIR:-/var/log/multisub-panel}"
PANEL_PORT="${PANEL_PORT:-18082}"
PANEL_PUBLIC_URL="${PANEL_PUBLIC_URL:-}"

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

ask() {
    local prompt="$1"
    if [[ -t 1 && -r /dev/tty ]]; then
        read -r -p "$prompt" REPLY </dev/tty
    else
        read -r -p "$prompt" REPLY
    fi
}

[[ "$EUID" -eq 0 ]] || fail "Запусти скрипт от root."

validate_path() {
    local name="$1" value="$2" part
    local -a parts
    [[ "$value" =~ ^/[a-zA-Z0-9._/-]+$ ]] ||
        fail "Недопустимые символы в $name: $value"
    [[ "$value" != *//* && "$value" != */ ]] ||
        fail "Некорректный формат пути $name: $value"
    IFS="/" read -r -a parts <<< "$value"
    for part in "${parts[@]}"; do
        [[ "$part" != "." && "$part" != ".." ]] ||
            fail "Путь $name содержит недопустимый компонент: $part"
    done
}

validate_path CONFIG_DIR "$CONFIG_DIR"
validate_path CONFIG_FILE "$CONFIG_FILE"
validate_path APP_DIR "$APP_DIR"
validate_path DATA_DIR "$DATA_DIR"
validate_path LOG_DIR "$LOG_DIR"
[[ "$CONFIG_FILE" == "$CONFIG_DIR/panel.env" ]] ||
    fail "CONFIG_FILE должен указывать на $CONFIG_DIR/panel.env"

if [[ -n "$PANEL_PUBLIC_URL" ]]; then
    [[ "$PANEL_PUBLIC_URL" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?$ ]] ||
        fail "Некорректный PANEL_PUBLIC_URL."
fi

APP_DIR="${APP_DIR:-/opt/multisub-panel}"
PANEL_COOKIE_SECURE=true
if [[ "$PANEL_PUBLIC_URL" == http://* ]]; then
    PANEL_COOKIE_SECURE=false
fi

CONFIG_CURRENT="/"
IFS="/" read -r -a CONFIG_PARTS <<< "$CONFIG_DIR"
for CONFIG_PART in "${CONFIG_PARTS[@]}"; do
    [[ -n "$CONFIG_PART" ]] || continue
    CONFIG_CURRENT="${CONFIG_CURRENT%/}/$CONFIG_PART"
    [[ ! -L "$CONFIG_CURRENT" ]] ||
        fail "Компонент каталога конфигурации является символической ссылкой: $CONFIG_CURRENT"
    if [[ -e "$CONFIG_CURRENT" ]]; then
        [[ -d "$CONFIG_CURRENT" ]] ||
            fail "Компонент каталога конфигурации не является каталогом: $CONFIG_CURRENT"
    fi
done
[[ ! -e "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || fail "Конфигурация уже существует или является ссылкой: $CONFIG_FILE"

if ! [[ "$PANEL_PORT" =~ ^[0-9]+$ ]] || (( PANEL_PORT < 1 || PANEL_PORT > 65535 )); then
    fail "Некорректный порт."
fi

ask "Логин администратора [admin]: "
PANEL_USERNAME="$REPLY"
PANEL_USERNAME="${PANEL_USERNAME:-admin}"
[[ "$PANEL_USERNAME" =~ ^[a-zA-Z0-9_.-]{3,64}$ ]] || fail "Некорректный логин."

PANEL_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
PANEL_SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"

install -d -o root -g root -m 0750 "$CONFIG_DIR"

CONFIG_OWNER="$(stat -c "%U:%G" -- "$CONFIG_DIR")"
CONFIG_MODE="$(stat -c "%a" -- "$CONFIG_DIR")"
[[ "$CONFIG_OWNER" == "root:root" ]] ||
    fail "Неверный владелец каталога конфигурации: $CONFIG_OWNER"
[[ "$CONFIG_MODE" == "750" ]] ||
    fail "Неверные права каталога конфигурации: $CONFIG_MODE"

[[ ! -e "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || fail "Конфигурация уже существует или является ссылкой."

TEMP_FILE="$(mktemp "$CONFIG_DIR/.panel.env.XXXXXX")"
trap 'rm -f "$TEMP_FILE"' EXIT

{
    printf 'PANEL_USERNAME=%s\n' "$PANEL_USERNAME"
    printf 'PANEL_PASSWORD=%s\n' "$PANEL_PASSWORD"
    printf 'PANEL_SECRET_KEY=%s\n' "$PANEL_SECRET_KEY"
    printf 'PANEL_COOKIE_SECURE=%s\n' "$PANEL_COOKIE_SECURE"
    printf 'PANEL_PUBLIC_URL=%s\n' "$PANEL_PUBLIC_URL"
    printf 'MULTISUB_DATA_DIR=%s\n' "$DATA_DIR"
    printf 'MULTISUB_LOG_FILE=%s/multisub.log\n' "$LOG_DIR"
    printf 'PANEL_PORT=%s\n' "$PANEL_PORT"
    printf 'APP_TEMPLATES_DIR=%s/templates\n' "$APP_DIR"
    printf 'APP_DIR=%s\n' "$APP_DIR"
} > "$TEMP_FILE"

chmod 0600 "$TEMP_FILE"

TEMP_OWNER="$(stat -c "%U:%G" -- "$TEMP_FILE")"
TEMP_MODE="$(stat -c "%a" -- "$TEMP_FILE")"
[[ -f "$TEMP_FILE" && ! -L "$TEMP_FILE" && -s "$TEMP_FILE" ]] ||
    fail "Временная конфигурация не является обычным непустым файлом."
[[ "$TEMP_OWNER" == "root:root" ]] ||
    fail "Неверный владелец временной конфигурации: $TEMP_OWNER"
[[ "$TEMP_MODE" == "600" ]] ||
    fail "Неверные права временной конфигурации: $TEMP_MODE"

ln -- "$TEMP_FILE" "$CONFIG_FILE" || fail "Не удалось безопасно создать конфигурацию: файл уже существует или операция запрещена."

FINAL_OWNER="$(stat -c "%U:%G" -- "$CONFIG_FILE")"
FINAL_MODE="$(stat -c "%a" -- "$CONFIG_FILE")"
[[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" && -s "$CONFIG_FILE" ]] ||
    fail "Итоговая конфигурация не является обычным непустым файлом."
[[ "$FINAL_OWNER" == "root:root" ]] ||
    fail "Неверный владелец итоговой конфигурации: $FINAL_OWNER"
[[ "$FINAL_MODE" == "600" ]] ||
    fail "Неверные права итоговой конфигурации: $FINAL_MODE"

rm -- "$TEMP_FILE"
trap - EXIT

printf '\n[OK] Конфигурация создана.\n'
printf '[INFO] Логин администратора: %s\n' "$PANEL_USERNAME"
printf '[INFO] Временный пароль: %s\n' "$PANEL_PASSWORD"
printf '[WARN] Сохраните пароль сейчас.\n'
