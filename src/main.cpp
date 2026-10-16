/*
  Стенд герконовой сетки 4x4 для ESP32-S3-DevKitC-1 (PlatformIO + Wokwi).

  Зачем: проверить связку «геркон + магнит» на макете до того, как она уедет
  в умные шахматы. Герконов в Wokwi нет, поэтому клетка — залипающая кнопка:
  Cmd-клик оставляет её нажатой, поэтому несколько фигур можно поставить
  одновременно, а сценарий CI ставит состояние через set-control.

  Клетки читаются через два 74HC165 в цепочке: каждый вход читается отдельно,
  поэтому фантомных срабатываний (ghosting) не бывает структурно и диоды не
  нужны — в отличие от матричного опроса.

  Модули (все на host-тестах, кроме чтения железа):
    grid_logic.h  — адресация клеток, разбор прочитанных бит, антидребезг,
                    вычисление изменений, отрисовка поля;
    blink.h       — отсчёт мигания светодиода;
    grid_reader.h — чтение цепочки регистров сдвига.

  Схема собирается генератором из описания (tools/diagram/), а не руками:
  diagram.json — производный файл.

  Строки serial (контракт для blink.test.yaml):
    ESP32-S3 reed grid started (GPIO48, 4x4)
    LED ON / LED OFF
    cell A1 closed / cell A1 opened
    поле в виде сетки (шапка A B C D, номера строк, X — занятая клетка)
*/

#include <Arduino.h>

#include "blink.h"
#include "grid_logic.h"
#include "grid_reader.h"

constexpr uint8_t LED_PIN = 48;              // GPIO48 — встроенный светодиод платы
constexpr uint32_t BLINK_DELAY_MS = 1000;    // половина периода: горит и гаснет по секунде
constexpr uint32_t GRID_POLL_MS = 5;         // как часто читаем регистры
constexpr uint32_t GRID_DEBOUNCE_MS = 20;    // окно устойчивости против дребезга контакта

blink::State g_blink;
grid::Debounce g_debounce;
bool g_prev[grid::kCells];                   // состояние, о котором уже сообщили
uint32_t g_lastPollMs = 0;

void printField(const bool cells[grid::kCells]) {
  char buf[128];
  grid::renderField(cells, buf, sizeof(buf));
  Serial.print(buf);
}

// Печатает по строке на каждую изменившуюся клетку и следом — всё поле.
void reportChanges(const grid::Changes& ch, const bool cells[grid::kCells]) {
  if (ch.closed == 0 && ch.opened == 0) {
    return;
  }
  for (int i = 0; i < grid::kCells; ++i) {
    const uint16_t mask = static_cast<uint16_t>(1u << i);
    if ((ch.closed & mask) == 0 && (ch.opened & mask) == 0) {
      continue;
    }
    const grid::Cell c{i / grid::kCols + 1, i % grid::kCols};
    char name[4];
    grid::nameOf(c, name, sizeof(name));
    Serial.print("cell ");
    Serial.print(name);
    Serial.println((ch.closed & mask) != 0 ? " closed" : " opened");
  }
  printField(cells);
}

void setup() {
  Serial.begin(115200);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  blink::init(g_blink, millis());
  grid::debounceInit(g_debounce);
  for (int i = 0; i < grid::kCells; ++i) {
    g_prev[i] = false;
  }
  grid_reader::begin();

  Serial.println("ESP32-S3 reed grid started (GPIO48, 4x4)");
  printField(g_prev);
}

void loop() {
  const uint32_t now = millis();

  if (blink::update(g_blink, now, BLINK_DELAY_MS)) {
    digitalWrite(LED_PIN, g_blink.on ? HIGH : LOW);
    Serial.println(g_blink.on ? "LED ON" : "LED OFF");
  }

  if (now - g_lastPollMs >= GRID_POLL_MS) {
    g_lastPollMs = now;

    bool sampled[grid::kCells];
    bool stable[grid::kCells];
    grid::rawToCells(grid_reader::readRaw(), sampled);
    grid::debounceUpdate(g_debounce, sampled, now, GRID_DEBOUNCE_MS, stable);

    const grid::Changes ch = grid::diff(g_prev, stable);
    for (int i = 0; i < grid::kCells; ++i) {
      g_prev[i] = stable[i];
    }
    reportChanges(ch, stable);
  }

  delay(1);  // не крутить цикл вхолостую — симулятору так легче
}
