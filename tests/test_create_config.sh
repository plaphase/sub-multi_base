#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_SCRIPT="$PROJECT_ROOT/installer/lib/create-config.sh"

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail "Запусти тесты от root."
[[ -f "$CONFIG_SCRIPT" ]] || fail "Не найден installer/lib/create-config.sh."

TEST_ROOT="$(mktemp -d /tmp/codex-create-config-tests.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

run_config() {
    local output="$1"
    shift
    printf 'codex-test\n' | env "$@" bash "$CONFIG_SCRIPT" >"$output" 2>&1
}

expect_failure() {
    local name="$1"
    shift
    if run_config "$TEST_ROOT/$name.log" "$@"; then
        fail "$name: ожидалась ошибка, но скрипт завершился успешно."
    fi
}

VALID_DIR="$TEST_ROOT/valid/config"
if ! run_config "$TEST_ROOT/valid.log" \
    "CONFIG_DIR=$VALID_DIR" \
    "APP_DIR=$TEST_ROOT/app" \
    "DATA_DIR=$TEST_ROOT/data" \
    "LOG_DIR=$TEST_ROOT/log" \
    "PANEL_PUBLIC_URL=http://127.0.0.1"; then
    fail "Корректные пути должны приниматься."
fi

CONFIG_FILE="$VALID_DIR/panel.env"
[[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" && -s "$CONFIG_FILE" ]] ||
    fail "Итоговый файл должен быть обычным непустым файлом."
[[ "$(stat -c '%U:%G' -- "$CONFIG_FILE")" == "root:root" ]] ||
    fail "Итоговый файл должен принадлежать root:root."
[[ "$(stat -c '%a' -- "$CONFIG_FILE")" == "600" ]] ||
    fail "Итоговый файл должен иметь права 600."
grep -Fxq 'PANEL_COOKIE_SECURE=false' "$CONFIG_FILE" ||
    fail "Для HTTP установки cookie должна быть помечена как не secure."
grep -Fxq 'PANEL_PUBLIC_URL=http://127.0.0.1' "$CONFIG_FILE" ||
    fail "Публичный URL не записан в конфигурацию."
[[ -z "$(find "$VALID_DIR" -mindepth 1 -maxdepth 1 -name '.panel.env.*' -print -quit)" ]] ||
    fail "Временный файл остался после успешного завершения."
printf '[OK] Корректные пути и права итогового файла.\n'

SPACE_DIR="$TEST_ROOT/invalid path/config"
expect_failure spaces \
    "CONFIG_DIR=$SPACE_DIR" \
    "APP_DIR=$TEST_ROOT/app" \
    "DATA_DIR=$TEST_ROOT/data" \
    "LOG_DIR=$TEST_ROOT/log"
[[ ! -e "$TEST_ROOT/invalid path" ]] || fail "Путь с пробелом создал каталог."
printf '[OK] Путь с пробелом отклонён.\n'

expect_failure invalid_symbol \
    "CONFIG_DIR=$TEST_ROOT/config" \
    "APP_DIR=$TEST_ROOT/app;invalid" \
    "DATA_DIR=$TEST_ROOT/data" \
    "LOG_DIR=$TEST_ROOT/log"
[[ ! -e "$TEST_ROOT/config" ]] || fail "Недопустимый символ создал каталог."
printf '[OK] Недопустимый символ отклонён.\n'

mkdir -p -- "$TEST_ROOT/real-config"
ln -s -- "$TEST_ROOT/real-config" "$TEST_ROOT/config-link"
expect_failure symlink \
    "CONFIG_DIR=$TEST_ROOT/config-link" \
    "APP_DIR=$TEST_ROOT/app" \
    "DATA_DIR=$TEST_ROOT/data" \
    "LOG_DIR=$TEST_ROOT/log"
[[ ! -e "$TEST_ROOT/real-config/panel.env" ]] ||
    fail "Символьная ссылка привела к созданию конфигурации."
printf '[OK] Символьная ссылка в CONFIG_DIR отклонена.\n'

mkdir -m 0750 -- "$TEST_ROOT/existing-config"
printf 'preserve-me\n' > "$TEST_ROOT/existing-config/panel.env"
chmod 0600 "$TEST_ROOT/existing-config/panel.env"
expect_failure existing_file \
    "CONFIG_DIR=$TEST_ROOT/existing-config" \
    "APP_DIR=$TEST_ROOT/app" \
    "DATA_DIR=$TEST_ROOT/data" \
    "LOG_DIR=$TEST_ROOT/log"
[[ "$(cat -- "$TEST_ROOT/existing-config/panel.env")" == "preserve-me" ]] ||
    fail "Существующий panel.env был изменён."
printf '[OK] Существующий panel.env сохранён без изменений.\n'

printf '[OK] Все тесты create-config.sh пройдены.\n'
