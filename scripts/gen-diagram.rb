#!/usr/bin/env ruby
# frozen_string_literal: true

# Собирает diagram.json из описания схемы: tools/diagram/topology.json (что с чем
# соединено), tools/diagram/layout.json (где стоит и как разведено) и
# tools/diagram/parts.json (смещения выводов деталей).
#
# Зачем: в diagram.json связь задаётся именем отверстия макетной платы, а не
# координатой. Руками такие имена не удержать — шестнадцать кнопок, шестнадцать
# подтяжек и два корпуса дают больше сотни соединений, и любая правка топологии
# сдвигает их все. Здесь координаты выводов считаются из геометрии деталей,
# имена отверстий подставляются по координатам, а топология остаётся читаемой.
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

# Допуск посадки: редактор Wokwi сам соединяет вывод с отверстием, если они
# ближе 2 px. Генератор берёт тот же допуск, поэтому нарисованная схема и
# объявленные соединения совпадают.
TOLERANCE = 2.0

GRID_HOLE = /\A(\d+)([tb])\.([a-j])\z/
RAIL_HOLE = /\A(tp|tn|bp|bn)\.(\d+)\z/

def die(message)
  warn "gen-diagram: #{message}"
  exit 1
end

def read_json(path)
  JSON.parse(path.read)
rescue JSON::ParserError => e
  die "#{path} не разбирается: #{e.message}"
end

# Макетная плата: сетка отверстий и шины питания.
class Board
  attr_reader :id, :type, :left, :top, :attrs

  def initialize(id, spec, geometry)
    @id = id
    @type = spec.fetch('type')
    @left = spec['at'][0]
    @top = spec['at'][1]
    @attrs = spec.fetch('attrs', {})
    @grid = geometry.fetch('parts').fetch(@type).fetch('grid')
  end

  def columns
    @grid['columns']
  end

  def rails
    @grid['rails']
  end

  # Координата отверстия в системе схемы.
  def hole_xy(hole)
    if (m = GRID_HOLE.match(hole))
      [@left + @grid['x0'] + (m[1].to_i - 1) * @grid['columnsX'], @top + @grid['rowsY'].fetch(m[3])]
    elsif (m = RAIL_HOLE.match(hole))
      rail = rails.fetch(m[1])
      [@left + rail['x0'] + (m[2].to_i - 1) * @grid['columnsX'], @top + rail['y']]
    else
      die "отверстие #{@id}:#{hole} не разобрать"
    end
  end

  # Электрическая точка отверстия: колонка целиком не проводит, проводят её
  # половины (a..e и f..j), а шина проводит по всей длине.
  def node_of(hole)
    if (m = GRID_HOLE.match(hole))
      "#{@id}##{m[1]}#{m[2]}"
    elsif (m = RAIL_HOLE.match(hole))
      "#{@id}##{m[1]}"
    else
      die "отверстие #{@id}:#{hole} не разобрать"
    end
  end

  def holes_of(node)
    kind = node.split('#', 2).last
    if RAIL_HOLE.match("#{kind}.1")
      rail = rails.fetch(kind)
      (1..rail['count']).map { |n| "#{kind}.#{n}" }
    else
      m = kind.match(/\A(\d+)([tb])\z/) || die("точка #{node} не разобрать")
      rows = m[2] == 't' ? @grid['topRows'] : @grid['bottomRows']
      rows.map { |row| "#{m[1]}#{m[2]}.#{row}" }
    end
  end

  # Ближайшее отверстие к точке — если оно ближе допуска, иначе nil.
  def hole_at(x, y)
    best = candidates(x, y).min_by do |hole|
      hx, hy = hole_xy(hole)
      Math.hypot(hx - x, hy - y)
    end
    return nil if best.nil?

    hx, hy = hole_xy(best)
    Math.hypot(hx - x, hy - y) <= TOLERANCE ? best : nil
  end

  def nearest_hole(holes, x, y)
    holes.min_by do |hole|
      hx, hy = hole_xy(hole)
      Math.hypot(hx - x, hy - y)
    end
  end

  private

  # Кандидаты: три колонки вокруг x во всех десяти рядах и по одному отверстию
  # на каждую шину. Перебирать все 830 отверстий платы не нужно.
  def candidates(x, y)
    out = []
    col = ((x - @left - @grid['x0']) / @grid['columnsX']).round + 1
    [col - 1, col, col + 1].each do |c|
      next if c < 1 || c > columns

      @grid['topRows'].each { |row| out << "#{c}t.#{row}" }
      @grid['bottomRows'].each { |row| out << "#{c}b.#{row}" }
    end
    rails.each do |name, spec|
      n = ((x - @left - spec['x0']) / @grid['columnsX']).round + 1
      out << "#{name}.#{n}" if n >= 1 && n <= spec['count']
    end
    out
  end
end

# Деталь схемы: положение, поворот и смещения выводов.
class Part
  attr_accessor :left, :top, :board
  attr_reader :id, :type, :attrs, :rotate, :pins, :anchor

  def initialize(id:, type:, attrs:, rotate:, pins:, anchor: nil)
    @id = id
    @type = type
    @attrs = attrs
    @rotate = rotate
    @pins = pins
    @anchor = anchor
    @left = nil
    @top = nil
    @board = nil
  end

  def on_board?
    !@board.nil?
  end

  def point(pin)
    dx, dy = @pins.fetch(pin) { die "у детали #{@id} нет вывода #{pin}" }
    [@left + dx, @top + dy]
  end

  # Ставит деталь так, чтобы её якорный вывод попал в заданное отверстие.
  def place(board, pin, hole)
    dx, dy = @pins.fetch(pin) { die "у детали #{@id} нет якорного вывода #{pin}" }
    hx, hy = board.hole_xy(hole)
    @board = board
    @left = hx - dx
    @top = hy - dy
  end

  def place_free(left, top)
    @left = left
    @top = top
  end
end

# Схема: детали, соединения и всё, что нужно для их вывода.
class Diagram
  attr_reader :boards, :parts, :connections

  def initialize(topology, layout, geometry)
    @topology = topology
    @layout = layout
    @geometry = geometry
    @boards = build_boards
    @parts = []
    @connections = []
    @extra_nets = []
    build_parts
    build_wiring
  end

  private

  def build_boards
    @layout.fetch('boards').map { |id, spec| Board.new(id, spec, @geometry) }
  end

  def board(id)
    @boards.find { |b| b.id == id } || die("в layout.json нет платы #{id}")
  end

  def board_part?(id)
    @boards.any? { |b| b.id == id }
  end

  def pins_for(type, rotate)
    spec = @geometry.fetch('parts')[type] || die("в parts.json нет геометрии для #{type}")
    if spec.key?('rotations')
      spec['rotations'].fetch(rotate.to_s) { die "в parts.json нет геометрии #{type} при повороте #{rotate}" }
    else
      spec.fetch('pins')
    end
  end

  def build_parts
    @boards.each do |b|
      part = Part.new(id: b.id, type: b.type, attrs: b.attrs, rotate: 0, pins: {})
      part.place_free(b.left, b.top)
      add_part(part)
    end
    board_spec = @topology.fetch('board')
    add_part(Part.new(id: board_spec['id'], type: board_spec['type'], attrs: board_spec['attrs'],
                      rotate: 0, pins: pins_for(board_spec['type'], 0)))
    indicator = @topology.fetch('indicator')
    add_part(Part.new(id: indicator['led']['id'], type: indicator['led']['type'],
                      attrs: indicator['led']['attrs'], rotate: 0,
                      pins: pins_for(indicator['led']['type'], 0)))
    add_part(Part.new(id: indicator['resistor']['id'], type: indicator['resistor']['type'],
                      attrs: indicator['resistor']['attrs'], rotate: 90,
                      pins: pins_for(indicator['resistor']['type'], 90)))
    @topology.fetch('shiftRegisters').fetch('chain').each_with_index do |chip_spec, index|
      build_chip(chip_spec, index)
    end
    apply_free_rules
    apply_placements
  end

  # Свободные детали (плата управления, светодиод, резистор) стоят вне макетной
  # платы: им задаётся координата, а не отверстие.
  def apply_free_rules
    @layout.fetch('rules', {}).fetch('free', {}).each do |id, spec|
      part = @parts.find { |p| p.id == id } || die("в layout.json есть свободная деталь #{id}, которой нет в топологии")
      part.place_free(spec['at'][0], spec['at'][1])
    end
  end
  # Корпус регистра: якорь — вывод PL, он садится в нижний ряд f левой колонки.
  # Смещения выводов задают, в какой колонке и в какой половине платы оказался
  # каждый вход D0..D7, поэтому карта «клетка → вход» проверяется геометрией.
  def build_chip(chip_spec, index)
    rule = @layout.dig('rules', 'chips', chip_spec['id']) ||
           die("в layout.json нет правила посадки для #{chip_spec['id']}")
    chip = Part.new(id: chip_spec['id'], type: chip_spec['type'], attrs: chip_spec['attrs'],
                    rotate: 0, pins: pins_for(chip_spec['type'], 0), anchor: 'PL')
    add_part(chip)
    chip.place(board(rule['board']), 'PL', "#{rule['column']}b.f")

    buttons = @layout.dig('rules', 'buttons')
    grid = @topology.fetch('grid')
    chip_spec.fetch('cells').each_with_index do |cell, i|
      input = "D#{i}"
      column = rule['column'] + column_offset(chip, input)
      half = input_half(chip, input)
      button = Part.new(id: "#{grid['button']['id_prefix']}#{cell}", type: grid['button']['type'],
                        attrs: grid['button']['attrs'].transform_values { |v| v.to_s.gsub('<cell>', cell).gsub('<row-color>', grid['rowColors'].fetch(cell[1])) },
                        rotate: 90, pins: pins_for(grid['button']['type'], 90), anchor: '1.l')
      button.place(board(rule['board']), '1.l', "#{buttons['firstColumn'] + i * buttons['step']}t.b")
      add_part(button)
      pullup = Part.new(id: "#{grid['pullup']['id_prefix']}#{cell}", type: grid['pullup']['type'],
                        attrs: grid['pullup']['attrs'], rotate: 90,
                        pins: pins_for(grid['pullup']['type'], 90), anchor: half == 't' ? '2' : '1')
      pullup.place(board(rule['board']), pullup.anchor, half == 't' ? "#{column}t.c" : "#{column}b.g")
      add_part(pullup)
      @extra_nets << cell_net(cell, chip, input, button, pullup, half)
      @extra_nets << cell_ground_net(cell, button, half, rule['board'])
    end
  end

  # Колонка входа считается по смещению вывода от PL: одна колонка — 9.6 px.
  def column_offset(chip, pin)
    pitch = @geometry.fetch('pitch')
    ((chip.pins.fetch(pin)[0] - chip.pins.fetch('PL')[0]) / pitch).round
  end

  # Половина платы, в которую попал вывод: верхний ряд корпуса ложится на ряд e,
  # нижний — на ряд f.
  def input_half(chip, pin)
    chip.pins.fetch(pin)[1] < 15 ? 't' : 'b'
  end

  # Явная посадка из layout.json перекрывает правила: так правки, сделанные в
  # редакторе и снятые make diagram-capture, не теряются при перегенерации.
  def apply_placements
    @layout.fetch('placements', {}).each do |id, spec|
      next if board_part?(id)

      part = @parts.find { |p| p.id == id } || die("в layout.json есть посадка неизвестной детали #{id}")
      if spec.key?('board')
        part.place(board(spec['board']), part.anchor || die("у детали #{id} нет якорного вывода"),
                   spec['hole'])
      else
        part.place_free(spec['at'][0], spec['at'][1])
      end
    end
  end

  def add_part(part)
    die "деталь #{part.id} описана дважды" if @parts.any? { |p| p.id == part.id }
    @parts << part
    part
  end

  # --- соединения ----------------------------------------------------------

  def build_wiring
    @parts.each do |part|
      next unless part.on_board?

      part.pins.each_key { |pin| declare(part, pin) }
    end
    nets = @topology.fetch('nets') + @extra_nets
    nets.each { |net| wire(net) }
  end

  # Вывод, стоящий в отверстии, объявляется соединённым с ним: иначе в схеме
  # деталь нарисована на плате, а электрически к ней не подключена.
  def declare(part, pin)
    x, y = part.point(pin)
    hole = part.board.hole_at(x, y) || die(
      "вывод #{part.id}:#{pin} не попал в отверстие платы #{part.board.id} — перекалибруй parts.json"
    )
    add_connection("#{part.id}:#{pin}", "#{part.board.id}:#{hole}", '', ['$bb'])
  end

  def add_connection(a, b, color, route)
    return if @connections.any? { |c| (c[0] == a && c[1] == b) || (c[0] == b && c[1] == a) }

    stored = @layout.fetch('routes', {})["#{a}|#{b}"] || @layout.fetch('routes', {})["#{b}|#{a}"]
    @connections << [a, b, color, stored || route]
  end

  # Точка вывода: отверстие платы для детали на плате, сам вывод — для свободной.
  def endpoint(part, pin)
    if part.on_board?
      x, y = part.point(pin)
      hole = part.board.hole_at(x, y) || die("вывод #{part.id}:#{pin} не попал в отверстие")
      { endpoint: "#{part.board.id}:#{hole}", node: part.board.node_of(hole), point: [x, y] }
    else
      { endpoint: "#{part.id}:#{pin}", node: "pin:#{part.id}:#{pin}", point: part.point(pin) }
    end
  end

  def resolve_member(member)
    id, pin = member.split(':', 2)
    return { endpoint: member, node: "pin:#{member}", point: nil } if id.start_with?('$')

    part = @parts.find { |p| p.id == id } || die("соединение ссылается на неизвестную деталь #{id}")
    endpoint(part, pin)
  end

  # Провода кладутся от точки к точке. У шин питания есть hubs: каждая группа
  # выводов тянется к ближайшему отверстию шины, а шины соединяются между собой,
  # поэтому проводов мало и они короткие.
  def wire(net)
    members = net.fetch('members').map { |m| resolve_member(m) }
    groups = {}
    members.each do |m|
      groups[m[:node]] ||= m
    end
    hubs = net.fetch('hubs', []).map { |h| hub_node(h) }
    hubs = [groups.keys.first] if hubs.empty?

    hubs.each_with_index do |node, i|
      next if i.zero?

      previous = hubs[0...i].flat_map { |n| hub_anchors(n, groups) }
      seed = hub_anchors(node, groups).first
      target = previous.min_by { |a| distance(a, seed) }
      from = hub_anchors(node, groups).min_by { |a| distance(a, target) }
      add_connection(from[:endpoint], target[:endpoint], net['color'],
                     default_route(from[:endpoint], target[:endpoint]))
    end

    hub_points = hubs.flat_map { |n| hub_anchors(n, groups) }
    groups.each do |node, group|
      next if hubs.include?(node)

      target = hub_points.min_by { |point| distance(point, group) }
      add_connection(group[:endpoint], target[:endpoint], net['color'],
                     default_route(group[:endpoint], target[:endpoint]))
    end
  end

  def hub_node(ref)
    kind, name = ref.split(':', 2)
    die "шина #{ref} должна выглядеть как rail:bb1.tp" unless kind == 'rail'

    board_id, rail = name.split('.', 2)
    board(board_id).node_of("#{rail}.1")
  end

  # Кандидаты точки: все отверстия шины или колонки, либо сам вывод свободной детали.
  def hub_anchors(node, groups)
    board_id = node.split('#', 2).first
    board = @boards.find { |b| b.id == board_id }
    return [groups.fetch(node)] if board.nil?

    board.holes_of(node).map do |hole|
      { endpoint: "#{board.id}:#{hole}", point: board.hole_xy(hole) }
    end
  end

  def distance(a, b)
    return 0.0 if a[:point].nil? || b[:point].nil?

    Math.hypot(a[:point][0] - b[:point][0], a[:point][1] - b[:point][1])
  end

  # Маршрут задаёт редактор (или пользователь): программа монитора — без
  # маршрута, провод между выводами деталей — прямой, остальное ведёт
  # маршрутизатор макетной платы.
  def default_route(a, b)
    return [] if a.start_with?('$') || b.start_with?('$')

    board_ids = @boards.map(&:id)
    on_hole = [a, b].any? { |endpoint| board_ids.include?(endpoint.split(':', 2).first) }
    on_hole ? ['$bb'] : ['v0']
  end

  # Сеть клетки: контакт кнопки и вход регистра — одна колонка платы. Берётся
  # тот контакт кнопки, который лежит в той же половине платы, что и вход.
  def cell_net(cell, chip, input, button, pullup, half)
    # Шин здесь нет намеренно: сигнал клетки — это колонка кнопки, соединённая
    # с колонкой входа регистра. У подтяжки берётся тот её вывод, который стоит
    # в этой же колонке: второй вывод упирается в шину питания.
    { 'name' => "cell-#{cell}", 'color' => 'green',
      'members' => ["#{button.id}:#{half == 't' ? '1.l' : '1.r'}", "#{chip.id}:#{input}",
                    "#{pullup.id}:#{pullup.anchor}"] }
  end

  # Земля кнопки: второй контакт тянется в шину земли той же половины.
  def cell_ground_net(cell, button, half, board_id)
    { 'name' => "gnd-#{cell}", 'color' => 'black',
      'members' => ["#{button.id}:#{half == 't' ? '2.l' : '2.r'}"],
      'hubs' => ["rail:#{board_id}.#{half == 't' ? 'tn' : 'bn'}"] }
  end

  public

  # --- вывод ---------------------------------------------------------------

  def num(value)
    rounded = value.to_f.round(2)
    return rounded.round.to_s if (rounded - rounded.round).abs < 1e-9

    formatted = format('%.2f', rounded)
    formatted.sub(/0+\z/, '').sub(/\.\z/, '')
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
    @boards.each do |b|
      part = diagram['parts'].find { |p| p['id'] == b.id } || next
      @layout['boards'][b.id]['at'] = [normalize(part['left']), normalize(part['top'])]
    end
    @parts.each do |part|
      next if board_part?(part.id)

      source = diagram['parts'].find { |p| p['id'] == part.id } || next
      entry = { 'at' => [normalize(source['left']), normalize(source['top'])] }
      entry['rotate'] = source['rotate'] if source.key?('rotate')
      if part.on_board? && part.anchor
        x = source['left'] + part.pins.fetch(part.anchor)[0]
        y = source['top'] + part.pins.fetch(part.anchor)[1]
        hole = part.board.hole_at(x, y)
        if hole
          entry = { 'board' => part.board.id, 'hole' => hole }
        else
          warn "gen-diagram: #{part.id} съехал с сетки — посадка сохранена координатами"
        end
      end
      placements[part.id] = entry
    end
    routes = {}
    diagram['connections'].each do |a, b, _color, route|
      next if route.nil? || route.empty? || route == default_route(a, b) || (a.include?('$') || b.include?('$'))

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
