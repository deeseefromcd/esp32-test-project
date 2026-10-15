# Зависимости проекта, ставящиеся через Homebrew (macOS).
#
#   brew bundle --file Brewfile      # или: make setup
#
# Здесь только то, что имеет смысл ставить через brew на любой машине.
# Остальное — либо уже есть в macOS (ruby, make, git), либо ставится
# иначе (PlatformIO, wokwi-cli) — см. README, раздел «Настройка с нуля».

# Проверка workflow в make lint (и в CI)
brew "actionlint"
# shellcheck нужен actionlint для проверки блоков run: — тянется автоматически,
# указан явно, чтобы не сломаться, если это перестанет быть зависимостью
brew "shellcheck"

# Не через brew: PlatformIO. На части машин brew-версия ломается на новых
# Python (см. AGENTS.md §4.6), поэтому рабочий путь — venv или официальный
# установщик. Подробности в README.
