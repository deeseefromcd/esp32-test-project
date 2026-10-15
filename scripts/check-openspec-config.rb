#!/usr/bin/env ruby
# frozen_string_literal: true

# Проверка openspec/config.yaml на ошибку, которую OpenSpec проглатывает молча.
#
# Если строка в списке содержит ": " и не взята в кавычки, YAML читает её как
# mapping, и OpenSpec выбрасывает ВЕСЬ список правил артефакта или всю секцию
# guidance со строкой "must be an array of strings, ignoring...".
# `openspec validate` при этом проходит — дефект виден только в stderr.
#
# Этот скрипт падает, если такой список содержит не строку.

require 'yaml'

path = ARGV[0] || 'openspec/config.yaml'

unless File.exist?(path)
  warn "check-openspec-config: нет файла #{path}"
  exit 0
end

begin
  data = YAML.load_file(path)
rescue Psych::SyntaxError => e
  warn "check-openspec-config: YAML не разбирается: #{e.message}"
  exit 1
end

unless data.is_a?(Hash)
  warn "check-openspec-config: ожидался объект верхнего уровня в #{path}"
  exit 1
end

errors = []
checked = 0

check_list = lambda do |label, value|
  return if value.nil?
  checked += 1
  unless value.is_a?(Array)
    errors << "#{label}: ожидался список строк, получено #{value.class}"
    return
  end
  value.each_with_index do |item, i|
    next if item.is_a?(String)
    errors << "#{label}[#{i}]: элемент не строка (#{item.class}) — вероятно, не хватает кавычек вокруг строки с \": \""
  end
end

# rules.<artifact> — список строк
(data['rules'] || {}).each do |artifact, rules|
  check_list.call("rules.#{artifact}", rules)
end

# operations.<op>.guidance — список строк
(data['operations'] || {}).each do |operation, spec|
  next unless spec.is_a?(Hash)
  check_list.call("operations.#{operation}.guidance", spec['guidance'])
end

# context — просто строка
if data.key?('context') && !data['context'].is_a?(String)
  errors << "context: ожидалась строка, получено #{data['context'].class}"
  checked += 1
end

if errors.empty?
  puts "OK: #{path} (#{checked} списков проверено, все элементы — строки)"
  exit 0
end

warn "check-openspec-config: проблемы в #{path}:"
errors.each { |e| warn "  - #{e}" }
warn ''
warn 'Подсказка: строку с ": " внутри бери в двойные кавычки.'
exit 1
