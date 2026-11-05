#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${STATE_FILE:-/run/multisub-panel-install.state}"

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail "Требуются права root."
[[ "$STATE_FILE" == /* ]] || fail "STATE_FILE должен быть абсолютным путём."
[[ ! -e "$STATE_FILE" && ! -L "$STATE_FILE" ]] ||
    fail "Файл состояния уже существует: $STATE_FILE"

printf '%s\n' '======================================'
printf '%s\n' '       MultiSub Panel Installer'
printf '%s\n' '======================================'
printf '\n'
printf '%s\n' 'Выберите режим установки:'
printf '%s\n' '  1) Новая установка'
printf '%s\n' '  2) Подключить существующие данные MultiSub'
printf '%s\n' '  0) Выход без изменений'
printf '\n'

read -r -p 'Ваш выбор [0-2]: ' choice

case "$choice" in
    1)
        MODE="new"
        read -r -p 'Абсолютный путь для новых данных: ' DATA_DIR
        SOURCE_DATA_DIR=""
        ;;
    2)
        MODE="existing"
        read -r -p 'Абсолютный путь к исходным данным MultiSub: ' SOURCE_DATA_DIR
        read -r -p 'Абсолютный путь для копии данных панели: ' DATA_DIR
        ;;
    0)
        printf '%s\n' 'Выход без изменений.'
        exit 10
        ;;
    *)
        fail "Недопустимый выбор. Введите 0, 1 или 2."
        ;;
esac

[[ "$DATA_DIR" == /* && "$DATA_DIR" != "/" ]] ||
    fail "Недопустимый путь назначения."

if [[ "$MODE" == "existing" ]]; then
    [[ "$SOURCE_DATA_DIR" == /* && "$SOURCE_DATA_DIR" != "/" ]] ||
        fail "Недопустимый путь источника."
    bash "$SCRIPT_DIR/check-data-dir.sh" existing "$SOURCE_DATA_DIR"
else
    bash "$SCRIPT_DIR/check-data-dir.sh" new "$DATA_DIR"
fi

TEMP_FILE="$(mktemp "${STATE_FILE}.XXXXXX")"
trap 'rm -f -- "$TEMP_FILE"' EXIT

python3 - "$TEMP_FILE" "$MODE" "$DATA_DIR" "$SOURCE_DATA_DIR" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = {
    "mode": sys.argv[2],
    "data_dir": sys.argv[3],
    "source_data_dir": sys.argv[4],
}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PY

chmod 0600 "$TEMP_FILE"
ln -- "$TEMP_FILE" "$STATE_FILE"
rm -- "$TEMP_FILE"
trap - EXIT

printf '\n%s\n' 'Параметры установки сохранены.'
printf '[INFO] Файл состояния: %s\n' "$STATE_FILE"
