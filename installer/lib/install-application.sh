#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/multisub-panel}"
SOURCE_DIR="${SOURCE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

info() {
    printf '[INFO] %s\n' "$1"
}

[[ "${EUID}" -eq 0 ]] || fail "Запусти скрипт от root."

[[ "$SOURCE_DIR" == /* && "$SOURCE_DIR" != "/" && "$SOURCE_DIR" != */ && "$SOURCE_DIR" != *//* ]] ||
    fail "Недопустимый исходный путь: $SOURCE_DIR"

SOURCE_CURRENT="/"
IFS='/' read -r -a SOURCE_PARTS <<< "$SOURCE_DIR"
for SOURCE_PART in "${SOURCE_PARTS[@]}"; do
    [[ -n "$SOURCE_PART" ]] || continue
    [[ "$SOURCE_PART" != "." && "$SOURCE_PART" != ".." ]] ||
        fail "Исходный путь содержит недопустимый компонент: $SOURCE_DIR"
    SOURCE_CURRENT="${SOURCE_CURRENT%/}/$SOURCE_PART"
    [[ ! -L "$SOURCE_CURRENT" ]] ||
        fail "Компонент исходного пути является символической ссылкой: $SOURCE_CURRENT"
    [[ -d "$SOURCE_CURRENT" ]] ||
        fail "Компонент исходного пути не является каталогом: $SOURCE_CURRENT"
done

[[ -d "$SOURCE_DIR/app" && ! -L "$SOURCE_DIR/app" ]] || fail "Каталог app отсутствует или является символической ссылкой."
[[ -d "$SOURCE_DIR/templates" && ! -L "$SOURCE_DIR/templates" ]] || fail "Каталог templates отсутствует или является символической ссылкой."
[[ -f "$SOURCE_DIR/app/panel.py" && ! -L "$SOURCE_DIR/app/panel.py" ]] || fail "Файл app/panel.py отсутствует или является символической ссылкой."
[[ -f "$SOURCE_DIR/requirements.txt" && ! -L "$SOURCE_DIR/requirements.txt" ]] || fail "Файл requirements.txt отсутствует или является символической ссылкой."
[[ -f "$SOURCE_DIR/installer/run-panel.sh" && ! -L "$SOURCE_DIR/installer/run-panel.sh" ]] || fail "Файл run-panel.sh отсутствует или является символической ссылкой."

[[ "$APP_DIR" == /* && "$APP_DIR" != "/" && "$APP_DIR" != */ && "$APP_DIR" != *//* ]] ||
    fail "Недопустимый путь установки: $APP_DIR"

APP_PARENT="$(dirname -- "$APP_DIR")"
[[ -d "$APP_PARENT" ]] || fail "Родительский каталог установки не существует: $APP_PARENT"

APP_CURRENT="/"
IFS='/' read -r -a APP_PARENT_PARTS <<< "$APP_PARENT"
for APP_PART in "${APP_PARENT_PARTS[@]}"; do
    [[ -n "$APP_PART" ]] || continue
    [[ "$APP_PART" != "." && "$APP_PART" != ".." ]] ||
        fail "Путь установки содержит недопустимый компонент: $APP_PARENT"
    APP_CURRENT="${APP_CURRENT%/}/$APP_PART"
    [[ ! -L "$APP_CURRENT" ]] ||
        fail "Компонент родительского пути является символической ссылкой: $APP_CURRENT"
    [[ -d "$APP_CURRENT" ]] ||
        fail "Компонент родительского пути не является каталогом: $APP_CURRENT"
done

[[ ! -e "$APP_DIR" && ! -L "$APP_DIR" ]] ||
    fail "Каталог установки уже существует или является ссылкой: $APP_DIR"

shopt -s nullglob
TEMPLATES=("$SOURCE_DIR/templates/"*.html)
((${#TEMPLATES[@]} > 0)) || fail "В каталоге templates не найдены HTML-шаблоны."
for template in "${TEMPLATES[@]}"; do
    [[ -f "$template" && ! -L "$template" ]] || fail "Некорректный HTML-шаблон: $template"
done
shopt -u nullglob

info "Подготовка установки в $APP_DIR"

install -d -o root -g root -m 0755 "$APP_DIR"
install -d -o root -g root -m 0755 "$APP_DIR/app"
install -d -o root -g root -m 0755 "$APP_DIR/templates"
install -m 0644 "$SOURCE_DIR/app/panel.py" "$APP_DIR/app/panel.py"
install -m 0644 "$SOURCE_DIR/requirements.txt" "$APP_DIR/requirements.txt"
for template in "${TEMPLATES[@]}"; do
    install -m 0644 "$template" "$APP_DIR/templates/"
done
install -m 0755 "$SOURCE_DIR/installer/run-panel.sh" "$APP_DIR/run-panel.sh"

python3 -m venv "$APP_DIR/.venv" ||
    fail "Не удалось создать виртуальное окружение: $APP_DIR/.venv"

"$APP_DIR/.venv/bin/pip" install --disable-pip-version-check -r "$APP_DIR/requirements.txt" ||
    fail "Не удалось установить Python-зависимости. Каталог приложения сохранён для диагностики."

"$APP_DIR/.venv/bin/python" -c 'import flask, requests, gunicorn' ||
    fail "Проверка установленных Python-зависимостей завершилась ошибкой."

# Python creates a venv with owner-only directory permissions under a restrictive
# umask. The service runs as an unprivileged account, so make installed code
# traversable and readable while keeping write access with root.
chmod -R a+rX "$APP_DIR/.venv"

info "Файлы приложения и зависимости установлены."
info "Создание системного пользователя и службы выполняется отдельными этапами."
