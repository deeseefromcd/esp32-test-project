#!/usr/bin/env bash
# Проверка окружения для разработки: чего не хватает на этой машине
# и какой командой это ставить.
#
# Запуск:  make doctor          (или напрямую: bash scripts/doctor.sh)
#
# Это и есть документация по зависимостям: список инструментов, их версии
# и команды установки живут здесь и в Brewfile, а не дублируются прозой
# в README. Скрипт ничего не устанавливает — только сообщает.
#
# Инструменты ищутся в PATH и в известных местах установки (~/bin, ~/.local/bin),
# потому что домашние каталоги bin часто не попадают в PATH неинтерактивных
# оболочек (например, когда doctor запущен из make).

set -u

# --- вывод ------------------------------------------------------------------
if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
else
  B=''; DIM=''; RED=''; GRN=''; YEL=''; RST=''
fi

ok_count=0
miss_required=0
miss_optional=0

# resolve <имя-команды> [подсказка-путь]
# Печатает полный путь к исполняемому файлу или пустую строку.
# Порядок: подсказка (env/аргумент) → PATH → ~/bin → ~/.local/bin.
resolve() {
  local name="$1" hint="${2:-}"
  if [ -n "$hint" ]; then
    if [ -x "$hint" ]; then printf '%s' "$hint"; return 0; fi
    if command -v "$hint" >/dev/null 2>&1; then command -v "$hint"; return 0; fi
    return 1
  fi
  local found
  if found=$(command -v "$name" 2>/dev/null); then printf '%s' "$found"; return 0; fi
  local d
  for d in "$HOME/bin" "$HOME/.local/bin"; do
    if [ -x "$d/$name" ]; then printf '%s' "$d/$name"; return 0; fi
  done
  return 1
}

# require <имя> <подсказка-путь> <команда версии> <как ставить>
# Подсказка может быть пустой. __PATH__ подставляется найденным путём.
require() {
  local name="$1" hint="$2" ver="$3" how="$4" path
  if path=$(resolve "$name" "$hint"); then
    local v; v=$(eval "${ver//__PATH__/$path}" 2>&1 | head -1 | tr -d '\r')
    printf '  %s✓%s %-14s %s%s%s\n' "$GRN" "$RST" "$name" "$DIM" "$v" "$RST"
    ok_count=$((ok_count + 1))
  else
    printf '  %s✗%s %-14s %sНЕ НАЙДЕН%s\n' "$RED" "$RST" "$name" "$RED" "$RST"
    printf '      %sустановка: %s%s\n' "$DIM" "$how" "$RST"
    miss_required=$((miss_required + 1))
  fi
}

echo "${B}Проверка окружения: ESP32-S3 + Wokwi${RST}"
echo

# Подсказки приходят из Makefile (PIO/WOKWI_CLI); при прямом запуске — пусто,
# и тогда работает поиск по PATH и стандартным каталогам.
PIO_HINT="${PIO:-}"
WOKWI_HINT="${WOKWI_CLI:-}"

# --- обязательные: не ставятся через brew, поэтому объявлены явно -----------
echo "${B}Обязательное${RST}"
require "git"       ""            "__PATH__ --version"  "brew install git (на macOS уже есть)"
require "make"      ""            "__PATH__ --version"  "xcode-select --install"
require "ruby"      ""            "__PATH__ -v"         "brew install ruby"
require "node"      ""            "__PATH__ -v"         "brew install node  (нужен для npx/openspec)"
require "pio"       "$PIO_HINT"   "__PATH__ --version"  "brew install platformio  — на части машин brew-версия ломается на новом Python; тогда отдельное venv (README, «Особенность этой машины»)"
require "wokwi-cli" "$WOKWI_HINT" "__PATH__ --version"  "curl -L https://wokwi.com/ci/install.sh | sh"

# --- из Brewfile: единственный источник истины для того, что ставит make setup
# Список не перечисляем вручную — читаем Brewfile. Добавил пакет в Brewfile →
# make setup его поставит, а make doctor о нём сообщит. Двух мест уже нет.
echo
echo "${B}Из Brewfile (ставит make setup)${RST}"
if [ -f Brewfile ]; then
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    if path=$(resolve "$pkg" ""); then
      v=$( "$path" --version 2>&1 | head -1 | tr -d '\r' )
      printf '  %s✓%s %-14s %s%s%s\n' "$GRN" "$RST" "$pkg" "$DIM" "$v" "$RST"
      ok_count=$((ok_count + 1))
    else
      printf '  %s·%s %-14s %sне найден — поставь: make setup%s\n' "$YEL" "$RST" "$pkg" "$YEL" "$RST"
      miss_optional=$((miss_optional + 1))
    fi
  done < <(grep -oE '^[[:space:]]*brew[[:space:]]+"[^"]+"' Brewfile | sed -E 's/.*"([^"]+)".*/\1/' | sort -u)
else
  printf '  %s·%s Brewfile не найден — запускай make doctor из корня проекта\n' "$YEL" "$RST"
fi

echo
echo "${B}Итог${RST}"
if [ "$miss_required" -eq 0 ]; then
  printf '  обязательные инструменты на месте (%s)\n' "$ok_count"
else
  printf '  %sне хватает обязательных: %s%s\n' "$RED" "$miss_required" "$RST"
fi
[ "$miss_optional" -gt 0 ] && printf '  %sне хватает из Brewfile: %s — поставь: make setup%s\n' "$YEL" "$miss_optional" "$RST"

# --- контекст, который стоит знать ------------------------------------------
echo
echo "${B}Что важно знать${RST}"

PIO_PATH=$(resolve "pio" "$PIO_HINT" || true)
WOKWI_PATH=$(resolve "wokwi-cli" "$WOKWI_HINT" || true)

printf '  %s·%s pio:        %s\n' "$DIM" "$RST" "${PIO_PATH:-не найден}"

# Подсказка про venv-обход: только если выбран именно venv-путь.
if [ -n "$PIO_PATH" ] && [ "$PIO_PATH" = "$HOME/.platformio-venv/bin/pio" ]; then
  printf '      %sвзят venv-путь: обход сломанного brew-pio (см. AGENTS.md §4.6)%s\n' "$YEL" "$RST"
fi

# wokwi-cli найден там, где его нет в PATH → говорим прямо, иначе make lint-diagram
# упадёт с «command not found», хотя инструмент установлен.
if [ -n "$WOKWI_PATH" ]; then
  printf '  %s·%s wokwi-cli:  %s\n' "$DIM" "$RST" "$WOKWI_PATH"
  if ! command -v wokwi-cli >/dev/null 2>&1; then
    printf '      %sне в PATH — make находит его сам, но в терминале может понадобиться:%s\n' "$YEL" "$RST"
    # $PATH здесь литерал: печатаем готовую команду для копирования, а не её значение.
    # shellcheck disable=SC2016
    printf '      %sexport PATH="%s:$PATH"%s\n' "$DIM" "$(dirname "$WOKWI_PATH")" "$RST"
  fi
else
  printf '  %s·%s wokwi-cli:  не найден\n' "$DIM" "$RST"
fi

# Токен: проверяем факт наличия, значение не печатаем.
if [ -n "${WOKWI_CLI_TOKEN:-}" ]; then
  printf '  %s✓%s WOKWI_CLI_TOKEN задан — можно гонять симуляцию локально\n' "$GRN" "$RST"
else
  printf '  %s·%s WOKWI_CLI_TOKEN не задан — симуляцию локально не прогнать.\n' "$YEL" "$RST"
  printf '      %sПоведение проверяет Wokwi CI по push. Секрет намеренно не лежит на диске.%s\n' "$DIM" "$RST"
fi

# Первый build тянет платформу — предупреждаем заранее.
if [ -d "$HOME/.platformio/packages/framework-arduinoespressif32" ]; then
  printf '  %s✓%s платформа espressif32 уже скачана (первый make build не будет долгим)\n' "$GRN" "$RST"
else
  printf '  %s·%s платформа espressif32 ещё не скачана — первый make build займёт время\n' "$YEL" "$RST"
  printf '      %sи потребует сети (несколько сотен МБ)%s\n' "$DIM" "$RST"
fi

echo
if [ "$miss_required" -eq 0 ]; then
  printf '%sОкружение готово.%s Дальше: %smake help%s  (команды) · %smake check%s  (lint и сборка)\n' \
    "$GRN" "$RST" "$B" "$RST" "$B" "$RST"
  exit 0
fi

printf '%sОкружение не готово:%s поставь недостающее выше и повтори %smake doctor%s\n' \
  "$RED" "$RST" "$B" "$RST"
exit 1