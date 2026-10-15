# Design

## Context

См. `proposal.md` — Why. Схема `diagram.json` описывает плату
`board-esp32-s3-devkitc-1`, светодиод и резистор. Прошивка печатает в `Serial`
(Arduino, UART0) и переключает GPIO48. Wokwi CI запускает ту же схему и тот же
сценарий, что и локальный симулятор.

## Goals / Non-Goals

**Goals:**
- Вывод `Serial` из прошивки доступен в симуляции и в Wokwi CI.
- Схема остаётся пригодной и для браузерной страницы на wokwi.com.

**Non-Goals:**
- Переход на USB CDC (`USB_SERIAL_JTAG`) вместо UART0.
- Изменение прошивки, сценария или workflow.

## Decisions

**Явные соединения `esp:TX`/`esp:RX`, а не атрибут `serialInterface`.**
У ESP32-S3 два пути serial: UART0 (GPIO43/44) и USB Serial/JTAG. По умолчанию
Arduino-ESP32 для этой платы направляет `Serial` в UART0, поэтому достаточно соединить
выводы `TX`/`RX` платы с `$serialMonitor`.
Альтернатива — перевести симуляцию на USB CDC атрибутом
`serialInterface: USB_SERIAL_JTAG` и убрать соединения. Отклонена: меняет наблюдаемый
контракт, требует правки прошивки и не соответствует поведению по умолчанию, которое
проверяет сценарий.

## Risks / Trade-offs

- [Схема на wokwi.com разойдётся с репозиторием] → после изменения `diagram.json`
  синхронизировать страницу проекта (см. `AGENTS.md`, раздел 2).
- [Порядок соединений влияет на линтер] → `wokwi-cli lint` проходит, кроме
  ожидаемого `[unsupported-part]` (info).