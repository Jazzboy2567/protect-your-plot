class_name Unit
extends Node2D

# One combatant (peasant, enemy, or structure). Drawn as a stick figure in _draw().
# Behaviour: find nearest enemy -> move into range (unless Hold) -> attack on cooldown.

enum Stance { AGGRESSIVE, HOLD }

var main = null                       # reference to Main (owns the unit arrays)
var team: int = 0                     # 0 = peasant, 1 = enemy
var type_id: String = "farmer"
var display_name: String = "Farmer"
var max_hp: float = 30.0
var hp: float = 30.0
var damage: float = 5.0
var attack_range: float = 6.0
var attack_cooldown: float = 1.0
var move_speed: float = 55.0
var radius: float = 7.0
var is_structure: bool = false
var stance: int = Stance.AGGRESSIVE
var body_color: Color = Color(0.78, 0.80, 0.85)
var gold_drop: int = 0
var armor: float = 0.0                 # flat damage reduction (min 1 damage taken)
var pierce: bool = false               # attacks ignore target armor
var aura: String = ""                  # "", "heal", or "haste"
var aura_range: float = 0.0
var aura_value: float = 0.0            # heal = hp/sec to allies; haste = attack-speed bonus

var target = null
var _cd: float = 0.0
var _flash: float = 0.0
var _dead: bool = false

func setup(def: Dictionary, _team: int, _main) -> void:
	main = _main
	team = _team
	type_id = def.get("id", "unit")
	display_name = def.get("name", "Unit")
	max_hp = float(def.get("hp", 30))
	hp = max_hp
	damage = float(def.get("damage", 5))
	attack_range = float(def.get("range", 6))
	attack_cooldown = float(def.get("cooldown", 1.0))
	move_speed = float(def.get("speed", 55))
	radius = float(def.get("radius", 7))
	is_structure = bool(def.get("structure", false))
	gold_drop = int(def.get("drop", 0))
	armor = float(def.get("armor", 0))
	pierce = bool(def.get("pierce", false))
	aura = def.get("aura", "")
	aura_range = float(def.get("aura_range", 0))
	aura_value = float(def.get("aura_value", 0))
	body_color = def.get("color", Color(0.78, 0.80, 0.85))
	_cd = randf() * attack_cooldown

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()

func _physics_process(delta: float) -> void:
	if _dead or is_structure or main == null:
		return
	_cd -= delta

	# Acquire / re-acquire a target.
	if target == null or not is_instance_valid(target) or target.hp <= 0.0:
		target = main.get_nearest_enemy(self)

	# Single ally pass: light separation + collect nearby aura effects.
	var sep := Vector2.ZERO
	var haste := 0.0
	var heal_rate := 0.0
	for a in main.get_allies(self):
		if a == self:
			continue
		var d: Vector2 = global_position - a.global_position
		var dl := d.length()
		var mind: float = radius + a.radius + 2.0
		if dl > 0.001 and dl < mind:
			sep += d / dl * (mind - dl)
		if a.aura != "" and dl <= a.aura_range:
			if a.aura == "haste":
				haste += a.aura_value
			elif a.aura == "heal":
				heal_rate += a.aura_value
	if sep != Vector2.ZERO:
		global_position += sep * 0.5
	if heal_rate > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + heal_rate * delta)
		queue_redraw()

	if target == null:
		return

	var to_t: Vector2 = target.global_position - global_position
	var dist := to_t.length()
	var reach: float = attack_range + radius + target.radius
	if dist <= reach:
		if _cd <= 0.0:
			_cd = attack_cooldown / (1.0 + haste)
			target.take_damage(damage * main.damage_mult(team), pierce)
	elif stance != Stance.HOLD:
		global_position += to_t / maxf(dist, 0.001) * move_speed * delta

func take_damage(amount: float, pierce_flag: bool = false) -> void:
	if _dead:
		return
	var dealt := amount if pierce_flag else maxf(1.0, amount - armor)
	hp -= dealt
	_flash = 0.12
	if main and dealt >= 3.0:
		main.spawn_float_text(global_position + Vector2(0, -radius - 4), str(int(round(dealt))), Color(1, 0.92, 0.45))
	queue_redraw()
	if hp <= 0.0:
		die()

func die() -> void:
	if _dead:
		return
	_dead = true
	if main:
		main.on_unit_died(self)
	# Fade-and-pop the corpse out (logic already removed it from the arrays).
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.18)
	t.parallel().tween_property(self, "scale", Vector2(1.5, 1.5), 0.18)
	t.tween_callback(queue_free)

func _draw() -> void:
	# HP bar
	var w := radius * 2.0
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	var bar_y := -radius - 9.0
	draw_rect(Rect2(-radius, bar_y, w, 3.0), Color(0, 0, 0, 0.5))
	var bar_col := Color(0.25, 0.9, 0.3) if team == 0 else Color(0.9, 0.3, 0.2)
	draw_rect(Rect2(-radius, bar_y, w * frac, 3.0), bar_col)

	# Hit flash: briefly wash the body toward white when struck.
	var c := body_color
	if _flash > 0.0:
		c = body_color.lerp(Color.WHITE, clampf(_flash / 0.12, 0.0, 1.0) * 0.85)

	if is_structure:
		draw_rect(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), c)
		draw_rect(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), Color(0.25, 0.16, 0.08), false, 2.0)
		return

	# Stick figure
	draw_circle(Vector2(0, -radius * 0.5), radius * 0.45, c)          # head
	draw_line(Vector2(0, -radius * 0.1), Vector2(0, radius * 0.6), c, 2.0)   # body
	draw_line(Vector2(-radius * 0.5, radius * 0.15), Vector2(radius * 0.5, radius * 0.15), c, 2.0)  # arms
	draw_line(Vector2(0, radius * 0.6), Vector2(-radius * 0.4, radius), c, 2.0)  # left leg
	draw_line(Vector2(0, radius * 0.6), Vector2(radius * 0.4, radius), c, 2.0)   # right leg
