#!/usr/bin/env ruby
# frozen_string_literal: true

# Собирает sketch.ino из модулей src/ — файл для вставки в редактор на wokwi.com.
#
# Зачем: веб-редактор Wokwi не умеет загружать файлы (в трекере Wokwi это
# открытый запрос), поэтому прошивка попадает туда одним файлом. Собирать его
# руками — значит повторить ошибку рассинхрона: правило «sketch.ino и src/
# должны совпадать» сегодня не проверяет ничто.
#
# Почему файл собирается в два слоя. Arduino-компилятор (и PlatformIO, и
# arduino-cli) сам вставляет в скетч прототипы функций: он ищет первое
# определение функции и кладёт объявления всех функций перед ним. Прототипы
# ссылаются на типы из сигнатур, поэтому типы обязаны быть объявлены выше этой
# точки. При простой склейке модулей это не так: первый прототип попадает
# перед первым определением в grid_logic.h, а типы blink.h и grid_logic.h
# объявлены ниже — сборка в редакторе падает с «'State' was not declared in
# this scope», хотя src/ собирается нормально.
#
# Поэтому склейка идёт в два слоя: сначала объявления (типы, константы,
# состояние) всех модулей, затем их функции. Внешние #include поднимаются в
# начало файла, пространства имён открываются в обоих слоях (это законно в C++).
# Границу между слоями в модуле задаёт отметка MARKER: она ставится вручную там,
# где заканчиваются объявления, и без неё сборка падает с понятной ошибкой, а не
# собирает файл, который не компилируется.
#
# Запуск:
#   ruby scripts/bundle-sketch.rb           — перезаписать sketch.ino
#   ruby scripts/bundle-sketch.rb --check   — только проверить актуальность

require 'pathname'

ROOT = Pathname.new(__dir__).parent

# Модули независимы друг от друга, поэтому порядок — от чистого к железному;
# главное, что main.cpp идёт последним: он определяет setup() и loop().
MODULES = %w[grid_logic.h blink.h grid_reader.h].freeze
MAIN = 'main.cpp'
FILES = (MODULES + [MAIN]).freeze

# Отметка границы «объявления / функции» в модуле.
MARKER = '// ==== склейка: выше объявления, ниже функции ===='

# В самом sketch.ino видно, что правки в нём бесполезны.
BANNER = <<~'TEXT'
  /*
    ВНИМАНИЕ: файл собран из src/ — правки здесь будут затёрты.

    Сборка: make sketch  (scripts/bundle-sketch.rb)

    Нужен для wokwi.com: в веб-редакторе нет загрузки файлов, поэтому прошивка
    попадает туда одним файлом. Источник — src/ в репозитории.

    Файл собран в два слоя: сначала объявления всех модулей, потом их функции
    (сборщик ставит объявления выше первой функции, иначе Arduino-компилятор
    вставляет прототипы раньше типов и скетч не собирается).
  */
TEXT

# Модуль, разобранный на слои склейки.
class Module
  attr_reader :name, :includes, :decls, :impls, :namespace

  def initialize(name, text)
    @name = name
    @includes = []
    @namespace = nil
    @decls, @impls = split(text)
  end

  private

  def split(text)
    text = strip_local(text)
    text = lift_includes(text)
    lines = text.lines
    index = lines.index { |line| line.strip == MARKER }
    abort "в src/#{@name} нет отметки склейки — добавь строку:\n  #{MARKER}" if index.nil?

    above = lines[0...index]
    below = lines[(index + 1)..]
    @namespace = peel_namespace(above)
    close_namespace(below)

    [above.join.strip, below.join.strip]
  end

  # Убирает то, что имеет смысл только при раздельной сборке.
  def strip_local(text)
    text
      .gsub(/^#pragma once\n/, '')
      .gsub(/^#include\s+"[^"]+"\n/, '')
  end

  # Внешние #include уезжают в начало скетча: в веб-редакторе они на месте.
  def lift_includes(text)
    text.gsub(/^#include\s+<[^>]+>\n/) do |line|
      @includes << line.strip
      ''
    end
  end

  # Пространство имён открывается в обоих слоях, поэтому строка с ним уходит из
  # объявлений, а её закрытие — из функций.
  def peel_namespace(lines)
    index = lines.index { |line| line.start_with?('namespace ') }
    return nil if index.nil?

    name = lines[index][/namespace\s+(\w+)/, 1]
    lines.delete_at(index)
    name
  end

  def close_namespace(lines)
    lines.reject! { |line| line.start_with?('}') && line.include?('namespace') }
  end
end

def wrap(mod, body)
  return body if mod.namespace.nil?

  ["namespace #{mod.namespace} {", '', body, '', "}  // namespace #{mod.namespace}"].join("\n")
end

def bundle(root)
  modules = FILES.map do |name|
    path = root.join('src', name)
    abort "нет файла #{path}" unless path.exist?
    Module.new(name, path.read)
  end

  includes = modules.flat_map(&:includes).uniq
  namespaces = modules.map(&:namespace).compact.uniq
  parts = [BANNER, includes.join("\n"), '']

  parts << '// ---- Объявления: типы, константы и состояние всех модулей ----'
  modules.each do |mod|
    parts << "// ==== src/#{mod.name} ====\n#{wrap(mod, mod.decls)}\n"
  end

  # Прототипы, которые вставляет Arduino-компилятор, попадают вне пространств
  # имён, а в сигнатурах стоят их типы (State, Debounce). Директивы ниже делают
  # эти имена видимыми без квалификации — без них сборка в редакторе падает.
  # Стоят они после объявлений: до объявления пространства имён директива
  # `using namespace` не работает.
  unless namespaces.empty?
    parts << '// Имена модулей видны без квалификации: см. комментарий в начале файла.'
    namespaces.each { |name| parts << "using namespace #{name};" }
    parts << ''
  end

  parts << '// ---- Функции ----'
  modules.each do |mod|
    parts << "// ==== src/#{mod.name} ====\n#{wrap(mod, mod.impls)}\n"
  end

  parts.join("\n")
end

content = bundle(ROOT)
out = ROOT.join('sketch.ino')

if ARGV.include?('--check')
  unless out.exist?
    warn "sketch.ino отсутствует — собери его: make sketch"
    exit 1
  end
  if out.read != content
    warn 'sketch.ino разошёлся с src/ — пересобери его: make sketch'
    exit 1
  end
  puts "sketch.ino совпадает с src/ (#{FILES.size} файлов)"
  exit 0
end

out.write(content)
puts "собран sketch.ino из src/ (#{FILES.size} файлов)"
