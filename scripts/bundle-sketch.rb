#!/usr/bin/env ruby
# frozen_string_literal: true

# Собирает sketch.ino из модулей src/ — файл для вставки в редактор на wokwi.com.
#
# Зачем: веб-редактор Wokwi не умеет загружать файлы (в трекере Wokwi это
# открытый запрос), поэтому прошивка попадает туда одним файлом. Собирать его
# руками — значит повторить ошибку рассинхрона: правило «sketch.ino и src/
# должны совпадать» сегодня не проверяет ничто.
#
# Что делает: склеивает модули в порядке MODULES и тело main.cpp, убирая
# #pragma once и локальные #include — они нужны только сборщику. Внешние
# #include (<Arduino.h>, <stdint.h>) остаются: в веб-редакторе они на месте.
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

# В самом sketch.ino видно, что правки в нём бесполезны.
BANNER = <<~'TEXT'
  /*
    ВНИМАНИЕ: файл собран из src/ — правки здесь будут затёрты.

    Сборка: make sketch  (scripts/bundle-sketch.rb)

    Нужен для wokwi.com: в веб-редакторе нет загрузки файлов, поэтому прошивка
    попадает туда одним файлом. Источник — src/ в репозитории.
  */
TEXT

# Убирает то, что имеет смысл только при раздельной сборке.
def strip_local(text)
  text
    .gsub(/^#pragma once\n/, '')
    .gsub(/^#include\s+"[^"]+"\n/, '')
    .strip
end

def bundle(root)
  parts = [BANNER]
  FILES.each do |name|
    path = root.join('src', name)
    abort "нет файла #{path}" unless path.exist?
    parts << "// ==== src/#{name} ====\n#{strip_local(path.read)}\n"
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
