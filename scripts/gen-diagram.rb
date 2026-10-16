#!/usr/bin/env ruby
# frozen_string_literal: true

# Собирает diagram.json из описания схемы: tools/diagram/topology.json (что с чем
# соединено), tools/diagram/layout.json (где стоит и как разведено) и
# tools/diagram/parts.json (смещения выводов деталей).
#
# Зачем: провод в diagram.json — это пара «деталь:вывод», а координат выводов в
# описании схемы нет. Шестнадцать кнопок, шестнадцать подтяжек и два корпуса дают
# десятки проводов, и держать их руками нечем: правка топологии меняет точки, к
# которым тянутся провода. Здесь координаты считаются из геометрии деталей,
# порядок проводов в сети — по раскладке, а топология остаётся читаемой.
#
# Проверки, которые генератор делает за описанием (ошибка — выход с кодом 1):
#   * каждый вывод детали участвует не больше чем в одной сети;
#   * каждая клетка поля описана ровно в одном корпусе;
#   * у сигнального и земляного контактов кнопки один и тот же вывод (иначе
#     клетка замыкается сама на себя);
#   * у каждой детали есть координата — правило раскладки или посадка.
#
# Запуск:
#   ruby scripts/gen-diagram.rb            — перезаписать diagram.json
#   ruby scripts/gen-diagram.rb --check    — только проверить актуальность
#   ruby scripts/gen-diagram.rb --capture  — снять посадку и маршруты из diagram.json в layout.json

require 'json'
require 'pathname'

ROOT = Pathname.new(__dir__).parent
DIAGRAM_DIR = ROOT.join('tools', 'diagram')
OUT = ROOT.join('diagram.json')
AUTHOR = 'deeseefromcd'

def die(message)
  warn "gen-diagram: #{message}"
  exit 1
end

def read_json(path)
  JSON.parse(path.read)
rescue JSON::ParserError => e
  die "#{path} не разбирается: #{e.message}"
end

# Деталь схемы: положение, поворот и смещения выводов.
class Part
  attr_accessor :left, :top
  attr_reader :id, :type, :attrs, :rotate, :pins

  def initialize(id:, type:, attrs:, rotate:, pins:)
    @id = id
    @type = type
    @attrs = attrs
    @rotate = rotate
    @pins = pins
    @left = nil
    @top = nil
  end

  def placed?
    !@left.nil?
  end

  def point(pin)
    die "у детали #{@id} нет вывода #{pin}" unless @pins.key?(pin)
    die "деталь #{@id} не поставлена" unless placed?

    [@left + @pins[pin][0], @top + @pins[pin][1]]
  end

  # Ставит деталь так, чтобы указанный вывод попал в заданную точку.
  def place(pin, x, y)
    die "у детали #{@id} нет вывода #{pin}" unless @pins.key?(pin)

    place_left_top(x - @pins[pin][0], y - @pins[pin][1])
  end

  def place_left_top(x, y)
    @left = x
    @top = y
  end
end

# Схема: детали, соединения и всё, что нужно для их вывода.
class Diagram
  attr_reader :parts, :connections

  def initialize(topology, layout, geometry)
    @topology = topology
    @layout = layout
    @geometry = geometry
    @parts = []
    @connections = []
    @cells = build_cells
    build_parts
    build_wiring
    check_placement
  end

  private

  # --- описание ------------------------------------------------------------

  def grid
    @topology.fetch('grid')
  end

  # Клетки поля в порядке строк и столбцов: [[имя, id корпуса, вход], ...].
  def build_cells
    chips = @topology.fetch('shiftRegisters').fetch('chain')
    out = []
    (1..grid.fetch('rows')).each do |row|
      ('A'.ord..('A'.ord + grid.fetch('cols') - 1)).map(&:chr).each do |col|
        cell = "#{col}#{row}"
        found = chips.map do |chip|
          index = chip.fetch('cells').index(cell)
          [chip.fetch('id'), "D#{index}"] if index
        end.compact
        die "клетка #{cell} описана в #{found.size} корпусах, а должна ровно в одном" if found.size != 1

        out << [cell, found[0][0], found[0][1]]
      end
    end
    out
  end

  def part_id(kind, cell)
    case kind
    when 'button' then "#{grid.dig('button', 'id_prefix')}#{cell}"
    when 'pullup' then "#{grid.dig('pullup', 'id_prefix')}#{cell}"
    else die "неизвестный вид детали клетки: #{kind}"
    end
  end

  def pins_for(type, rotate)
    spec = @geometry.fetch('parts')[type] || die("в parts.json нет геометрии для #{type}")
    if spec.key?('rotations')
      spec['rotations'].fetch(rotate.to_s) { die "в parts.json нет геометрии #{type} при повороте #{rotate}" }
    else
      spec.fetch('pins')
    end
  end

  # Поворот детали: правило раскладки, а если правку сняли из редактора — её.
  def rotate_for(id, default)
    @layout.dig('placements', id, 'rotate') || default
  end

  # --- сборка --------------------------------------------------------------

  def build_parts
    esp = @topology.fetch('board')
    add_part(Part.new(id: esp['id'], type: esp['type'], attrs: esp['attrs'], rotate: 0,
                      pins: pins_for(esp['type'], 0)))
    @topology.fetch('shiftRegisters').fetch('chain').each do |chip|
      add_part(Part.new(id: chip['id'], type: chip['type'], attrs: chip['attrs'], rotate: 0,
                        pins: pins_for(chip['type'], 0)))
    end
    led = @topology.fetch('indicator').fetch('led')
    add_part(Part.new(id: led['id'], type: led['type'], attrs: led['attrs'], rotate: 0,
                      pins: pins_for(led['type'], 0)))
    resistor = @topology.fetch('indicator').fetch('resistor')
    add_part(Part.new(id: resistor['id'], type: resistor['type'], attrs: resistor['attrs'],
                      rotate: rotate_for(resistor['id'], 90), pins: pins_for(resistor['type'], 90)))
    build_field
    apply_rules
    apply_placements
  end

  # Матрица поля: кнопка клетки — в своей строке и столбце, подтяжка — рядом.
  def build_field
    field = @layout.dig('rules', 'field') || die('в layout.json нет rules.field')
    cells_spec = @topology.fetch('cells')
    ox, oy = field.fetch('origin')
    step_x, step_y = field.fetch('step')
    offset_x, offset_y = field.fetch('pullupOffset')
    @cells.each_with_index do |(cell, _chip, _input), index|
      column = index % grid.fetch('cols')
      row = index / grid.fetch('cols')
      button = Part.new(id: part_id('button', cell), type: grid.dig('button', 'type'),
                        attrs: render_attrs(grid.dig('button', 'attrs'), cell),
                        rotate: rotate_for(part_id('button', cell), 90),
                        pins: pins_for(grid.dig('button', 'type'), 90))
      button.place_left_top(ox + column * step_x, oy + row * step_y)
      add_part(button)

      signal_x, signal_y = button.point(cells_spec.fetch('signalPin'))
      pullup = Part.new(id: part_id('pullup', cell), type: grid.dig('pullup', 'type'),
                        attrs: grid.dig('pullup', 'attrs'),
                        rotate: rotate_for(part_id('pullup', cell), 90),
                        pins: pins_for(grid.dig('pullup', 'type'), 90))
      pullup.place(cells_spec.fetch('pullupPin'), signal_x + offset_x, signal_y + offset_y)
      add_part(pullup)
    end
  end

  def render_attrs(attrs, cell)
    attrs.transform_values do |value|
      value.to_s.gsub('<cell>', cell).gsub('<row-color>', grid.fetch('rowColors').fetch(cell[1]))
    end
  end

  def add_part(part)
    die "деталь #{part.id} описана дважды" if @parts.any? { |p| p.id == part.id }

    @parts << part
    part
  end

  # Координаты деталей, которым не нужно место в матрице поля.
  def apply_rules
    @layout.fetch('rules').fetch('at', {}).each do |id, at|
      part(@parts, id).place_left_top(at[0], at[1])
    end
  end

  # Посадка из layout.json перекрывает правила: так правки, сделанные мышью в
  # редакторе и снятые make diagram-capture, не теряются при перегенерации.
  def apply_placements
    @layout.fetch('placements', {}).each do |id, spec|
      part(@parts, id).place_left_top(spec['at'][0], spec['at'][1])
    end
  end

  def part(parts, id)
    parts.find { |p| p.id == id } || die("в layout.json есть координата неизвестной детали #{id}")
  end

  # --- соединения ----------------------------------------------------------

  def build_wiring
    seen = {}
    nets = @topology.fetch('nets').map { |net| expand(net) } + cell_nets
    nets.each do |net|
      net.fetch('members').each do |member|
        if seen.key?(member)
          die "вывод #{member} попал и в сеть #{seen[member]}, и в сеть #{net['name']}"
        end

        seen[member] = net.fetch('name')
      end
      wire(net)
    end
  end

  # Сети питания и земли общие: их члены дополняются по одному выводу на клетку.
  def expand(net)
    per_cell = net.fetch('perCell', {})
    return net if per_cell.empty?

    members = net.fetch('members').dup
    @cells.each do |cell, _chip, _input|
      per_cell.each { |kind, pin| members << "#{part_id(kind, cell)}:#{pin}" }
    end
    net.merge('members' => members)
  end

  # Сеть клетки: сигнальный контакт кнопки, подтяжка и вход регистра.
  def cell_nets
    spec = @topology.fetch('cells')
    if spec.fetch('signalPin') == spec.fetch('buttonGroundPin')
      die "у кнопки сигнал и земля на одном выводе #{spec.fetch('signalPin')}"
    end

    @cells.map do |cell, chip, input|
      { 'name' => "cell-#{cell}", 'color' => spec.fetch('color'),
        'members' => ["#{part_id('button', cell)}:#{spec.fetch('signalPin')}",
                      "#{part_id('pullup', cell)}:#{spec.fetch('pullupPin')}",
                      "#{chip}:#{input}"] }
    end
  end

  # Провода кладутся цепочкой: первым идёт вывод, записанный в описании первым
  # (обычно вывод платы управления), дальше каждый раз ближайший неподключённый.
  # Так провода короткие и не собираются пучком из одного вывода.
  def wire(net)
    order = chain_order(net.fetch('members').map { |member| resolve(member) })
    order.each_cons(2) do |from, to|
      add_connection(from[:endpoint], to[:endpoint], net.fetch('color', ''),
                     default_route(from[:endpoint], to[:endpoint]))
    end
  end

  def chain_order(members)
    return members if members.size <= 2

    order = [members.first]
    rest = members[1..].dup
    until rest.empty?
      nearest = rest.min_by { |member| distance(order.last[:point], member[:point]) }
      order << nearest
      rest.delete(nearest)
    end
    order
  end

  def resolve(member)
    return { endpoint: member, point: nil } if member.start_with?('$')

    id, pin = member.split(':', 2)
    found = @parts.find { |p| p.id == id } || die("соединение ссылается на неизвестную деталь #{id}")
    { endpoint: member, point: found.point(pin) }
  end

  def distance(a, b)
    return 0.0 if a.nil? || b.nil?

    Math.hypot(a[0] - b[0], a[1] - b[1])
  end

  def add_connection(a, b, color, route)
    return if @connections.any? { |c| (c[0] == a && c[1] == b) || (c[0] == b && c[1] == a) }

    stored = @layout.fetch('routes', {})["#{a}|#{b}"] || @layout.fetch('routes', {})["#{b}|#{a}"]
    @connections << [a, b, color, stored || route]
  end

  # Маршрут: программа монитора — без маршрута, провод между выводами деталей —
  # прямой. Маршрутов макетной платы здесь больше нет: плат в схеме нет.
  def default_route(a, b)
    return [] if a.start_with?('$') || b.start_with?('$')

    ['v0']
  end

  def check_placement
    @parts.each do |part|
      next if part.placed?

      die "у детали #{part.id} нет координаты — добавь её в rules.at или в rules.field"
    end
  end

  public

  # --- вывод ---------------------------------------------------------------

  def num(value)
    rounded = value.to_f.round(2)
    return rounded.round.to_s if (rounded - rounded.round).abs < 1e-9

    format('%.2f', rounded).sub(/0+\z/, '').sub(/\.\z/, '')
  end

  def normalize(value)
    return value unless value.is_a?(Float)

    (value - value.round).abs < 1e-9 ? value.round : value
  end

  def to_json_text
    lines = ['{', '  "version": 1,', "  \"author\": \"#{AUTHOR}\",", '  "editor": "wokwi",', '  "parts": [']
    lines += @parts.each_with_index.map { |part, i| "    #{part_line(part)}#{i == @parts.size - 1 ? '' : ','}" }
    lines << '  ],'
    lines << '  "connections": ['
    lines += @connections.each_with_index.map do |conn, i|
      tail = i == @connections.size - 1 ? '' : ','
      "    [ \"#{conn[0]}\", \"#{conn[1]}\", \"#{conn[2]}\", #{route_text(conn[3])} ]#{tail}"
    end
    lines << '  ],'
    lines << '  "dependencies": {}'
    lines << '}'
    "#{lines.join("\n")}\n"
  end

  def part_line(part)
    fields = ["\"type\": \"#{part.type}\"", "\"id\": \"#{part.id}\"",
              "\"top\": #{num(part.top)}", "\"left\": #{num(part.left)}"]
    fields << "\"rotate\": #{part.rotate}" unless part.rotate.zero?
    fields << "\"attrs\": #{attrs_text(part.attrs)}"
    "{ #{fields.join(', ')} }"
  end

  def attrs_text(attrs)
    return '{}' if attrs.empty?

    inner = attrs.map { |k, v| "\"#{k}\": \"#{v}\"" }.join(', ')
    "{ #{inner} }"
  end

  def route_text(route)
    return '[]' if route.nil? || route.empty?

    "[ #{route.map { |step| "\"#{step}\"" }.join(', ')} ]"
  end

  # Что снять из diagram.json в layout.json, чтобы перегенерация не разрушила
  # расстановку и разводку, сделанные в редакторе.
  def capture(diagram)
    placements = {}
    @parts.each do |part|
      source = diagram['parts'].find { |p| p['id'] == part.id } || next
      entry = { 'at' => [normalize(source['left']), normalize(source['top'])] }
      if source.key?('rotate') && source['rotate'] != part.rotate
        entry['rotate'] = source['rotate']
      end
      placements[part.id] = entry
    end
    routes = {}
    diagram['connections'].each do |a, b, _color, route|
      next if route.nil? || route.empty? || route == default_route(a, b) || a.include?('$') || b.include?('$')

      routes["#{a}|#{b}"] = route
    end
    @layout['placements'] = placements
    @layout['routes'] = routes
    @layout
  end
end

topology = read_json(DIAGRAM_DIR.join('topology.json'))
layout = read_json(DIAGRAM_DIR.join('layout.json'))
geometry = read_json(DIAGRAM_DIR.join('parts.json'))
diagram = Diagram.new(topology, layout, geometry)

if ARGV.include?('--capture')
  captured = diagram.capture(read_json(OUT))
  DIAGRAM_DIR.join('layout.json').write("#{JSON.pretty_generate(captured)}\n")
  puts 'посадка и маршруты сняты из diagram.json в tools/diagram/layout.json'
  exit 0
end

text = diagram.to_json_text

if ARGV.include?('--check')
  unless OUT.exist?
    warn 'diagram.json отсутствует — собери его: make diagram'
    exit 1
  end
  if OUT.read != text
    warn 'diagram.json разошёлся с описанием схемы — пересобери его: make diagram'
    exit 1
  end
  puts "diagram.json совпадает с описанием (#{diagram.parts.size} деталей, #{diagram.connections.size} соединений)"
  exit 0
end

OUT.write(text)
puts "собран diagram.json из описания (#{diagram.parts.size} деталей, #{diagram.connections.size} соединений)"
