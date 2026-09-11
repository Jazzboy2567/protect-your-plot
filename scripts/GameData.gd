class_name GameData
extends RefCounted

# Central stat tables + wave generator. Accessed statically, e.g. GameData.UNITS["peasant"].
# Flags: structure (no move/attack), armor (flat reduction), pierce (ignore armor),
# aura ("heal"/"haste"), beast (Hunter bonus), heals (targeted ally heal),
# applies_burn/applies_slow (on-hit), knockback, bonus_beast, behavior ("diver"),
# targets ("structures" = go for walls/castle), evasion (0..1 dodge chance).

const UNITS := {
	# --- Your side ---
	"peasant":    {"id":"peasant","name":"Peasant","hp":40,"damage":6,"range":7,"cooldown":1.0,"speed":55,"radius":8,"cost":10,"armor":1,"color":Color(0.80,0.82,0.86)},
	"archer":     {"id":"archer","name":"Archer","hp":24,"damage":8,"range":150,"cooldown":1.1,"speed":50,"radius":7,"cost":25,"color":Color(0.60,0.80,0.62)},
	"woodcutter": {"id":"woodcutter","name":"Woodcutter","hp":65,"damage":15,"range":9,"cooldown":1.4,"speed":45,"radius":9,"cost":35,"pierce":true,"color":Color(0.72,0.62,0.50)},
	"hunter":     {"id":"hunter","name":"Hunter","hp":30,"damage":7,"range":130,"cooldown":1.0,"speed":55,"radius":7,"cost":30,"bonus_beast":2.2,"color":Color(0.55,0.70,0.45)},
	"herbalist":  {"id":"herbalist","name":"Herbalist","hp":30,"damage":0,"range":95,"cooldown":1.3,"speed":52,"radius":8,"cost":35,"heals":true,"heal_amount":10,"color":Color(0.55,0.80,0.70)},
	"fisherman":  {"id":"fisherman","name":"Fisherman","hp":38,"damage":5,"range":9,"cooldown":1.1,"speed":55,"radius":8,"cost":30,"applies_slow":true,"color":Color(0.55,0.72,0.80)},
	"torchbearer":{"id":"torchbearer","name":"Torchbearer","hp":34,"damage":6,"range":8,"cooldown":1.0,"speed":55,"radius":8,"cost":35,"applies_burn":true,"color":Color(0.90,0.65,0.35)},
	"baker":      {"id":"baker","name":"Baker","hp":34,"damage":4,"range":7,"cooldown":1.2,"speed":52,"radius":8,"cost":30,"aura":"heal","aura_range":95,"aura_value":5,"color":Color(0.86,0.78,0.55)},
	"monk":       {"id":"monk","name":"Monk","hp":34,"damage":4,"range":7,"cooldown":1.2,"speed":52,"radius":8,"cost":35,"aura":"haste","aura_range":95,"aura_value":0.30,"color":Color(0.70,0.66,0.80)},
	# structures (you start with castle + church; walls are bought)
	"barricade":  {"id":"barricade","name":"Barricade","hp":220,"damage":0,"range":0,"cooldown":1.0,"speed":0,"radius":14,"cost":30,"structure":true,"armor":2,"color":Color(0.50,0.35,0.20)},
	"spikes":     {"id":"spikes","name":"Spike Barricade","hp":150,"damage":0,"range":0,"cooldown":1.0,"speed":0,"radius":13,"cost":40,"structure":true,"armor":1,"color":Color(0.45,0.42,0.40)},
	"palisade":   {"id":"palisade","name":"Palisade","hp":380,"damage":0,"range":0,"cooldown":1.0,"speed":0,"radius":15,"cost":45,"structure":true,"armor":4,"color":Color(0.46,0.33,0.19)},
	"stone_wall": {"id":"stone_wall","name":"Stone Wall","hp":600,"damage":0,"range":0,"cooldown":1.0,"speed":0,"radius":16,"cost":70,"structure":true,"armor":8,"color":Color(0.55,0.55,0.58)},
	"church":     {"id":"church","name":"Church","hp":300,"damage":0,"range":0,"cooldown":1.0,"speed":0,"radius":18,"cost":60,"structure":true,"armor":2,"color":Color(0.86,0.82,0.66)},
	"castle":     {"id":"castle","name":"Castle Keep","hp":900,"damage":0,"range":0,"cooldown":1.0,"speed":0,"radius":66,"cost":0,"structure":true,"armor":5,"color":Color(0.62,0.62,0.68)},

	# --- Enemies (right side) — reddish. targets defaults to your units. ---
	"sheep":       {"id":"sheep","name":"Sheep","hp":18,"damage":2,"range":6,"cooldown":1.2,"speed":45,"radius":8,"drop":3,"beast":true,"color":Color(0.90,0.90,0.90)},
	"rat":         {"id":"rat","name":"Rat","hp":12,"damage":3,"range":5,"cooldown":0.7,"speed":72,"radius":5,"drop":2,"beast":true,"color":Color(0.55,0.30,0.35)},
	"bandit":      {"id":"bandit","name":"Bandit","hp":36,"damage":7,"range":7,"cooldown":1.0,"speed":55,"radius":8,"drop":6,"armor":1,"color":Color(0.80,0.35,0.30)},
	"ram":         {"id":"ram","name":"Ram","hp":58,"damage":14,"range":8,"cooldown":1.3,"speed":85,"radius":10,"drop":9,"armor":2,"beast":true,"knockback":14,"targets":"structures","color":Color(0.85,0.55,0.30)},
	"wolf":        {"id":"wolf","name":"Wolf","hp":30,"damage":8,"range":6,"cooldown":0.8,"speed":110,"radius":7,"drop":7,"beast":true,"behavior":"diver","evasion":0.10,"color":Color(0.60,0.45,0.45)},
	"boar":        {"id":"boar","name":"Boar","hp":90,"damage":14,"range":8,"cooldown":1.4,"speed":70,"radius":11,"drop":12,"beast":true,"armor":2,"knockback":12,"color":Color(0.70,0.45,0.40)},
	"crossbowman": {"id":"crossbowman","name":"Crossbowman","hp":34,"damage":12,"range":140,"cooldown":1.6,"speed":45,"radius":8,"drop":12,"armor":1,"color":Color(0.78,0.40,0.45)},
	"knight":      {"id":"knight","name":"Knight","hp":130,"damage":18,"range":9,"cooldown":1.3,"speed":40,"radius":11,"drop":22,"armor":6,"color":Color(0.85,0.25,0.25)},
	"bear":        {"id":"bear","name":"Bear","hp":220,"damage":22,"range":10,"cooldown":1.5,"speed":45,"radius":16,"drop":30,"beast":true,"armor":2,"knockback":10,"color":Color(0.60,0.40,0.35)},
	"baron":       {"id":"baron","name":"The Baron","hp":520,"damage":24,"range":10,"cooldown":1.2,"speed":34,"radius":20,"drop":65,"armor":12,"color":Color(0.70,0.20,0.20)},
	"black_death": {"id":"black_death","name":"The Black Death","hp":650,"damage":26,"range":13,"cooldown":1.1,"speed":30,"radius":22,"drop":70,"armor":8,"color":Color(0.50,0.10,0.35)},
}

# Build the enemy wave for battle number n (1-based). Every 4th battle is a boss.
static func generate_wave(n: int) -> Array:
	var w: Array = []
	if n % 4 == 0:
		if n == 8:
			w.append("baron")
			for i in 3:
				w.append("crossbowman")
			for i in 4:
				w.append("bandit")
		else:
			w.append("black_death")
			for i in 3 + n:
				w.append("rat")
		for i in 2:
			w.append("knight")
		return w
	for i in 2 + n:
		w.append("sheep")
	for i in 1 + n:
		w.append("rat")
	for i in maxi(0, n - 1):
		w.append("bandit")
	for i in maxi(0, n - 2):
		w.append("ram")
	for i in maxi(0, n - 2):
		w.append("wolf")
	for i in maxi(0, n - 3):
		w.append("boar")
	for i in maxi(0, (n - 3) / 2):
		w.append("crossbowman")
	for i in maxi(0, (n - 2) / 2):
		w.append("knight")
	if n >= 6:
		w.append("bear")
	return w
