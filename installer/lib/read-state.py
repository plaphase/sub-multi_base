#!/usr/bin/env python3
import base64
import json
import sys
from pathlib import Path

def fail(message):
    print(f"[ERROR] {message}", file=sys.stderr)
    raise SystemExit(1)

if len(sys.argv) != 2:
    fail("Не указан файл состояния.")

path = Path(sys.argv[1])

if path.is_symlink() or not path.is_file():
    fail("Файл состояния отсутствует или является ссылкой.")

if path.stat().st_mode & 0o077:
    fail("Небезопасные права файла состояния. Требуются права 600.")

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError):
    fail("Не удалось прочитать JSON-файл состояния.")

if not isinstance(data, dict):
    fail("Корневой элемент JSON должен быть объектом.")

if set(data) != {"mode", "data_dir", "source_data_dir"}:
    fail("Неверный набор полей файла состояния.")

if data["mode"] not in ("new", "existing"):
    fail("Недопустимый режим установки.")

for key in ("data_dir", "source_data_dir"):
    if not isinstance(data[key], str) or "\n" in data[key] or "\0" in data[key]:
        fail(f"Некорректное значение поля {key}.")

if not data["data_dir"].startswith("/") or data["data_dir"] == "/":
    fail("Недопустимый путь назначения.")

if data["mode"] == "existing":
    if not data["source_data_dir"].startswith("/") or data["source_data_dir"] == "/":
        fail("Недопустимый путь источника.")
elif data["source_data_dir"] != "":
    fail("Для новой установки источник должен быть пустым.")

for key in ("mode", "data_dir", "source_data_dir"):
    value = data[key].encode("utf-8")
    encoded = base64.b64encode(value).decode("ascii")
    print(encoded if encoded else "-")
