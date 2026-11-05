#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INSTALLER_DIR="$PROJECT_ROOT/installer"

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail "Запусти тесты от root на тестовом VPS."
[[ -f "$INSTALLER_DIR/install.sh" ]] || fail "Не найден installer/install.sh."

TEST_ROOT="$(mktemp -d /tmp/codex-installer-flow.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
DRY_RUN_ENV=(
    "APP_DIR=$TEST_ROOT/app"
    "CONFIG_DIR=$TEST_ROOT/config"
    "CONFIG_FILE=$TEST_ROOT/config/panel.env"
    "LOG_DIR=$TEST_ROOT/log"
    "BACKUP_DIR=$TEST_ROOT/backups"
    "SERVICE_USER=codex-installer-flow-$$"
    "SERVICE_GROUP=codex-installer-flow-$$"
)

run_new_mode() {
    local state_file="$TEST_ROOT/new.state"
    local data_dir="/var/lib/codex-installer-flow-$$-new"
    printf '1\n%s\n' "$data_dir" |
        env "${DRY_RUN_ENV[@]}" STATE_FILE="$state_file" PUBLIC_HOST=127.0.0.1 \
        INSTALLER_CONFIRM_HTTP=yes INSTALLER_DRY_RUN=1 \
        bash "$INSTALLER_DIR/install.sh" >"$TEST_ROOT/new.log" 2>&1 || {
            cat "$TEST_ROOT/new.log" >&2
            fail "Режим новой установки должен пройти подготовительные проверки."
        }
    [[ ! -e "$state_file" && ! -L "$state_file" ]] ||
        fail "После dry-run остался файл состояния."
    grep -Fq "[DRY RUN] Каталог данных: $data_dir" "$TEST_ROOT/new.log" ||
        fail "Dry-run не показал выбранный каталог данных."
    [[ ! -e "$data_dir" ]] ||
        fail "Подготовительный этап неожиданно создал каталог данных."
    printf '[OK] Dry-run новой установки проверил состояние без создания данных.\n'
}

run_existing_mode() {
    local state_file="$TEST_ROOT/existing.state"
    local source_dir="$TEST_ROOT/source-data"
    local data_dir="/var/lib/codex-installer-flow-$$-existing"
    mkdir -m 0750 -- "$source_dir"
    printf '{}\n' > "$source_dir/users.json"

    printf '2\n%s\n%s\n' "$source_dir" "$data_dir" |
        env "${DRY_RUN_ENV[@]}" STATE_FILE="$state_file" PUBLIC_HOST=127.0.0.1 \
        INSTALLER_CONFIRM_HTTP=yes INSTALLER_DRY_RUN=1 \
        bash "$INSTALLER_DIR/install.sh" >"$TEST_ROOT/existing.log" 2>&1 || {
            cat "$TEST_ROOT/existing.log" >&2
            fail "Режим существующих данных должен пройти подготовительные проверки."
        }
    [[ ! -e "$state_file" && ! -L "$state_file" ]] ||
        fail "После dry-run остался файл состояния."
    grep -Fq "[DRY RUN] Каталог данных: $data_dir" "$TEST_ROOT/existing.log" ||
        fail "Dry-run не показал выбранный каталог данных."
    [[ ! -e "$data_dir" ]] ||
        fail "Подготовительный этап неожиданно создал каталог копии данных."
    printf '[OK] Dry-run существующих данных проверил состояние без копирования.\n'
}

run_cancel_mode() {
    local state_file="$TEST_ROOT/cancel.state"
    printf '0\n' |
        STATE_FILE="$state_file" bash "$INSTALLER_DIR/install.sh" >"$TEST_ROOT/cancel.log" 2>&1 || {
            cat "$TEST_ROOT/cancel.log" >&2
            fail "Отмена установки должна завершиться штатно."
        }
    [[ ! -e "$state_file" && ! -L "$state_file" ]] ||
        fail "После отмены остался файл состояния."
    printf '[OK] Отмена не оставила файл состояния.\n'
}

run_new_mode
run_existing_mode
run_cancel_mode
printf '[OK] Проверки потока установщика пройдены.\n'
