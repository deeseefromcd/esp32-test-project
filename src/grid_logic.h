/*
  Чистая логика сетки герконов: адресация клеток, разбор прочитанных бит,
  антидребезг, вычисление изменений и отрисовка поля.

  Здесь нет Arduino.h и нет обращений к железу: на входе числа и массивы,
  на выходе тоже. Поэтому модуль собирается и проверяется на хосте
  ([env:native], make test) — без платы и без токена Wokwi. Это единственная
  проверка поведения, которую можно прогнать локально.
*/
#pragma once

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

// Сколько клеток занято — для сводки в serial: по числу видно, что схема
// прочитала ровно столько фигур, сколько поставлено, без лишних клеток.
inline int countClosed(const bool cells[kCells]) {
  int count = 0;
  for (int i = 0; i < kCells; ++i) {
    if (cells[i]) {
      ++count;
    }
  }
  return count;
}

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
