#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail "Требуются права root."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../systemd/multisub-panel.service.template"
UNIT_FILE="/etc/systemd/system/multisub-panel.service"
SERVICE_USER="${SERVICE_USER:-multisub-panel}"
SERVICE_GROUP="${SERVICE_GROUP:-multisub-panel}"
APP_DIR="${APP_DIR:-/opt/multisub-panel}"
CONFIG_FILE="${CONFIG_FILE:-/etc/multisub-panel/panel.env}"
DATA_DIR="${DATA_DIR:-/var/lib/multisub-panel}"
LOG_DIR="${LOG_DIR:-/var/log/multisub-panel}"

[[ -f "$TEMPLATE" && ! -L "$TEMPLATE" ]] || fail "Не найден шаблон systemd-службы."
[[ ! -e "$UNIT_FILE" && ! -L "$UNIT_FILE" ]] || fail "Systemd-служба уже существует: $UNIT_FILE"

TEMP_FILE="$(mktemp /etc/systemd/system/.multisub-panel.service.XXXXXX)"
UNIT_CREATED=0
cleanup() {
    rm -f -- "$TEMP_FILE"
    if [[ "$UNIT_CREATED" -eq 1 ]]; then
        rm -f -- "$UNIT_FILE"
    fi
}
trap cleanup EXIT

python3 - "$TEMPLATE" "$TEMP_FILE" "$SERVICE_USER" "$SERVICE_GROUP" "$APP_DIR" "$CONFIG_FILE" "$DATA_DIR" "$LOG_DIR" <<'PY'
import sys
from pathlib import Path

template_path, output_path, *values = sys.argv[1:]
tokens = (
    "@SERVICE_USER@",
    "@SERVICE_GROUP@",
    "@APP_DIR@",
    "@CONFIG_FILE@",
    "@DATA_DIR@",
    "@LOG_DIR@",
)
text = Path(template_path).read_text(encoding="utf-8")
for token, value in zip(tokens, values, strict=True):
    text = text.replace(token, value)
if any(token in text for token in tokens):
    raise SystemExit("Не все значения шаблона systemd заменены.")
Path(output_path).write_text(text, encoding="utf-8")
PY

chown root:root "$TEMP_FILE"
chmod 0644 "$TEMP_FILE"
ln -- "$TEMP_FILE" "$UNIT_FILE" || fail "Не удалось безопасно создать unit-файл."
UNIT_CREATED=1
rm -- "$TEMP_FILE"
TEMP_FILE=""

systemd-analyze verify "$UNIT_FILE" || fail "Systemd отклонил unit-файл."
systemctl daemon-reload
UNIT_CREATED=0
trap - EXIT
printf '[OK] Systemd-служба подготовлена.\n'
