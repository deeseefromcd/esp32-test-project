# esp32-test-project

Первый тестовый проект для [Wokwi](https://wokwi.com) + **PlatformIO**: мигающий светодиод на **ESP32-S3**.

## Что внутри

| Файл | Назначение |
| --- | --- |
| `platformio.ini` | Конфигурация PlatformIO (плата `esp32-s3-devkitc-1`, framework Arduino) |
| `src/main.cpp` | Прошивка: мигает светодиодом на GPIO48 |
| `diagram.json` | Схема для симулятора Wokwi: плата ESP32-S3, светодиод, резистор 220 Ом |
| `wokwi.toml` | Указывает Wokwi, где лежит собранная прошивка (`.pio/build/...`) |
| `Makefile` | Удобные команды: `make build`, `make clean`, `make size`, `make flash`, `make sim` |
| `.gitignore` | Исключает артефакты сборки |

## Схема

```
ESP32-S3 GPIO48 ──► LED (анод) ──► LED (катод) ──► резистор 220 Ом ──► GND
```

GPIO48 выбран потому, что на реальной плате ESP32-S3-DevKitC-1 на нём висит встроенный RGB-светодиод.

## Запуск в VS Code (PlatformIO + Wokwi)

Порядок важен: **Wokwi не компилирует код — он запускает готовую прошивку.**

1. Установить расширение **PlatformIO IDE** в VS Code (даёт кнопку Build и терминал `pio`).
   Альтернатива — `brew install platformio`, тогда команда `pio` доступна в терминале.

2. **Собрать прошивку** (из папки проекта):
   ```sh
   make build      # или: pio run
   ```
   Первый раз PlatformIO скачает платформу `espressif32` и тулчейн (несколько сотен МБ) — это нормально.
   Результат появится в `.pio/build/esp32-s3-devkitc-1/firmware.bin` — именно туда смотрит `wokwi.toml`.

3. В VS Code нажать `F1` → **Wokwi: Start Simulator**.
   Светодиод замигает раз в секунду, в окне Serial Monitor появятся `LED ON` / `LED OFF`.

После каждого изменения кода нужно снова выполнить `pio run`, затем перезапустить симулятор
(при повторном build Wokwi сам подхватывает свежую прошивку).

## Ошибка «firmware binary ... not found in workspace»

Это значит, что шаг 2 (`pio run`) ещё не выполнялся (или путь в `wokwi.toml` не совпал с папкой
`.pio/build/<env>/`). Собери проект и запусти симулятор снова.

## Особенность этой машины (macOS 26 + Python 3.15)

На этом Mac `brew install platformio` подтягивает Python 3.15, в котором `platform.mac_ver()`
возвращает пустую строку. Из-за этого встроенный `pip` падает на установке пакета
`tool-esptoolpy` (`ValueError: invalid literal for int() with base 10: ''`), и сборка
обрывается ошибкой `MissingPackageManifestError`.

Рабочее решение — отдельное venv на Python 3.14 (в нём `mac_ver` корректный):

```sh
/opt/homebrew/bin/python3.14 -m venv ~/.platformio-venv
~/.platformio-venv/bin/python -m pip install --upgrade platformio
~/.platformio-venv/bin/pio run          # сборка использует именно этот pio
```

Чтобы `pio` работал и из терминала VS Code, можно добавить его в PATH (`~/.zprofile`):

```sh
echo 'export PATH="$HOME/.platformio-venv/bin:$PATH"' >> ~/.zprofile
```

После этого достаточно команды `pio run`.

## Проверка результата

- Светодиод мигает с периодом 1 секунда (1 сек горит, 1 сек не горит).
- Serial Monitor (115200 бод) показывает начало работы и смену состояния.