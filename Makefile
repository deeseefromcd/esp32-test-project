# Makefile для esp32-test-project (PlatformIO + Wokwi)
#
#   make setup   — поставить brew-зависимости (brew bundle)
#   make doctor  — проверить окружение: чего не хватает и как это ставить
#
#   make build   — собрать прошивку (pio run)
#   make test    — прогнать native-тесты чистой логики (pio test -e native)
#   make sketch  — пересобрать sketch.ino из src/ для wokwi.com
#   make diagram — собрать diagram.json из описания схемы
#   make diagram-capture — снять посадку и разводку из diagram.json в layout.json
#   make clean   — очистить сборку
#   make size    — показать размер прошивки
#   make flash   — прошить подключённую плату (pio run -t upload)
#   make sim     — подсказка, как запустить симулятор Wokwi
#
#   make lint    — все быстрые локальные проверки (cppcheck, схема, config.yaml, workflow, sketch.ino)
#   make check   — lint + тесты + сборка (то, что прогоняет агент при правке)
#
# Пути к инструментам определяются автоматически, чтобы Makefile работал и на
# других машинах. Переопределить можно из окружения или аргументом:
#   make build PIO=/opt/homebrew/bin/pio

# pio: приоритет у venv (на машине автора brew-версия сломана Python 3.15,
# см. AGENTS.md §4.6), иначе — из PATH. Пустая или незаданная переменная —
# считается незаданной (иначе `PIO=` из окружения даёт битую команду).
ifeq ($(strip $(PIO)),)
  PIO := $(shell if [ -x "$(HOME)/.platformio-venv/bin/pio" ]; then echo "$(HOME)/.platformio-venv/bin/pio"; else echo pio; fi)
endif

# wokwi-cli: сначала явный путь установщика Wokwi, потом PATH.
ifeq ($(strip $(WOKWI_CLI)),)
  WOKWI_CLI := $(shell if [ -x "$(HOME)/.local/bin/wokwi-cli" ]; then echo "$(HOME)/.local/bin/wokwi-cli"; else echo wokwi-cli; fi)
endif

ENV ?= esp32-s3-devkitc-1
ACTIONLINT ?= actionlint

.PHONY: help setup doctor build test sketch clean size flash sim lint check lint-cppcheck lint-diagram lint-yaml lint-workflow lint-sketch diagram diagram-capture

help:
	@echo "Доступные цели:"
	@echo "  make setup   — поставить brew-зависимости (brew bundle)"
	@echo "  make doctor  — проверить окружение (чего не хватает)"
	@echo "  make build   — собрать прошивку"
	@echo "  make test    — native-тесты чистой логики"
	@echo "  make sketch  — пересобрать sketch.ino из src/"
	@echo "  make diagram — собрать diagram.json из описания схемы"
	@echo "  make diagram-capture — снять посадку и разводку из diagram.json"
	@echo "  make clean   — очистить сборку"
	@echo "  make size    — размер прошивки"
	@echo "  make flash   — прошить плату"
	@echo "  make sim     — как запустить симулятор Wokwi"
	@echo "  make lint    — cppcheck + схема + config.yaml + workflow + sketch.ino"
	@echo "  make check   — lint, тесты и сборка (быстрая проверка перед коммитом)"
	@echo ""
	@echo "Используемый pio:       $(PIO)"
	@echo "Используемый wokwi-cli: $(WOKWI_CLI)"
	@echo "Используемое окружение: $(ENV)"

# ---- Настройка окружения --------------------------------------------------
#
# make doctor ничего не ставит — только проверяет и подсказывает команды.

doctor:
	@PIO="$(PIO)" WOKWI_CLI="$(WOKWI_CLI)" bash scripts/doctor.sh

setup:
	@command -v brew >/dev/null 2>&1 || { echo "brew не найден — поставь Homebrew: https://brew.sh"; exit 1; }
	brew bundle --file Brewfile
	@echo ""
	@echo "brew-зависимости готовы. Проверь остальное: make doctor"

# ---- Сборка ---------------------------------------------------------------

build:
	$(PIO) run

test:
	@echo "== native-тесты чистой логики =="
	$(PIO) test -e native

sketch:
	@ruby scripts/bundle-sketch.rb

diagram:
	@ruby scripts/gen-diagram.rb

diagram-capture:
	@ruby scripts/gen-diagram.rb --capture

clean:
	$(PIO) run -t clean

size:
	$(PIO) run -t size

flash:
	$(PIO) run -t upload

sim: build
	@echo ""
	@echo "Прошивка собрана: .pio/build/$(ENV)/firmware.bin"
	@echo "Запусти симулятор Wokwi из VS Code:"
	@echo "  1) открой папку проекта в VS Code"
	@echo "  2) нажми F1 -> 'Wokwi: Start Simulator'"

# ---- Проверки -------------------------------------------------------------
#
# Порог cppcheck — medium: на Arduino-скетчах cppcheck даёт ложные low-срабатывания
# ("setup/loop is never used" — их вызывает фреймворк), а medium и выше ловит
# настоящие дефекты.

lint: lint-cppcheck lint-diagram lint-yaml lint-workflow lint-sketch
	@echo ""
	@echo "Все локальные проверки пройдены."

lint-sketch:
	@echo "== sketch.ino (собран из src/) =="
	@ruby scripts/bundle-sketch.rb --check

lint-cppcheck:
	@echo "== cppcheck (pio check) =="
	$(PIO) check -e $(ENV) --fail-on-defect medium --skip-packages

lint-diagram:
	@echo "== схема (актуальность и wokwi-cli lint) =="
	@ruby scripts/gen-diagram.rb --check
	@$(WOKWI_CLI) lint

lint-yaml:
	@echo "== openspec/config.yaml =="
	@ruby scripts/check-openspec-config.rb openspec/config.yaml

lint-workflow:
	@echo "== workflow (actionlint) =="
	@command -v $(ACTIONLINT) >/dev/null 2>&1 \
		&& $(ACTIONLINT) .github/workflows/wokwi.yml \
		|| echo "actionlint не установлен — шаг пропущен (make setup или brew install actionlint)"

check: lint test build
	@echo ""
	@echo "check: lint, тесты и сборка пройдены."