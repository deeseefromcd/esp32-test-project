# Makefile для esp32-test-project (PlatformIO + Wokwi)
#
#   make build   — собрать прошивку (pio run)
#   make clean   — очистить сборку
#   make size    — показать размер прошивки
#   make flash   — прошить подключённую плату (pio run -t upload)
#   make sim     — подсказка, как запустить симулятор Wokwi
#
#   make lint    — все быстрые локальные проверки (cppcheck, схема, YAML, actionlint)
#   make check   — lint + сборка (то, что прогоняет агент при правке)
#
# PIO по умолчанию берётся из venv (на этой машине brew-версия сломана Python 3.15).
# Переопределить: make build PIO=/opt/homebrew/bin/pio

PIO ?= $(HOME)/.platformio-venv/bin/pio
ENV ?= esp32-s3-devkitc-1
WOKWI_CLI ?= $(HOME)/.local/bin/wokwi-cli
ACTIONLINT ?= actionlint

.PHONY: help build clean size flash sim lint check lint-cppcheck lint-diagram lint-yaml lint-workflow

help:
	@echo "Доступные цели:"
	@echo "  make build   — собрать прошивку"
	@echo "  make clean   — очистить сборку"
	@echo "  make size    — размер прошивки"
	@echo "  make flash   — прошить плату"
	@echo "  make sim     — как запустить симулятор Wokwi"
	@echo "  make lint    — cppcheck + схема + config.yaml + workflow"
	@echo "  make check   — lint и сборка (быстрая проверка перед коммитом)"
	@echo ""
	@echo "Используемый pio: $(PIO)"
	@echo "Используемое окружение: $(ENV)"

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

lint: lint-cppcheck lint-diagram lint-yaml lint-workflow
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
		|| echo "actionlint не установлен — шаг пропущен (brew install actionlint)"

check: lint build
	@echo ""
	@echo "check: lint и сборка пройдены."
