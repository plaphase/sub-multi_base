#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_USER="${SERVICE_USER:-multisub-panel}"
SERVICE_GROUP="${SERVICE_GROUP:-$SERVICE_USER}"

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail "Требуются права root."

[[ "$SERVICE_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] ||
    fail "Недопустимое имя пользователя: $SERVICE_USER"

[[ "$SERVICE_GROUP" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] ||
    fail "Недопустимое имя группы: $SERVICE_GROUP"

if getent passwd "$SERVICE_USER" >/dev/null 2>&1; then
    fail "Пользователь уже существует: $SERVICE_USER"
fi

if getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
    fail "Группа уже существует: $SERVICE_GROUP"
fi

groupadd --system "$SERVICE_GROUP"
useradd --system \
    --gid "$SERVICE_GROUP" \
    --no-create-home \
    --home-dir /nonexistent \
    --shell /usr/sbin/nologin \
    "$SERVICE_USER"

id "$SERVICE_USER"
printf '[OK] Созданы системные пользователь и группа.\n'
