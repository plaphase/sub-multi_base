#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail 'Запусти команду через sudo.'
command -v curl >/dev/null 2>&1 || fail 'Для загрузки пакета требуется curl.'
command -v tar >/dev/null 2>&1 || fail 'Для распаковки пакета требуется tar.'

INSTALL_ROOT="$(mktemp -d /tmp/multisub-panel-installer.XXXXXX)"
cleanup() {
    rm -rf -- "$INSTALL_ROOT"
}
trap cleanup EXIT

ARCHIVE="$INSTALL_ROOT/source.tar.gz"
SOURCE_DIR="$INSTALL_ROOT/source"
ARCHIVE_URL="https://github.com/plaphase/sub-multi_base/archive/refs/heads/main.tar.gz"

printf '[INFO] Загружаю MultiSub Panel…\n'
curl --fail --location --silent --show-error --retry 3 \
    --output "$ARCHIVE" "$ARCHIVE_URL" || fail 'Не удалось загрузить пакет MultiSub Panel.'
install -d -m 0755 "$SOURCE_DIR"
tar --extract --gzip --file "$ARCHIVE" --directory "$SOURCE_DIR" --strip-components=1 \
    --no-same-owner --no-same-permissions || fail 'Архив установщика повреждён.'

[[ -f "$SOURCE_DIR/installer/install.sh" && -f "$SOURCE_DIR/installer/preflight.sh" ]] ||
    fail 'В загруженном пакете нет файлов установщика.'

bash "$SOURCE_DIR/installer/install.sh" "$@"
