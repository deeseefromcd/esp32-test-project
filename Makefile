# Makefile для esp32-test-project (PlatformIO + Wokwi)
#
#   make build   — собрать прошивку (pio run)
#   make clean   — очистить сборку
#   make size    — показать размер прошивки
#   make flash   — прошить подключённую плату (pio run -t upload)
#   make sim     — подсказка, как запустить симулятор Wokwi
#
# PIO по умолчанию берётся из venv (на этой машине brew-версия сломана Python 3.15).
# Переопределить: make build PIO=/opt/homebrew/bin/pio

PIO ?= $(HOME)/.platformio-venv/bin/pio
ENV ?= esp32-s3-devkitc-1

.PHONY: help build clean size flash sim

help:
	@echo "Доступные цели:"
	@echo "  make build   — собрать прошивку"
	@echo "  make clean   — очистить сборку"
	@echo "  make size    — размер прошивки"
	@echo "  make flash   — прошить плату"
	@echo "  make sim     — как запустить симулятор Wokwi"
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