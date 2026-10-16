/*
  Мигание светодиодом как отдельный модуль.

  Здесь только чистая часть — отсчёт времени; запись в пин и печать в serial
  делает main.cpp. Поэтому модуль проверяется на хосте вместе с остальной
  логикой, а не только в симуляции.

  Отсчёт идёт по millis(), а не через delay(): пока delay() выполняется, сетка
  не читается, и реакция на фигуру приходит с задержкой до секунды.
*/
#pragma once

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
