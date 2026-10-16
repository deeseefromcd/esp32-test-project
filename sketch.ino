/*
  ВНИМАНИЕ: файл собран из src/ — правки здесь будут затёрты.

  Сборка: make sketch  (scripts/bundle-sketch.rb)

  Нужен для wokwi.com: в веб-редакторе нет загрузки файлов, поэтому прошивка
  попадает туда одним файлом. Источник — src/ в репозитории.
*/

// ==== src/grid_logic.h ====
/*
  Чистая логика сетки герконов: адресация клеток, разбор прочитанных бит,
  антидребезг, вычисление изменений и отрисовка поля.

  Здесь нет Arduino.h и нет обращений к железу: на входе числа и массивы,
  на выходе тоже. Поэтому модуль собирается и проверяется на хосте
  ([env:native], make test) — без платы и без токена Wokwi. Это единственная
  проверка поведения, которую можно прогнать локально.
*/

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

namespace grid {

constexpr int kRows = 4;                 // строки 1..4
constexpr int kCols = 4;                 // столбцы A..D
constexpr int kCells = kRows * kCols;    // 16 клеток
constexpr int kBits = kCells;            // 16 бит выдвигаются из двух 74HC165

struct Cell {
  int row;  // 1..4
  int col;  // 0..3, то есть A..D
};

inline int indexOf(Cell c) { return (c.row - 1) * kCols + c.col; }

// Клетка по номеру прочитанного бита.
//
// Порядок бит задан схемой, а не удобством: микросхемы соединены в цепочку,
// поэтому первым читается бит D7 ПОСЛЕДНЕЙ микросхемы. Если считать биты «как
// получилось», клетки окажутся отражены по обеим осям — и это не видно глазом,
// поэтому порядок закреплён тестом (test/test_grid).
inline Cell cellFromReadIndex(int i) {
  return Cell{4 - i / 4, 3 - i % 4};
}

// raw — значение, как его собирает чтение: первый прочитанный бит становится
// старшим (value = (value << 1) | bit).
inline void rawToCells(uint16_t raw, bool cells[kCells]) {
  for (int i = 0; i < kCells; ++i) {
    cells[i] = false;
  }
  for (int i = 0; i < kBits; ++i) {
    const bool bit = ((raw >> (kBits - 1 - i)) & 1u) != 0;
    if (bit) {
      cells[indexOf(cellFromReadIndex(i))] = true;
    }
  }
}

// "A1".."D4": столбец буквой, строка цифрой — как на доске.
inline void nameOf(Cell c, char* out, size_t size) {
  snprintf(out, size, "%c%c", 'A' + c.col, '1' + (c.row - 1));
}

// Дребезг контакта: при замыкании геркон (и кнопка) замыкается и размыкается
// десятки раз за миллисекунды. Поэтому новое состояние принимается только
// после того, как продержалось windowMs — тогда серия даёт одно событие.
struct Debounce {
  bool stable[kCells];
  bool candidate[kCells];
  uint32_t sinceMs[kCells];
};

inline void debounceInit(Debounce& d) {
  for (int i = 0; i < kCells; ++i) {
    d.stable[i] = false;
    d.candidate[i] = false;
    d.sinceMs[i] = 0;
  }
}

// Обновляет состояние и складывает в stableOut то, что считается устойчивым.
inline void debounceUpdate(Debounce& d, const bool raw[kCells], uint32_t nowMs,
                           uint32_t windowMs, bool stableOut[kCells]) {
  for (int i = 0; i < kCells; ++i) {
    if (raw[i] == d.stable[i]) {
      d.candidate[i] = raw[i];
    } else if (raw[i] != d.candidate[i]) {
      d.candidate[i] = raw[i];
      d.sinceMs[i] = nowMs;
    } else if (nowMs - d.sinceMs[i] >= windowMs) {
      d.stable[i] = d.candidate[i];
    }
    stableOut[i] = d.stable[i];
  }
}

// Что изменилось между двумя проходами: бит i — клетка с индексом i.
struct Changes {
  uint16_t closed;
  uint16_t opened;
};

inline Changes diff(const bool prev[kCells], const bool now[kCells]) {
  Changes ch{0, 0};
  for (int i = 0; i < kCells; ++i) {
    if (prev[i] == now[i]) {
      continue;
    }
    if (now[i]) {
      ch.closed |= static_cast<uint16_t>(1u << i);
    } else {
      ch.opened |= static_cast<uint16_t>(1u << i);
    }
  }
  return ch;
}

// Поле в виде сетки: шапка столбцов, номера строк, занятая клетка 'X',
// свободная '.'. Нужно, чтобы состояние доски читалось целиком, а не по числам.
inline void renderField(const bool cells[kCells], char* out, size_t size) {
  if (size == 0) {
    return;
  }
  size_t used = 0;
  const auto put = [&](char ch) {
    if (used + 1 < size) {
      out[used++] = ch;
    }
  };
  for (const char* s = "  A B C D\n"; *s != '\0'; ++s) {
    put(*s);
  }
  for (int r = 0; r < kRows; ++r) {
    put(static_cast<char>('1' + r));
    put(' ');
    for (int c = 0; c < kCols; ++c) {
      put(cells[r * kCols + c] ? 'X' : '.');
      if (c + 1 < kCols) {
        put(' ');
      }
    }
    put('\n');
  }
  out[used] = '\0';
}

}  // namespace grid

// ==== src/blink.h ====
/*
  Мигание светодиодом как отдельный модуль.

  Здесь только чистая часть — отсчёт времени; запись в пин и печать в serial
  делает main.cpp. Поэтому модуль проверяется на хосте вместе с остальной
  логикой, а не только в симуляции.

  Отсчёт идёт по millis(), а не через delay(): пока delay() выполняется, сетка
  не читается, и реакция на фигуру приходит с задержкой до секунды.
*/

#include <stdint.h>

namespace blink {

struct State {
  bool on;
  uint32_t sinceMs;
};

inline void init(State& s, uint32_t nowMs) {
  s.on = false;
  s.sinceMs = nowMs;
}

// Переключает состояние каждые halfPeriodMs и возвращает true в момент
// переключения — тогда main.cpp обновляет пин и печатает строку.
inline bool update(State& s, uint32_t nowMs, uint32_t halfPeriodMs) {
  if (halfPeriodMs == 0) {
    return false;
  }
  if (nowMs - s.sinceMs < halfPeriodMs) {
    return false;
  }
  s.sinceMs = nowMs;
  s.on = !s.on;
  return true;
}

}  // namespace blink

// ==== src/grid_reader.h ====
/*
  Чтение цепочки регистров сдвига 74HC165: два корпуса, шестнадцать входов.

  Здесь железо, поэтому есть Arduino.h — и нет чистой логики: результат
  отдаётся в виде числа, а разбирает его grid_logic.h (он проверяется на хосте).

  Порядок работы по документации детали:
    PL низкий  — регистры запоминают состояние входов D0..D7;
    PL высокий — состояние выдвигается побитно через Q7 по импульсу CP.
  В цепочке Q7 предыдущего корпуса идёт на DS следующего, PL и CP общие,
  CE притянут к земле.
*/

#include <Arduino.h>

namespace grid_reader {

constexpr uint8_t kPlPin = 4;  // PL: запомнить состояние входов
constexpr uint8_t kCpPin = 5;  // CP: такт выдвижения
constexpr uint8_t kQ7Pin = 6;  // Q7: последовательный выход последнего корпуса
constexpr int kChips = 2;      // два 74HC165 в цепочке = 16 входов

inline void begin() {
  pinMode(kPlPin, OUTPUT);
  pinMode(kCpPin, OUTPUT);
  pinMode(kQ7Pin, INPUT);
  digitalWrite(kPlPin, HIGH);
  digitalWrite(kCpPin, LOW);
}

// Запоминает входы и выдвигает 8*kChips бит. Первый прочитанный бит становится
// старшим — так же, как его разбирает grid::rawToCells.
inline uint16_t readRaw() {
  digitalWrite(kPlPin, LOW);   // запомнить состояние входов
  delayMicroseconds(5);
  digitalWrite(kPlPin, HIGH);  // перейти к выдвижению
  delayMicroseconds(5);

  uint16_t value = 0;
  for (int i = 0; i < 8 * kChips; ++i) {
    value = static_cast<uint16_t>((value << 1) | (digitalRead(kQ7Pin) == HIGH ? 1u : 0u));
    digitalWrite(kCpPin, HIGH);
    delayMicroseconds(1);
    digitalWrite(kCpPin, LOW);
    delayMicroseconds(1);
  }
  return value;
}

}  // namespace grid_reader

// ==== src/main.cpp ====
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
