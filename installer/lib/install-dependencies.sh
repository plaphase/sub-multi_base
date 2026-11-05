#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail "Требуются права root."
command -v apt-get >/dev/null 2>&1 || fail "Поддерживается только Ubuntu с apt-get."

printf '[INFO] Обновление списка пакетов APT...\n'
apt-get -o DPkg::Lock::Timeout=60 update

printf '[INFO] Установка системных зависимостей...\n'
DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=60 install -y --no-install-recommends \
    python3-venv nginx curl

python3 -c 'import venv'
command -v nginx >/dev/null 2>&1 || fail "После установки не найдена команда nginx."
command -v curl >/dev/null 2>&1 || fail "После установки не найдена команда curl."

printf '[OK] Системные зависимости установлены.\n'
