#!/usr/bin/env bash
set -Eeuo pipefail

fail() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || fail "Требуются права root."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_COMMAND="$SCRIPT_DIR/../subpanel"
COMMAND_FILE="/usr/local/sbin/subpanel"
MANIFEST="/etc/multisub-panel/managed-paths"
MARKER_NAME=".multisub-panel-managed"
MARKER_TEXT="MultiSub Panel managed path v1"

CONFIG_DIR="${CONFIG_DIR:-/etc/multisub-panel}"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/panel.env}"
APP_DIR="${APP_DIR:-/opt/multisub-panel}"
DATA_DIR="${DATA_DIR:-/var/lib/multisub-panel}"
LOG_DIR="${LOG_DIR:-/var/log/multisub-panel}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/multisub-panel}"
PANEL_PORT="${PANEL_PORT:-18082}"
SERVICE_USER="${SERVICE_USER:-multisub-panel}"
SERVICE_GROUP="${SERVICE_GROUP:-$SERVICE_USER}"
SERVICE_UID="$(id -u "$SERVICE_USER" 2>/dev/null || true)"
SERVICE_GID="$(getent group "$SERVICE_GROUP" | cut -d: -f3 || true)"

[[ "$CONFIG_DIR" == "/etc/multisub-panel" && "$CONFIG_FILE" == "$CONFIG_DIR/panel.env" ]] ||
    fail "Команда управления поддерживает стандартный каталог конфигурации /etc/multisub-panel."
[[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || fail "Не найдена конфигурация панели."
[[ -n "$SERVICE_UID" && -n "$SERVICE_GID" ]] || fail "Системный пользователь или группа панели не найдены."
[[ -f "$SOURCE_COMMAND" && ! -L "$SOURCE_COMMAND" ]] || fail "Не найден скрипт команды управления."
[[ ! -e "$COMMAND_FILE" && ! -L "$COMMAND_FILE" ]] || fail "Команда уже существует: $COMMAND_FILE"
[[ ! -e "$MANIFEST" && ! -L "$MANIFEST" ]] || fail "Манифест установки уже существует: $MANIFEST"

for path in "$APP_DIR" "$DATA_DIR" "$LOG_DIR"; do
    [[ -d "$path" && ! -L "$path" ]] || fail "Каталог установки отсутствует или небезопасен: $path"
    marker="$path/$MARKER_NAME"
    [[ ! -e "$marker" && ! -L "$marker" ]] || fail "Метка уже существует: $marker"
done

install -o root -g root -m 0600 /dev/null "$APP_DIR/$MARKER_NAME"
printf '%s\n' "$MARKER_TEXT" > "$APP_DIR/$MARKER_NAME"
install -o root -g root -m 0600 /dev/null "$DATA_DIR/$MARKER_NAME"
printf '%s\n' "$MARKER_TEXT" > "$DATA_DIR/$MARKER_NAME"
install -o root -g root -m 0600 /dev/null "$LOG_DIR/$MARKER_NAME"
printf '%s\n' "$MARKER_TEXT" > "$LOG_DIR/$MARKER_NAME"

TEMP_MANIFEST="$(mktemp "$CONFIG_DIR/.managed-paths.XXXXXX")"
cleanup() { rm -f -- "$TEMP_MANIFEST"; }
trap cleanup EXIT
{
    printf 'APP_DIR=%s\n' "$APP_DIR"
    printf 'DATA_DIR=%s\n' "$DATA_DIR"
    printf 'LOG_DIR=%s\n' "$LOG_DIR"
    printf 'BACKUP_DIR=%s\n' "$BACKUP_DIR"
    printf 'PANEL_PORT=%s\n' "$PANEL_PORT"
    printf 'SERVICE_USER=%s\n' "$SERVICE_USER"
    printf 'SERVICE_GROUP=%s\n' "$SERVICE_GROUP"
    printf 'SERVICE_UID=%s\n' "$SERVICE_UID"
    printf 'SERVICE_GID=%s\n' "$SERVICE_GID"
} > "$TEMP_MANIFEST"
chown root:root "$TEMP_MANIFEST"
chmod 0600 "$TEMP_MANIFEST"
ln -- "$TEMP_MANIFEST" "$MANIFEST" || fail "Не удалось записать манифест установки."
rm -- "$TEMP_MANIFEST"
TEMP_MANIFEST=""
trap - EXIT

install -o root -g root -m 0755 "$SOURCE_COMMAND" "$COMMAND_FILE"
printf '[OK] Команда управления установлена: sudo subpanel\n'
