#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DATA_DIR="${SOURCE_DATA_DIR:-}"
DATA_DIR="${DATA_DIR:-/var/lib/multisub-panel}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/multisub-panel}"

fail() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || fail "Требуются права root."
[[ -n "$SOURCE_DATA_DIR" ]] || fail "Не задан SOURCE_DATA_DIR."
[[ -d "$SOURCE_DATA_DIR" && ! -L "$SOURCE_DATA_DIR" ]] || fail "Источник не является обычным каталогом."
[[ -r "$SOURCE_DATA_DIR" && -x "$SOURCE_DATA_DIR" ]] || fail "Нет доступа для чтения исходного каталога."
[[ ! -e "$DATA_DIR" && ! -L "$DATA_DIR" ]] || fail "Каталог назначения уже существует."
[[ "$DATA_DIR" == /* && "$DATA_DIR" != "/" ]] || fail "Недопустимый путь назначения."

[[ "$BACKUP_DIR" == /* && "$BACKUP_DIR" != "/" ]] || fail "Недопустимый путь резервных копий."
[[ ! -L "$BACKUP_DIR" ]] || fail "Каталог резервных копий не должен быть символической ссылкой."

SOURCE_REAL="$(realpath -e "$SOURCE_DATA_DIR")"
PARENT_REAL="$(realpath -m "$(dirname "$DATA_DIR")")"
DATA_REAL="$PARENT_REAL/$(basename "$DATA_DIR")"
BACKUP_REAL="$(realpath -m "$BACKUP_DIR")"

paths=( "$SOURCE_REAL" "$DATA_REAL" "$BACKUP_REAL" )
for ((i=0; i<${#paths[@]}; i++)); do
    for ((j=i+1; j<${#paths[@]}; j++)); do
        a="${paths[$i]%/}/"
        b="${paths[$j]%/}/"
        [[ "$a" != "$b" && "$a" != "$b"* && "$b" != "$a"* ]] ||
            fail "Источник, назначение и резервные копии не должны совпадать или находиться друг внутри друга."
    done
done

[[ -f "$SOURCE_DATA_DIR/users.json" && ! -L "$SOURCE_DATA_DIR/users.json" ]] ||
    fail "В источнике отсутствует обычный файл users.json."

python3 - "$SOURCE_DATA_DIR" <<'PY'
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
for name in ("users.json", "users-trash.json"):
    path = source / name
    if not path.exists():
        if name == "users-trash.json":
            continue
        raise SystemExit(f"[ERROR] Не найден {name}")
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"[ERROR] {name} не является обычным файлом")
    with path.open(encoding="utf-8") as file:
        data = json.load(file)
    if not isinstance(data, dict):
        raise SystemExit(f"[ERROR] {name} должен содержать JSON-объект")
print("[OK] Исходные JSON-файлы проверены.")
PY

install -d -o root -g root -m 0700 "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/multisub-panel-$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
[[ ! -e "$BACKUP_FILE" && ! -L "$BACKUP_FILE" ]] ||
    fail "Файл резервной копии уже существует."

BACKUP_FILES=(users.json)
[[ ! -f "$SOURCE_DATA_DIR/users-trash.json" ]] || BACKUP_FILES+=(users-trash.json)

tar -czf "$BACKUP_FILE" -C "$SOURCE_DATA_DIR" "${BACKUP_FILES[@]}" || fail "Не удалось создать резервную копию."
[[ -f "$BACKUP_FILE" && ! -L "$BACKUP_FILE" ]] || fail "Резервная копия не является обычным файлом."
[[ -s "$BACKUP_FILE" ]] || fail "Файл резервной копии пуст."
chmod 0600 "$BACKUP_FILE"
python3 - "$BACKUP_FILE" <<'PY_ARCHIVE'
import sys
import tarfile

allowed = {"users.json", "users-trash.json"}

try:
    with tarfile.open(sys.argv[1], "r:gz") as archive:
        members = archive.getmembers()
        if not members:
            raise ValueError("Архив пустой")
        names = set()

        for member in members:
            if member.name not in allowed:
                raise ValueError(f"Недопустимое имя в архиве: {member.name}")
            if not member.isfile():
                raise ValueError(f"Недопустимый тип записи: {member.name}")
            if member.name in names:
                raise ValueError(f"Повторяющаяся запись: {member.name}")
            names.add(member.name)

        if "users.json" not in names:
            raise ValueError("В архиве отсутствует users.json")

except (tarfile.TarError, OSError, ValueError) as error:
    raise SystemExit(f"[ERROR] Архив не прошёл проверку: {error}")

print("[OK] Структура резервного архива проверена.")
PY_ARCHIVE

printf '[OK] Резервная копия создана и проверена: %s\n' "$BACKUP_FILE"

install -d -o root -g root -m 0755 "$(dirname "$DATA_DIR")"
TEMP_DIR="$(mktemp -d "$(dirname "$DATA_DIR")/.multisub-panel-copy.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR" || fail "Не удалось извлечь резервную копию."

python3 - "$TEMP_DIR" <<'PY_VALIDATE'
import json
import sys
from pathlib import Path

directory = Path(sys.argv[1])
allowed = {"users.json", "users-trash.json"}
entries = list(directory.iterdir())

if not entries or any(path.name not in allowed for path in entries):
    raise SystemExit("[ERROR] В распакованной копии обнаружены недопустимые файлы.")

for name in allowed:
    path = directory / name
    if not path.exists():
        if name == "users-trash.json":
            continue
        raise SystemExit("[ERROR] В копии отсутствует users.json.")
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"[ERROR] Некорректный тип файла: {name}")
    with path.open(encoding="utf-8") as file:
        if not isinstance(json.load(file), dict):
            raise SystemExit(f"[ERROR] Некорректная копия: {name}")

print("[OK] Состав и JSON распакованной копии проверены.")
PY_VALIDATE

chown root:root "$TEMP_DIR"/*
chmod 0600 "$TEMP_DIR"/*

mv -- "$TEMP_DIR" "$DATA_DIR"
trap - EXIT
printf '[OK] Данные скопированы в отдельный каталог: %s\n' "$DATA_DIR"
