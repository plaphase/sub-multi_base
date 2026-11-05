#!/usr/bin/env bash
set -Eeuo pipefail

# Read-only checks before the installer changes the system.

if [[ "${EUID}" -ne 0 ]]; then
    printf '%s\n' '[ERROR] Запусти проверку от root.' >&2
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

printf '%s\n' '=== Проверка совместимости системы ==='
bash "$SCRIPT_DIR/check-dependencies.sh"

printf '\n%s\n' '=== Проверка каталога данных ==='
if [[ -n "${MULTISUB_DATA_DIR:-}" ]]; then
    [[ -d "$MULTISUB_DATA_DIR" ]] || {
        printf '[ERROR] Каталог данных не существует: %s\n' "$MULTISUB_DATA_DIR" >&2
        exit 1
    }
    printf '[INFO] Каталог данных существует: %s\n' "$MULTISUB_DATA_DIR"
else
    printf '%s\n' '[INFO] Каталог данных будет выбран на следующем этапе.'
fi

printf '\n%s\n' '[INFO] Предварительные проверки пройдены. Изменений в системе не выполнено.'
