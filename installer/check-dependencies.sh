#!/usr/bin/env bash
set -Eeuo pipefail

log()  { printf '[INFO] %s\n' "$1"; }
fail() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }

if [[ "${EUID}" -ne 0 ]]; then
    fail "Запусти проверку от root: sudo bash installer/check-dependencies.sh"
fi

[[ -r /etc/os-release ]] || fail "Не найден /etc/os-release"
# shellcheck disable=SC1091
source /etc/os-release

[[ "${ID:-}" == "ubuntu" ]] || fail "Поддерживается Ubuntu; обнаружена ОС: ${PRETTY_NAME:-неизвестно}"
[[ "${VERSION_ID:-}" == "24.04" ]] || fail "Поддерживается Ubuntu 24.04; обнаружена версия: ${VERSION_ID:-неизвестно}"

log "ОС: ${PRETTY_NAME}"
log "Проверка системных команд"

missing=()
for cmd in apt-get python3 systemctl systemd-analyze bash install cp tar realpath getent; do
    if command -v "$cmd" >/dev/null 2>&1; then
        printf '[OK] %s: %s\n' "$cmd" "$(command -v "$cmd")"
    else
        printf '[MISSING] %s\n' "$cmd"
        missing+=("$cmd")
    fi
done

if ((${#missing[@]} > 0)); then
    fail "Отсутствуют обязательные системные команды."
fi

python_version="$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
log "Python: ${python_version}"
log "Python venv, Nginx и curl будут установлены установщиком."
log "Проверка обязательных системных команд завершена."
