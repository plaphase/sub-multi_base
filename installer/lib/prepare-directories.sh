#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$EUID" -eq 0 ]] || { printf "[ERROR] Требуются права root.\n" >&2; exit 1; }

SERVICE_USER="${SERVICE_USER:-multisub-panel}"
SERVICE_GROUP="${SERVICE_GROUP:-multisub-panel}"
DATA_DIR="${DATA_DIR:-/var/lib/multisub-panel}"
LOG_DIR="${LOG_DIR:-/var/log/multisub-panel}"
MODE="${1:-}"
SOURCE_DATA_DIR="${SOURCE_DATA_DIR:-}"

if [[ "$MODE" == "existing" ]]; then
    [[ -n "$SOURCE_DATA_DIR" ]] ||
        { printf '[ERROR] Не задан SOURCE_DATA_DIR — путь к оригинальным данным.\n' >&2; exit 1; }
    [[ -d "$SOURCE_DATA_DIR" && ! -L "$SOURCE_DATA_DIR" ]] ||
        { printf '[ERROR] Исходный каталог не существует или является ссылкой.\n' >&2; exit 1; }
    [[ -d "$DATA_DIR" && ! -L "$DATA_DIR" ]] ||
        { printf '[ERROR] Каталог назначения должен быть отдельной обычной директорией.\n' >&2; exit 1; }

    SOURCE_REAL="$(realpath -e "$SOURCE_DATA_DIR")"
    DATA_REAL="$(realpath -e "$DATA_DIR")"
    [[ "$SOURCE_REAL" != "$DATA_REAL" ]] ||
        { printf '[ERROR] Источник и назначение совпадают.\n' >&2; exit 1; }
fi

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

[[ "$MODE" == "new" || "$MODE" == "existing" ]] ||
    fail "Укажи режим: new или existing."

getent passwd "$SERVICE_USER" >/dev/null ||
    fail "Нет системного пользователя: $SERVICE_USER"
getent group "$SERVICE_GROUP" >/dev/null ||
    fail "Нет системной группы: $SERVICE_GROUP"

for dir in "$DATA_DIR" "$LOG_DIR"; do
    [[ "$dir" == /* && "$dir" != "/" ]] ||
        fail "Недопустимый путь: $dir"
done

if [[ "$MODE" == "new" ]]; then
    [[ ! -e "$DATA_DIR" && ! -L "$DATA_DIR" ]] || fail "Каталог новых данных уже существует или является ссылкой: $DATA_DIR"
    install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0750 "$DATA_DIR"
    printf '{}\n' > "$DATA_DIR/users.json"
    printf '{}\n' > "$DATA_DIR/users-trash.json"
    chown "$SERVICE_USER:$SERVICE_GROUP" "$DATA_DIR/users.json" "$DATA_DIR/users-trash.json"
    chmod 0640 "$DATA_DIR/users.json" "$DATA_DIR/users-trash.json"
else
    [[ -d "$DATA_DIR" ]] || fail "Каталог скопированных данных не найден."
    [[ -f "$DATA_DIR/users.json" && ! -L "$DATA_DIR/users.json" ]] || fail "users.json должен быть обычным файлом без символических ссылок."
    if [[ -e "$DATA_DIR/users-trash.json" || -L "$DATA_DIR/users-trash.json" ]]; then
        [[ -f "$DATA_DIR/users-trash.json" && ! -L "$DATA_DIR/users-trash.json" ]] || fail "users-trash.json должен быть обычным файлом без символических ссылок."
    fi

    python3 - "$DATA_DIR" <<'PY'
import json
import sys
from pathlib import Path

directory = Path(sys.argv[1])
for name in ("users.json", "users-trash.json"):
    path = directory / name
    if not path.exists():
        if name == "users-trash.json":
            continue
        raise SystemExit(f"[ERROR] Не найден {name}")
    with path.open(encoding="utf-8") as file:
        data = json.load(file)
    if not isinstance(data, dict):
        raise SystemExit(f"[ERROR] {name} должен содержать JSON-объект")
print("[OK] JSON-файлы проверены.")
PY

    chown "$SERVICE_USER:$SERVICE_GROUP" "$DATA_DIR"
    chmod 0750 "$DATA_DIR"
    for file in users.json users-trash.json; do
        if [[ -f "$DATA_DIR/$file" ]]; then
            chown "$SERVICE_USER:$SERVICE_GROUP" "$DATA_DIR/$file"
            chmod 0640 "$DATA_DIR/$file"
        fi
    done
fi

install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0750 "$LOG_DIR"
if [[ -L "$LOG_DIR/multisub.log" ]]; then
    fail "Файл журнала является символической ссылкой."
elif [[ -e "$LOG_DIR/multisub.log" ]]; then
    [[ -f "$LOG_DIR/multisub.log" ]] || fail "Путь журнала не является обычным файлом."
    chown "$SERVICE_USER:$SERVICE_GROUP" "$LOG_DIR/multisub.log"
    chmod 0640 "$LOG_DIR/multisub.log"
else
    install -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0640 /dev/null "$LOG_DIR/multisub.log"
fi

printf '[OK] Каталоги данных и логов подготовлены: режим %s.\n' "$MODE"
