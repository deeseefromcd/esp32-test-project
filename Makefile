# Makefile для esp32-test-project (PlatformIO + Wokwi)
#
#   make setup   — поставить brew-зависимости (brew bundle)
#   make doctor  — проверить окружение: чего не хватает и как это ставить
#
#   make build   — собрать прошивку (pio run)
#   make clean   — очистить сборку
#   make size    — показать размер прошивки
#   make flash   — прошить подключённую плату (pio run -t upload)
#   make sim     — подсказка, как запустить симулятор Wokwi
#
#   make lint    — все быстрые локальные проверки (cppcheck, схема, config.yaml, workflow)
#   make check   — lint + сборка (то, что прогоняет агент при правке)
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

.PHONY: help setup doctor build clean size flash sim lint check lint-cppcheck lint-diagram lint-yaml lint-workflow lint-deps

help:
	@echo "Доступные цели:"
	@echo "  make setup   — поставить brew-зависимости (brew bundle)"
	@echo "  make doctor  — проверить окружение (чего не хватает)"
	@echo "  make build   — собрать прошивку"
	@echo "  make clean   — очистить сборку"
	@echo "  make size    — размер прошивки"
	@echo "  make flash   — прошить плату"
	@echo "  make sim     — как запустить симулятор Wokwi"
	@echo "  make lint    — cppcheck + схема + config.yaml + workflow + зависимости"
	@echo "  make check   — lint и сборка (быстрая проверка перед коммитом)"
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

lint: lint-cppcheck lint-diagram lint-yaml lint-workflow lint-deps
	@echo ""
	@echo "Все локальные проверки пройдены."

lint-cppcheck:
	@echo "== cppcheck (pio check) =="
	$(PIO) check -e $(ENV) --fail-on-defect medium --skip-packages

lint-diagram:
	@echo "== схема (wokwi-cli lint) =="
	@$(WOKWI_CLI) lint

lint-yaml:
	@echo "== openspec/config.yaml =="
	@ruby scripts/check-openspec-config.rb openspec/config.yaml

lint-workflow:
	@echo "== workflow (actionlint) =="
	@command -v $(ACTIONLINT) >/dev/null 2>&1 \
		&& $(ACTIONLINT) .github/workflows/wokwi.yml \
		|| echo "actionlint не установлен — шаг пропущен (make setup или brew install actionlint)"

lint-deps:
	@echo "== согласованность зависимостей =="
	@bash scripts/check-deps.sh

check: lint build
	@echo ""
	@echo "check: lint и сборка пройдены."