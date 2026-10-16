#!/usr/bin/env bash
# Проверяет, что собранный sketch.ino компилируется так же, как его соберёт
# редактор wokwi.com.
#
# Зачем отдельная проверка: `make check` собирает прошивку PlatformIO (src/), а
# скетч — производный файл для веб-редактора, где Arduino-компилятор сам
# вставляет в файл прототипы функций. Из-за этого скетч может не собраться,
# хотя src/ собирается: так и случилось, когда типы объявлялись ниже вставки
# прототипов. Ни сборка проекта, ни native-тесты этого не видят.
#
# Что делает: кладёт sketch.ino во временный проект PlatformIO с той же платой и
# тем же framework, что в platformio.ini проекта, и собирает его. Платформа и
# тулчейн берутся из общего кэша PlatformIO, сеть не нужна.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIO="${PIO:-pio}"
SKETCH="$ROOT/sketch.ino"

[ -f "$SKETCH" ] || { echo "нет $SKETCH — собери его: make sketch" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/src"
cp "$SKETCH" "$TMP/src/sketch.ino"

cat > "$TMP/platformio.ini" <<'INI'
; Временный проект для проверки скетча. Плата и framework — те же, что в
; platformio.ini проекта; отдельный каталог нужен потому, что в редакторе
; wokwi.com скетч компилируется как один файл, а в проекте рядом с ним лежат
; модули src/ (два setup/loop в одной сборке не уживутся).
[env:esp32-s3-devkitc-1]
platform = espressif32
board = esp32-s3-devkitc-1
framework = arduino
INI

cd "$TMP"
"$PIO" run
echo "sketch.ino компилируется Arduino-окружением (проект $(basename "$ROOT"))"
