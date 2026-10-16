/*
  Native-тесты чистой логики (make test, окружение native).

  Идут на хосте: без платы, без Arduino.h и без токена Wokwi — поэтому это
  единственная проверка поведения, которую можно прогнать локально. Всё, что
  касается железа и симуляции, проверяется в Wokwi CI.

  Тест закрепляет в том числе порядок бит: он задан схемой (первым читается D7
  последней микросхемы цепочки) и незаметен глазом — отражённая сетка выглядит
  так же правдоподобно.
*/
#include <string.h>

#include <unity.h>

#include "../../src/blink.h"
#include "../../src/grid_logic.h"

void setUp(void) {}
void tearDown(void) {}

// Занятые клетки списком через пробел, в порядке индексов — удобно сравнивать
// целиком, не сверяя шестнадцать элементов по одному.
static const char* occupiedList(const bool cells[grid::kCells], char* out, size_t size) {
  out[0] = '\0';
  for (int i = 0; i < grid::kCells; ++i) {
    if (!cells[i]) {
      continue;
    }
    const grid::Cell c{i / grid::kCols + 1, i % grid::kCols};
    char name[4];
    grid::nameOf(c, name, sizeof(name));
    if (out[0] != '\0') {
      strncat(out, " ", size - strlen(out) - 1);
    }
    strncat(out, name, size - strlen(out) - 1);
  }
  return out;
}

static void assertOccupied(const bool cells[grid::kCells], const char* expected) {
  char buf[grid::kCells * 4];
  TEST_ASSERT_EQUAL_STRING(expected, occupiedList(cells, buf, sizeof(buf)));
}

// --- Клетки и порядок бит --------------------------------------------------

void test_names_cover_corner_cells(void) {
  char name[4];
  grid::nameOf(grid::Cell{1, 0}, name, sizeof(name));
  TEST_ASSERT_EQUAL_STRING("A1", name);
  grid::nameOf(grid::Cell{1, 3}, name, sizeof(name));
  TEST_ASSERT_EQUAL_STRING("D1", name);
  grid::nameOf(grid::Cell{4, 0}, name, sizeof(name));
  TEST_ASSERT_EQUAL_STRING("A4", name);
  grid::nameOf(grid::Cell{4, 3}, name, sizeof(name));
  TEST_ASSERT_EQUAL_STRING("D4", name);
}

void test_first_read_bit_is_last_cell(void) {
  // Первым читается D7 последней микросхемы цепочки, а это дальний угол поля.
  bool cells[grid::kCells];
  grid::rawToCells(0x8000, cells);
  assertOccupied(cells, "D4");
}

void test_read_order_goes_bottom_up_right_to_left(void) {
  // Микросхемы связаны цепочкой, поэтому порядок чтения — сверху вниз и
  // справа налево. Именно это и закрепляет тест: «как получилось» не сойдёт.
  struct Case {
    uint16_t raw;
    const char* cell;
  };
  const Case cases[] = {
      {0x8000, "D4"}, {0x4000, "C4"}, {0x2000, "B4"}, {0x1000, "A4"},
      {0x0800, "D3"}, {0x0100, "A3"}, {0x0080, "D2"}, {0x0010, "A2"},
      {0x0008, "D1"}, {0x0004, "C1"}, {0x0002, "B1"}, {0x0001, "A1"},
  };
  for (const Case& c : cases) {
    bool cells[grid::kCells];
    grid::rawToCells(c.raw, cells);
    assertOccupied(cells, c.cell);
  }
}

void test_several_cells_at_once(void) {
  // Несколько фигур на поле: две крайние клетки и одна внутри (C2 — это бит 6).
  bool cells[grid::kCells];
  grid::rawToCells(static_cast<uint16_t>(0x8001 | 0x0040), cells);
  assertOccupied(cells, "A1 C2 D4");
}

void test_all_cells_can_be_occupied(void) {
  // Поле заполнено целиком: ни одна клетка не теряется и не дублируется.
  bool cells[grid::kCells];
  grid::rawToCells(0xFFFF, cells);
  assertOccupied(cells,
                 "A1 B1 C1 D1 A2 B2 C2 D2 A3 B3 C3 D3 A4 B4 C4 D4");
}

void test_empty_grid(void) {
  bool cells[grid::kCells];
  grid::rawToCells(0x0000, cells);
  assertOccupied(cells, "");
}

// --- Антидребезг -----------------------------------------------------------

void test_debounce_waits_for_stable_window(void) {
  grid::Debounce d;
  grid::debounceInit(d);
  bool raw[grid::kCells] = {};
  bool stable[grid::kCells];
  const uint32_t window = 20;

  grid::debounceUpdate(d, raw, 1000, window, stable);
  TEST_ASSERT_FALSE(stable[0]);

  raw[0] = true;
  grid::debounceUpdate(d, raw, 1001, window, stable);  // момент замыкания
  TEST_ASSERT_FALSE(stable[0]);                        // рано: окно не прошло

  grid::debounceUpdate(d, raw, 1001 + window - 1, window, stable);
  TEST_ASSERT_FALSE(stable[0]);

  grid::debounceUpdate(d, raw, 1001 + window, window, stable);
  TEST_ASSERT_TRUE(stable[0]);  // продержалось окно — принято
}

void test_debounce_swallows_bouncing(void) {
  grid::Debounce d;
  grid::debounceInit(d);
  bool raw[grid::kCells] = {};
  bool stable[grid::kCells];
  const uint32_t window = 20;

  // Контакт дребезжит: десять переключений за десять миллисекунд.
  for (int i = 0; i < 10; ++i) {
    raw[0] = (i % 2 == 0);
    grid::debounceUpdate(d, raw, static_cast<uint32_t>(2000 + i), window, stable);
    TEST_ASSERT_FALSE(stable[0]);
  }

  raw[0] = true;
  grid::debounceUpdate(d, raw, 2009, window, stable);
  TEST_ASSERT_FALSE(stable[0]);
  grid::debounceUpdate(d, raw, 2009 + window, window, stable);
  TEST_ASSERT_TRUE(stable[0]);  // серия дребезга дала одно событие
}

void test_debounce_reports_release(void) {
  grid::Debounce d;
  grid::debounceInit(d);
  bool raw[grid::kCells] = {};
  bool stable[grid::kCells];
  const uint32_t window = 20;

  raw[0] = true;
  grid::debounceUpdate(d, raw, 1000, window, stable);
  grid::debounceUpdate(d, raw, 1000 + window, window, stable);
  TEST_ASSERT_TRUE(stable[0]);

  raw[0] = false;
  grid::debounceUpdate(d, raw, 1100, window, stable);
  TEST_ASSERT_TRUE(stable[0]);  // магнит убрали, но окно ещё не прошло
  grid::debounceUpdate(d, raw, 1100 + window, window, stable);
  TEST_ASSERT_FALSE(stable[0]);
}

void test_debounce_keeps_cells_independent(void) {
  grid::Debounce d;
  grid::debounceInit(d);
  bool raw[grid::kCells] = {};
  bool stable[grid::kCells];
  const uint32_t window = 20;

  raw[grid::indexOf(grid::Cell{1, 0})] = true;  // A1
  raw[grid::indexOf(grid::Cell{2, 1})] = true;  // B2
  grid::debounceUpdate(d, raw, 1000, window, stable);
  grid::debounceUpdate(d, raw, 1000 + window, window, stable);
  bool expected[grid::kCells] = {};
  expected[grid::indexOf(grid::Cell{1, 0})] = true;
  expected[grid::indexOf(grid::Cell{2, 1})] = true;
  TEST_ASSERT_EQUAL_MEMORY(expected, stable, sizeof(expected));
}

// --- Изменения и отрисовка -------------------------------------------------

void test_diff_reports_closed_and_opened(void) {
  bool prev[grid::kCells] = {};
  bool now[grid::kCells] = {};
  now[grid::indexOf(grid::Cell{1, 0})] = true;  // A1 замкнулась
  now[grid::indexOf(grid::Cell{2, 1})] = true;  // B2 замкнулась
  prev[grid::indexOf(grid::Cell{1, 3})] = true;  // D1 разомкнулась

  const grid::Changes ch = grid::diff(prev, now);
  TEST_ASSERT_EQUAL_UINT16(static_cast<uint16_t>((1u << 0) | (1u << 5)), ch.closed);
  TEST_ASSERT_EQUAL_UINT16(static_cast<uint16_t>(1u << 3), ch.opened);
}

void test_diff_of_equal_states_is_empty(void) {
  bool cells[grid::kCells] = {};
  cells[7] = true;
  const grid::Changes ch = grid::diff(cells, cells);
  TEST_ASSERT_EQUAL_UINT16(0, ch.closed);
  TEST_ASSERT_EQUAL_UINT16(0, ch.opened);
}

void test_render_field_marks_occupied_cells(void) {
  bool cells[grid::kCells] = {};
  cells[grid::indexOf(grid::Cell{1, 0})] = true;  // A1
  cells[grid::indexOf(grid::Cell{4, 3})] = true;  // D4
  char buf[128];
  grid::renderField(cells, buf, sizeof(buf));
  TEST_ASSERT_EQUAL_STRING(
      "  A B C D\n"
      "1 X . . .\n"
      "2 . . . .\n"
      "3 . . . .\n"
      "4 . . . X\n",
      buf);
}

void test_render_field_of_empty_grid(void) {
  bool cells[grid::kCells] = {};
  char buf[128];
  grid::renderField(cells, buf, sizeof(buf));
  TEST_ASSERT_EQUAL_STRING(
      "  A B C D\n"
      "1 . . . .\n"
      "2 . . . .\n"
      "3 . . . .\n"
      "4 . . . .\n",
      buf);
}

void test_render_field_survives_small_buffer(void) {
  // Урезанный буфер не должен приводить к выходу за границу или мусору.
  bool cells[grid::kCells] = {};
  cells[0] = true;
  char buf[8];
  grid::renderField(cells, buf, sizeof(buf));
  TEST_ASSERT_EQUAL_size_t(strlen(buf), 7);
  TEST_ASSERT_EQUAL_CHAR('\0', buf[7]);
}

// --- Мигание ---------------------------------------------------------------

void test_blink_toggles_every_half_period(void) {
  blink::State s;
  blink::init(s, 0);
  TEST_ASSERT_FALSE(s.on);

  TEST_ASSERT_FALSE(blink::update(s, 999, 1000));
  TEST_ASSERT_FALSE(s.on);

  TEST_ASSERT_TRUE(blink::update(s, 1000, 1000));
  TEST_ASSERT_TRUE(s.on);

  TEST_ASSERT_FALSE(blink::update(s, 1500, 1000));
  TEST_ASSERT_TRUE(blink::update(s, 2000, 1000));
  TEST_ASSERT_FALSE(s.on);
}

void test_blink_ignores_zero_period(void) {
  blink::State s;
  blink::init(s, 0);
  TEST_ASSERT_FALSE(blink::update(s, 5000, 0));
  TEST_ASSERT_FALSE(s.on);
}

int main(int argc, char** argv) {
  (void)argc;
  (void)argv;
  UNITY_BEGIN();
  RUN_TEST(test_names_cover_corner_cells);
  RUN_TEST(test_first_read_bit_is_last_cell);
  RUN_TEST(test_read_order_goes_bottom_up_right_to_left);
  RUN_TEST(test_several_cells_at_once);
  RUN_TEST(test_all_cells_can_be_occupied);
  RUN_TEST(test_empty_grid);
  RUN_TEST(test_debounce_waits_for_stable_window);
  RUN_TEST(test_debounce_swallows_bouncing);
  RUN_TEST(test_debounce_reports_release);
  RUN_TEST(test_debounce_keeps_cells_independent);
  RUN_TEST(test_diff_reports_closed_and_opened);
  RUN_TEST(test_diff_of_equal_states_is_empty);
  RUN_TEST(test_render_field_marks_occupied_cells);
  RUN_TEST(test_render_field_of_empty_grid);
  RUN_TEST(test_render_field_survives_small_buffer);
  RUN_TEST(test_blink_toggles_every_half_period);
  RUN_TEST(test_blink_ignores_zero_period);
  return UNITY_END();
}
