#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${STATE_FILE:-/run/multisub-panel-install.state}"
DEFAULT_DATA_DIR="${DEFAULT_DATA_DIR:-/var/lib/multisub-panel}"

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

[[ "$EUID" -eq 0 ]] || fail "Требуются права root."
[[ "$STATE_FILE" == /* ]] || fail "STATE_FILE должен быть абсолютным путём."
[[ ! -e "$STATE_FILE" && ! -L "$STATE_FILE" ]] ||
    fail "Файл состояния уже существует: $STATE_FILE"

printf '%s\n' '======================================'
printf '%s\n' '       MultiSub Panel Installer'
printf '%s\n' '======================================'
printf '\n'
printf '%s\n' 'Выберите вариант установки:'
printf '  1) Новая пустая панель (данные: %s)\n' "$DEFAULT_DATA_DIR"
printf '%s\n' '  2) Установить панель с существующими данными MultiSub'
printf '%s\n' '     Исходные данные останутся на месте; установщик создаст проверенную копию.'
printf '%s\n' '  3) Новая панель в другом каталоге данных'
printf '%s\n' '  0) Отмена'
printf '\n'

ask 'Вариант [1]: '
choice="$REPLY"
choice="${choice:-1}"

MODE=""
DATA_DIR=""
SOURCE_DATA_DIR=""

case "$choice" in
    1)
        MODE="new"
        DATA_DIR="$DEFAULT_DATA_DIR"
        ;;
    2)
        MODE="existing"
        declare -a CANDIDATES=()

        add_candidate() {
            local candidate="$1" resolved current
            [[ -n "$candidate" && -d "$candidate" && ! -L "$candidate" ]] || return 0
            [[ -f "$candidate/users.json" && ! -L "$candidate/users.json" ]] || return 0
            resolved="$(realpath -e -- "$candidate")" || return 0
            for current in "${CANDIDATES[@]}"; do
                [[ "$current" != "$resolved" ]] || return 0
            done
            CANDIDATES+=("$resolved")
        }

        if [[ -n "${MULTISUB_DATA_DIR:-}" ]]; then
            add_candidate "$MULTISUB_DATA_DIR"
        else
            add_candidate /var/lib/multisub-panel
            add_candidate /var/lib/multisub
            add_candidate /opt/multisub-panel/data
            add_candidate /opt/multisub-panel
            add_candidate /opt/multisub-panel-dev/data
            add_candidate /opt/multisub-panel-dev
            add_candidate /srv/multisub-panel
            add_candidate /srv/multisub
        fi

        if ((${#CANDIDATES[@]} == 1)); then
            SOURCE_DATA_DIR="${CANDIDATES[0]}"
            printf '[INFO] Найдены данные MultiSub: %s\n' "$SOURCE_DATA_DIR"
        elif ((${#CANDIDATES[@]} > 1)); then
            printf '\nНайдено несколько каталогов с users.json:\n'
            for i in "${!CANDIDATES[@]}"; do
                printf '  %d) %s\n' "$((i + 1))" "${CANDIDATES[$i]}"
            done
            printf '%s\n' '  0) Указать другой каталог'
            ask 'Использовать каталог [1]: '
            candidate_choice="$REPLY"
            candidate_choice="${candidate_choice:-1}"
            if [[ "$candidate_choice" =~ ^[0-9]+$ ]] &&
                (( candidate_choice >= 1 && candidate_choice <= ${#CANDIDATES[@]} )); then
                SOURCE_DATA_DIR="${CANDIDATES[$((candidate_choice - 1))]}"
            elif [[ "$candidate_choice" == "0" ]]; then
                ask 'Путь к каталогу с users.json: '
                SOURCE_DATA_DIR="$REPLY"
            else
                fail "Выбери номер найденного каталога или 0."
            fi
        else
            printf '%s\n' '[INFO] Стандартный каталог данных автоматически не найден.'
            ask 'Путь к каталогу с users.json (или 0 для отмены): '
            SOURCE_DATA_DIR="$REPLY"
            [[ "$SOURCE_DATA_DIR" != "0" ]] || {
                printf '%s\n' 'Установка отменена.'
                exit 10
            }
        fi

        [[ "$SOURCE_DATA_DIR" == /* && "$SOURCE_DATA_DIR" != "/" ]] ||
            fail "Путь к исходным данным должен быть абсолютным."

        DATA_DIR="$DEFAULT_DATA_DIR"
        if [[ "$DATA_DIR" == "$SOURCE_DATA_DIR" || -e "$DATA_DIR" || -L "$DATA_DIR" ]]; then
            DATA_DIR="${DEFAULT_DATA_DIR}-import"
            suffix=2
            while [[ -e "$DATA_DIR" || -L "$DATA_DIR" || "$DATA_DIR" == "$SOURCE_DATA_DIR" ]]; do
                DATA_DIR="${DEFAULT_DATA_DIR}-import-$suffix"
                suffix=$((suffix + 1))
            done
        fi
        printf '[INFO] Копия будет создана в: %s\n' "$DATA_DIR"
        ;;
    3)
        MODE="new"
        ask 'Абсолютный путь для новых данных: '
        DATA_DIR="$REPLY"
        ;;
    0)
        printf '%s\n' 'Установка отменена.'
        exit 10
        ;;
    *)
        fail "Недопустимый вариант. Выбери 0, 1 или 2."
        ;;
esac

[[ "$DATA_DIR" == /* && "$DATA_DIR" != "/" ]] ||
    fail "Недопустимый путь назначения."

if [[ "$MODE" == "existing" ]]; then
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

printf '\n%s\n' 'Вариант установки выбран.'
printf '[INFO] Файл состояния: %s\n' "$STATE_FILE"
