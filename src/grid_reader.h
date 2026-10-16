/*
  Чтение цепочки регистров сдвига 74HC165: два корпуса, шестнадцать входов.

  Здесь железо, поэтому есть Arduino.h — и нет чистой логики: результат
  отдаётся в виде числа, а разбирает его grid_logic.h (он проверяется на хосте).

  Порядок работы по документации детали:
    PL низкий  — регистры запоминают состояние входов D0..D7;
    PL высокий — состояние выдвигается побитно через Q7 по импульсу CP.
  В цепочке Q7 предыдущего корпуса идёт на DS следующего, PL и CP общие,
  CE притянут к земле.

  Входы притянуты к питанию, поэтому замкнутая клетка читается низким уровнем:
  результат чтения инвертируется, и наружу выходит «карта замкнутых клеток».
*/
#pragma once

#include <Arduino.h>

namespace grid_reader {

constexpr uint8_t kPlPin = 4;  // PL: запомнить состояние входов
constexpr uint8_t kCpPin = 5;  // CP: такт выдвижения
constexpr uint8_t kQ7Pin = 6;  // Q7: последовательный выход последнего корпуса
constexpr int kChips = 2;      // два 74HC165 в цепочке = 16 входов

// ==== склейка: выше объявления, ниже функции ====

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
  // Замкнутая клетка сажает вход на землю, а разомкнутая держится подтяжкой на
  // питании, поэтому занятая клетка читается низким уровнем. Инверсия стоит
  // здесь, на границе с железом: в чистой логике единица означает «замкнуто»,
  // иначе порядок бит в native-тестах читался бы шиворот-навыворот.
  return static_cast<uint16_t>(~value);
}

}  // namespace grid_reader
