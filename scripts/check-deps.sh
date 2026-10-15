#!/usr/bin/env bash
# Согласованность декларации зависимостей.
#
# Запуск:  make lint-deps   (входит в make lint)
#
# Инвариант: каждый brew-пакет из Brewfile обязан быть зарегистрирован
#   (а) в scripts/doctor.sh — как require/optional, чтобы make doctor о нём сообщал;
#   (б) в README.md — чтобы коллега видел, зачем он нужен.
#
# Обратное неверно: в doctor есть инструменты, которые ставятся не через brew
# (pio, wokwi-cli, node, ruby, git, make) — их в Brewfile нет по определению.
# Поэтому проверка односторонняя.

set -u

BREWFILE="Brewfile"
DOCTOR="scripts/doctor.sh"
README="README.md"

for f in "$BREWFILE" "$DOCTOR" "$README"; do
  if [ ! -f "$f" ]; then
    echo "check-deps: нет файла $f (запускай из корня проекта)"
    exit 1
  fi
done

# brew-имена из Brewfile: brew "actionlint"
pkgs=$(grep -oE '^[[:space:]]*brew[[:space:]]+"[^"]+"' "$BREWFILE" \
  | sed -E 's/.*"([^"]+)".*/\1/' | sort -u)

if [ -z "$pkgs" ]; then
  echo "check-deps: в $BREWFILE нет brew-пакетов — проверять нечего"
  exit 0
fi

problems=0
count=0

while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  count=$((count + 1))

  # (а) зарегистрирован в doctor.sh
  if ! grep -qE "^[[:space:]]*(require|optional)[[:space:]]+\"$pkg\"" "$DOCTOR"; then
    echo "check-deps: «${pkg}» из $BREWFILE не проверяется в $DOCTOR"
    echo "            добавь: require/optional \"$pkg\" ..."
    problems=$((problems + 1))
  fi

  # (б) упомянут в README
  if ! grep -q "\`$pkg\`" "$README"; then
    echo "check-deps: «${pkg}» из $BREWFILE не упомянут в $README"
    echo "            добавь строку в таблицу «Кто чем проверяется»"
    problems=$((problems + 1))
  fi
done <<< "$pkgs"

if [ "$problems" -eq 0 ]; then
  echo "check-deps: $count brew-пакет(ов) согласованы (Brewfile ↔ doctor.sh ↔ README)"
  exit 0
fi

echo ""
echo "check-deps: проблем — $problems. Незарегистрированный инструмент на чужой машине не появится."
exit 1

