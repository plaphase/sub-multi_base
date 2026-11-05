#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    exit 1
}

check_absolute_path() {
    local path="$1"
    [[ "$path" == /* && "$path" != "/" && "$path" != */ && "$path" != *//* ]] || return 1

    local current="/"
    local part
    local -a parts
    IFS='/' read -r -a parts <<< "$path"

    for part in "${parts[@]}"; do
        [[ -n "$part" ]] || continue
        [[ "$part" != "." && "$part" != ".." ]] || return 1
        current="${current%/}/$part"
        [[ ! -L "$current" && -d "$current" ]] || return 1
    done
}

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p "$tmp/real/parent"
ln -s "$tmp/real" "$tmp/link"

check_absolute_path "$tmp/real/parent" ||
    fail "Обычный существующий путь должен приниматься."

check_absolute_path "relative/path" &&
    fail "Относительный путь должен отклоняться."

check_absolute_path "$tmp/real/../parent" &&
    fail "Путь с .. должен отклоняться."

check_absolute_path "$tmp/real//parent" &&
    fail "Путь с повторными / должен отклоняться."

check_absolute_path "$tmp/link/parent" &&
    fail "Путь через символическую ссылку должен отклоняться."

check_absolute_path "$tmp/missing/parent" &&
    fail "Путь через отсутствующий каталог должен отклоняться."

check_absolute_path "/" &&
    fail "Корневой каталог должен отклоняться."

check_absolute_path "$tmp/real/parent/" &&
    fail "Путь с завершающим / должен отклоняться."

printf '[OK] Все тесты проверки путей пройдены.\n'
