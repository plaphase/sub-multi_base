#!/usr/bin/env bash
set -Eeuo pipefail
: "${PANEL_PORT:=18082}"
: "${APP_DIR:=/opt/multisub-panel}"
[[ "$PANEL_PORT" =~ ^[0-9]+$ ]] || { echo "[ERROR] PANEL_PORT должен быть числом." >&2; exit 1; }
(( PANEL_PORT >= 1 && PANEL_PORT <= 65535 )) || { echo "[ERROR] PANEL_PORT должен быть в диапазоне 1–65535." >&2; exit 1; }
exec "$APP_DIR/.venv/bin/gunicorn" --workers 2 --bind "127.0.0.1:${PANEL_PORT}" --access-logfile - --error-logfile - --pythonpath "$APP_DIR/app" panel:app
