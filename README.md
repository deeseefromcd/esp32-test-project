# esp32-test-project

Первый тестовый проект для [Wokwi](https://wokwi.com) + **PlatformIO**: мигающий светодиод на **ESP32-S3**.

## Настройка с нуля

Чтобы восстановить окружение из репозитория на новой машине (macOS):

```sh
git clone https://github.com/deeseefromcd/esp32-test-project
cd esp32-test-project

make doctor     # проверить, чего не хватает (ничего не ставит)
make setup      # поставить brew-зависимости: actionlint, shellcheck
```

`make doctor` покажет, что есть, чего нет и какой командой это ставить. Ниже —
что нужно вручную, потому что через brew это ставить нежелательно.

### 1. PlatformIO (`pio`)

Рекомендуемый путь — изолированное venv (brew-версия на свежих Python ломается,
см. [§ Особенность этой машины](#особенность-этой-машины-macos--python-315)).

**Важно:** нужен Python, у которого `platform.mac_ver()` не пустой. На новой macOS
`python3` по умолчанию может быть именно сломанной версией (например, 3.15), поэтому
не полагайся на `python3` — укажи версию явно:

```sh
python3 -c 'import platform; print(platform.mac_ver())'   # убедиться, что НЕ пусто
```

Если вывод пустой — возьми другую версию (на машине автора работает 3.14):

```sh
brew install python@3.14                                  # если её нет
/opt/homebrew/bin/python3.14 -m venv ~/.platformio-venv
~/.platformio-venv/bin/python -m pip install --upgrade platformio
```

Makefile находит это venv автоматически. Если у тебя `pio` уже стоит и работает,
ничего делать не нужно — Makefile возьмёт его из PATH. Переопределить путь можно
так: `make build PIO=/путь/к/pio`.

Первый `make build` скачает платформу `espressif32` и тулчейн — несколько сотен МБ
и несколько минут. Это разовая операция.

### 2. Wokwi CLI (`wokwi-cli`)

```sh
curl -L https://wokwi.com/ci/install.sh | sh    # ставит symlink в ~/bin
```

Нужен только для `make lint-diagram`. Для интерактивной разработки достаточно
расширения **Wokwi for VS Code** (см. ниже).

> Установщик дописывает `~/bin` в PATH твоей оболочки. `make` находит `wokwi-cli`
> и без этого (ищет в `~/bin` и `~/.local/bin` тоже), а `make doctor` подскажет
> готовую строку `export PATH=...`, если инструмент не в PATH.

### 3. Ruby, Node

На macOS `ruby` и `make` уже есть. Node нужен для `npx` (OpenSpec):

```sh
brew install node
```

### 4. OpenSpec (для `/opsx-*` команд)

Слэш-команды OpenCode (`.opencode/commands/opsx-*`) вызывают `openspec` из PATH.
Глобальная установка (в репозитории `package.json` при этом не появляется):

```sh
npm install -g @fission-ai/openspec@1.14.2
```

Без этого команды `/opsx-*` падают с `command not found`. Разовые вызовы без
установки работают через `npx @fission-ai/openspec@latest ...`.

> **Про секрет.** `WOKWI_CLI_TOKEN` (для локального прогона симуляции) на диск не
> кладётся — он живёт в GitHub Secrets. `make doctor` сообщает, задан он или нет,
> не печатая значение. Без токена доступны сборка, `make lint` и `make check`;
> поведение проверяет Wokwi CI по push.

### Кто чем проверяется

| Инструмент | Нужен для | Если нет |
| --- | --- | --- |
| `pio` | `make build`, `make check`, `make lint-cppcheck` | сборка и lint не работают |
| `wokwi-cli` | `make lint-diagram` | проверка схемы не работает |
| `actionlint` | `make lint-workflow` | шаг пропускается с предупреждением |
| `ruby` | `make lint-yaml` | проверка `config.yaml` не работает |
| `node`/`npx` | `openspec validate`, разовые вызовы | проверка спек не работает |
| `openspec` (глобально) | `/opsx-*` команды | команды падают |

> **Добавляешь новый инструмент?** Зарегистрируй его в репозитории, иначе на чужой
> машине он не появится: brew-пакет — в `Brewfile`, проверку — в `scripts/doctor.sh`,
> строку — в таблицу выше. Согласованность этих трёх мест проверяет `make lint-deps`
> (входит в `make lint`). Инструмент, нужный только в CI, регистрируется в workflow.

## Что внутри

| Файл | Назначение |
| --- | --- |
| `platformio.ini` | Конфигурация PlatformIO (плата `esp32-s3-devkitc-1`, framework Arduino) |
| `src/main.cpp` | Прошивка: мигает светодиодом на GPIO48 |
| `diagram.json` | Схема для симулятора Wokwi: плата ESP32-S3, светодиод, резистор 220 Ом |
| `wokwi.toml` | Указывает Wokwi, где лежит собранная прошивка (`.pio/build/...`) |
| `sketch.ino` | Копия кода для вставки в редактор на wokwi.com (на сборку не влияет) |
| `blink.test.yaml` | Сценарий проверки для Wokwi CI (мигание + уровень на пине) |
| `.github/workflows/wokwi.yml` | GitHub Action: сборка и тест в Wokwi CI на каждый push |
| `Makefile` | Удобные команды: `make setup`, `make doctor`, `make build`, `make check`, `make lint`, `make size`, `make flash`, `make sim` |
| `Brewfile` | brew-зависимости проекта: `actionlint`, `shellcheck` (`make setup`) |
| `scripts/doctor.sh` | Проверка окружения: чего не хватает и как это ставить (`make doctor`) |
| `scripts/check-openspec-config.rb` | Ловит дефект `openspec/config.yaml`, который `openspec validate` пропускает молча |
| `scripts/check-deps.sh` | Проверяет, что зависимости согласованы: `Brewfile` ↔ `doctor.sh` ↔ README |
| `AGENTS.md` | Инструкции для AI-агентов: обязательная синхронизация с wokwi.com, OpenSpec и обход известных проблем |
| `docs/SDD-WORKFLOW.md` | Как ставить задачи через OpenSpec: шаблоны, разбор прошлой задачи, шпаргалка |
| `openspec/` | Спецификации (SDD): `specs/` — актуальное поведение, `changes/` — предлагаемые изменения |
| `.opencode/` | Слэш-команды `/opsx-*` и навыки OpenSpec для OpenCode |
| `.gitignore` | Исключает артефакты сборки |

> **AI-агентам:** перед работой прочитай [`AGENTS.md`](./AGENTS.md) — там обязательный шаг
> «после пуша обновить проект на wokwi.com», правила OpenSpec и список известных граблей.
> Задача меняет поведение — планируй через OpenSpec (см. [`docs/SDD-WORKFLOW.md`](./docs/SDD-WORKFLOW.md)).

## Схема

```
ESP32-S3 GPIO48 ──► LED (анод) ──► LED (катод) ──► резистор 220 Ом ──► GND
```

GPIO48 выбран потому, что на реальной плате ESP32-S3-DevKitC-1 на нём висит встроенный RGB-светодиод.

## Запуск в VS Code (PlatformIO + Wokwi)

Порядок важен: **Wokwi не компилирует код — он запускает готовую прошивку.**

1. Установить расширение **PlatformIO IDE** в VS Code (даёт кнопку Build и терминал `pio`).

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

## Особенность этой машины (macOS + Python 3.15)

На части машин `brew install platformio` подтягивает свежий Python (3.15), в котором
`platform.mac_ver()` возвращает пустую строку. Из-за этого встроенный `pip` падает на
установке `tool-esptoolpy` (`ValueError: invalid literal for int() with base 10: ''`),
и сборка обрывается ошибкой `MissingPackageManifestError`.

Рабочее решение — отдельное venv (см. [Настройка с нуля](#настройка-с-нуля), шаг 1).
Makefile находит его автоматически.

Чтобы `pio` работал и из терминала VS Code, можно добавить его в PATH (`~/.zprofile`):

```sh
echo 'export PATH="$HOME/.platformio-venv/bin:$PATH"' >> ~/.zprofile
```

После этого достаточно команды `pio run`.

> Эта поломка специфична для macOS и новых Python. На Linux и в CI (Ubuntu,
> Python 3.11) проблемы нет — там `pip install platformio` работает штатно.

## Проверка результата

- Светодиод мигает с периодом 1 секунда (1 сек горит, 1 сек не горит).
- Serial Monitor (115200 бод) показывает начало работы и смену состояния.

## Синхронизация с Wokwi (GitHub → симуляция)

Важно: **автоматической синхронизации «пуш в GitHub → проект на wokwi.com» не существует.**
У Wokwi две независимые вещи:

1. **Проект на wokwi.com** — то, чем делятся ссылкой (`https://wokwi.com/projects/<id>`).
   Авто-импорта из GitHub нет: код и `diagram.json` там обновляются вручную.
2. **Wokwi CI (GitHub Actions)** — по пушу собирает прошивку и прогоняет симуляцию в облаке
   (проверка, а не публичная ссылка).

### Ссылка для друзей (wokwi.com)

**Проект уже создан и опубликован:**

- **Ссылка:** <https://wokwi.com/projects/477978257402627073>
- **Название:** ESP32-S3 Blink (LED on GPIO48) · видимость **Public**

Друзья открывают ссылку и жмут **Play** прямо в браузере, ничего устанавливать не нужно.

При изменениях кода схему и код на wokwi.com нужно обновить вручную (копия кода лежит
в `sketch.ino`, схема — в `diagram.json`): открыть проект → вставить файлы → **Save**.
Ссылка при этом не меняется.

> Если проект менял AI-агент — он делает это сам, см. `AGENTS.md` (раздел 2). Там же описаны
> известные грабли браузерной автоматизации.

### Авто-проверка на GitHub (Wokwi CI)

В репозитории уже есть workflow `.github/workflows/wokwi.yml` и сценарий `blink.test.yaml`:
на каждый push/PR GitHub собирает прошивку (`pio run`) и прогоняет её в Wokwi CI, проверяя,
что LED мигает и пин GPIO48 меняет уровень.

Чтобы включить, один раз добавь секрет:

1. Получить токен на <https://wokwi.com/dashboard/ci> (начинается с `wok_`, 44 символа).
2. GitHub → репозиторий → **Settings → Secrets and variables → Actions → New repository secret**.
3. Имя: `WOKWI_CLI_TOKEN`, значение: токен.

Бесплатного тарифа хватает (50 минут симуляции в месяц). Результат видно во вкладке
**Actions** на GitHub.
