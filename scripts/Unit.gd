class_name Unit
extends Node2D

# One combatant (peasant, enemy, or structure). Drawn as a stick figure in _draw().
# Behaviour: find nearest enemy -> move into range (unless Hold) -> attack on cooldown.

const ENGAGE_RADIUS := 120.0          # how far a unit chases from its command point

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
var body_color: Color = Color(0.78, 0.80, 0.85)
var gold_drop: int = 0
var armor: float = 0.0                 # flat damage reduction (min 1 damage taken)
var pierce: bool = false               # attacks ignore target armor
var aura: String = ""                  # "", "heal", "haste", or "cleanse"
var aura_range: float = 0.0
var aura_value: float = 0.0            # heal = hp/sec to allies; haste = attack-speed bonus
var is_beast: bool = false
var plague_immune: bool = false
var applies_plague: bool = false
var applies_burn: bool = false
var applies_slow: bool = false
var knockback: float = 0.0
var bonus_beast: float = 1.0          # damage multiplier vs beast enemies
var behavior: String = ""             # "" or "diver" (target the backline)
var crit_chance: float = 0.0          # 0..1 chance to crit
var crit_mult: float = 1.5            # crit damage multiplier

var plague_time: float = 0.0
var plague_dps: float = 0.0
var burn_time: float = 0.0
var burn_dps: float = 0.0
var slow_time: float = 0.0
var _spread_cd: float = 0.0

var command_point: Vector2 = Vector2.ZERO   # where you've ordered this unit to hold
var selected: bool = false
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
	is_beast = bool(def.get("beast", false))
	plague_immune = bool(def.get("plague_immune", false))
	applies_plague = bool(def.get("applies_plague", false))
	applies_burn = bool(def.get("applies_burn", false))
	applies_slow = bool(def.get("applies_slow", false))
	knockback = float(def.get("knockback", 0))
	bonus_beast = float(def.get("bonus_beast", 1.0))
	behavior = def.get("behavior", "")
	body_color = def.get("color", Color(0.78, 0.80, 0.85))
	_cd = randf() * attack_cooldown

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()

func _physics_process(delta: float) -> void:
	if _dead or is_structure or main == null:
		return
	if not main.is_fighting():   # frozen during the deploy phase
		return
	_cd -= delta

	# Damage-over-time: plague spreads to nearby allies; burn does not.
	if slow_time > 0.0:
		slow_time -= delta
	var dot := false
	if plague_time > 0.0:
		plague_time -= delta
		hp -= plague_dps * delta
		dot = true
		_spread_cd -= delta
		if _spread_cd <= 0.0:
			_spread_cd = 1.0
			main.try_spread_plague(self)
	if burn_time > 0.0:
		burn_time -= delta
		hp -= burn_dps * delta
		dot = true
	if dot:
		queue_redraw()
		if hp <= 0.0:
			die()
			return

	# Acquire / re-acquire a target (divers go for your backline).
	if target == null or not is_instance_valid(target) or target.hp <= 0.0:
		target = null
		if team == 1 and behavior == "diver":
			target = main.get_backline_peasant()
		if target == null:
			target = main.get_nearest_enemy(self)

	# A wall directly ahead must be broken through first.
	if team == 1:
		var wall = main.structure_ahead(self)
		if wall != null:
			target = wall

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
			elif a.aura == "cleanse" and plague_time > 0.0:
				plague_time = 0.0
				queue_redraw()
	if sep != Vector2.ZERO:
		global_position += sep * 0.5
	if heal_rate > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + heal_rate * delta)
		queue_redraw()

	var has_t: bool = target != null and is_instance_valid(target)
	var dist: float = INF
	var reach: float = attack_range + radius
	if has_t:
		dist = global_position.distance_to(target.global_position)
		reach = attack_range + radius + target.radius

	# Attack whatever is in range, applying on-hit effects.
	if has_t and dist <= reach and _cd <= 0.0:
		_cd = attack_cooldown / (1.0 + haste)
		var dmg := damage
		if bonus_beast > 1.0 and target.is_beast:
			dmg *= bonus_beast
		var is_crit := crit_chance > 0.0 and randf() < crit_chance
		if is_crit:
			dmg *= crit_mult
		target.take_damage(dmg * main.damage_mult(team), pierce, is_crit)
		if applies_plague:
			target.infect(3.0, 4.0)
		if applies_burn:
			target.ignite(3.0, 3.0)
		if applies_slow:
			target.slow_for(1.5)
		if knockback > 0.0:
			var kb: Vector2 = target.global_position - global_position
			var kl := kb.length()
			if kl > 0.001:
				target.global_position += kb / kl * knockback

	# Move toward the goal (hold the command point; enemies advance).
	var goal = _movement_goal(has_t, dist, reach)
	if goal != null:
		var dir: Vector2 = goal - global_position
		var dl2 := dir.length()
		if dl2 > 0.001:
			var spd := move_speed * (0.5 if slow_time > 0.0 else 1.0)
			global_position += dir / dl2 * spd * delta

func _movement_goal(has_t: bool, dist: float, reach: float):
	# Enemies always advance on the nearest target.
	if team == 1:
		return target.global_position if (has_t and dist > reach) else null
	# Your units hold their command point and engage foes that come near it.
	if has_t and dist <= reach:
		return null
	if has_t and dist > reach and target.global_position.distance_to(command_point) <= ENGAGE_RADIUS:
		return target.global_position
	if global_position.distance_to(command_point) > 8.0:
		return command_point
	return null

func take_damage(amount: float, pierce_flag: bool = false, is_crit: bool = false) -> void:
	if _dead:
		return
	var dealt := amount if pierce_flag else maxf(1.0, amount - armor)
	hp -= dealt
	_flash = 0.12
	if main and dealt >= 3.0:
		var col := Color(1, 0.5, 0.15) if is_crit else Color(1, 0.92, 0.45)
		var txt := str(int(round(dealt))) + ("!" if is_crit else "")
		main.spawn_float_text(global_position + Vector2(0, -radius - 4), txt, col)
	queue_redraw()
	if hp <= 0.0:
		die()

func infect(dps: float, t: float) -> void:
	if plague_immune or _dead:
		return
	plague_dps = maxf(plague_dps, dps)
	plague_time = maxf(plague_time, t)

func ignite(dps: float, t: float) -> void:
	if _dead:
		return
	burn_dps = maxf(burn_dps, dps)
	burn_time = maxf(burn_time, t)

func slow_for(t: float) -> void:
	slow_time = maxf(slow_time, t)

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
	elif plague_time > 0.0:
		c = body_color.lerp(Color(0.3, 0.8, 0.2), 0.5)   # sickly green when infected

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

	# Selection ring when this unit is currently selected.
	if selected:
		draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 20, Color(1, 1, 0.4, 0.9), 1.6)
