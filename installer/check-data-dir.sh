#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

info() {
    printf '[INFO] %s\n' "$1"
}

usage() {
    printf '%s\n' \
        "Использование:" \
        "  $0 new /путь/к/каталогу" \
        "  $0 existing /путь/к/каталогу"
}

[[ $# -eq 2 ]] || {
    usage
    exit 2
}

mode="$1"
data_dir="${2%/}"

[[ -n "$data_dir" ]] || fail "Путь к каталогу не указан."
[[ "$data_dir" = /* ]] || fail "Укажите абсолютный путь."
[[ "$data_dir" != "/" ]] || fail "Корневой каталог / использовать нельзя."

case "$mode" in
    new)
        if [[ -e "$data_dir" ]]; then
            fail "Каталог уже существует. Для защиты данных новая установка в него запрещена: $data_dir"
        fi

        info "Каталог свободен для новой установки: $data_dir"
        info "Проверка завершена. Каталог не создан."
        ;;

    existing)
        [[ -d "$data_dir" && ! -L "$data_dir" ]] ||
            fail "Каталог существующих данных отсутствует или является символической ссылкой: $data_dir"

        [[ -f "$data_dir/users.json" && ! -L "$data_dir/users.json" ]] ||
            fail "В каталоге нет users.json. Подключение отменено."

        [[ -r "$data_dir/users.json" ]] ||
            fail "Нет прав на чтение users.json."

        [[ -r "$data_dir" && -x "$data_dir" ]] ||
            fail "Нет прав на чтение или доступ к каталогу данных."

        python3 - "$data_dir/users.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

try:
    with path.open("r", encoding="utf-8") as file:
        data = json.load(file)
except (OSError, UnicodeError, json.JSONDecodeError) as exc:
    print(f"[ERROR] users.json не удалось прочитать как корректный JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(data, dict):
    print("[ERROR] Ожидался JSON-объект в users.json. Подключение отменено.", file=sys.stderr)
    raise SystemExit(1)

print(f"[INFO] users.json корректен; записей верхнего уровня: {len(data)}")
PY

        if [[ -e "$data_dir/users-trash.json" ]]; then
            [[ -f "$data_dir/users-trash.json" && ! -L "$data_dir/users-trash.json" ]] ||
                fail "users-trash.json существует, но не является обычным файлом."

            python3 - "$data_dir/users-trash.json" <<'PY'
import json
import sys
from pathlib import Path

try:
    with Path(sys.argv[1]).open("r", encoding="utf-8") as file:
        data = json.load(file)
except (OSError, UnicodeError, json.JSONDecodeError) as exc:
    print(f"[ERROR] users-trash.json не удалось прочитать как корректный JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(data, dict):
    print("[ERROR] Ожидался JSON-объект в users-trash.json.", file=sys.stderr)
    raise SystemExit(1)

print(f"[INFO] users-trash.json корректен; записей верхнего уровня: {len(data)}")
PY
        else
            info "users-trash.json отсутствует; существующий файл создаваться не будет."
        fi

        info "Проверка завершена. Данные не изменены."
        ;;

    *)
        usage
        fail "Неизвестный режим: $mode"
        ;;
esac
