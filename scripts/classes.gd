extends Node
## Classes — autoload. Port of backend/classes.py CLASSES dict + D&D metadata.
## Each entry mirrors the CharacterClass fields plus stat_priority / action_type.

const CLASS_DATA := {
	"warrior": {
		"name": "Warrior", "max_health": 150, "max_mana": 30, "symbol": "W",
		"color": "#ff4444", "description": "High health, melee.", "weapon": "Sword",
		"attack_range": 1.5, "attack_damage": 30, "ability_name": "Whirlwind",
		"ability_cost": 15, "ability_range": 2.5,
		"ability_desc": "Hit all surrounding enemies.", "damage_dice": "2d8",
		"stat_priority": ["STR", "CON", "DEX", "WIS", "CHA", "INT"],
		"action_type": "action", "sprite": "warrior",
	},
	"mage": {
		"name": "Mage", "max_health": 80, "max_mana": 100, "symbol": "M",
		"color": "#44ccff", "description": "Spellcaster.", "weapon": "Fireball",
		"attack_range": 4.5, "attack_damage": 40, "ability_name": "Frost Nova",
		"ability_cost": 30, "ability_range": 4.5,
		"ability_desc": "Freeze target for 1 turn and deal damage.", "damage_dice": "4d4",
		"stat_priority": ["INT", "DEX", "CON", "WIS", "CHA", "STR"],
		"action_type": "action", "sprite": "mage",
	},
	"rogue": {
		"name": "Rogue", "max_health": 100, "max_mana": 60, "symbol": "R",
		"color": "#88ff44", "description": "Nimble attacker.", "weapon": "Bow",
		"attack_range": 3.5, "attack_damage": 25, "ability_name": "Shadow Step",
		"ability_cost": 25, "ability_range": 5.0,
		"ability_desc": "Teleport next to target and backstab.", "damage_dice": "3d6",
		"stat_priority": ["DEX", "INT", "CON", "CHA", "WIS", "STR"],
		"action_type": "bonus", "sprite": "rogue",
	},
	"cleric": {
		"name": "Cleric", "max_health": 120, "max_mana": 150, "symbol": "C",
		"color": "#fbbf24", "description": "Healer and protector.", "weapon": "Mace",
		"attack_range": 1.5, "attack_damage": 20, "ability_name": "Holy Resonance",
		"ability_cost": 40, "ability_range": 3.5,
		"ability_desc": "AoE heal for all party members.", "damage_dice": "2d6",
		"stat_priority": ["WIS", "CON", "STR", "CHA", "INT", "DEX"],
		"action_type": "action", "sprite": "cleric",
	},
	"ranger": {
		"name": "Ranger", "max_health": 90, "max_mana": 80, "symbol": "H",
		"color": "#22c55e", "description": "Sniper and tracker.", "weapon": "Longbow",
		"attack_range": 6.0, "attack_damage": 35, "ability_name": "Volley",
		"ability_cost": 30, "ability_range": 6.0,
		"ability_desc": "Fire multiple arrows in an area.", "damage_dice": "3d6",
		"stat_priority": ["DEX", "WIS", "CON", "STR", "INT", "CHA"],
		"action_type": "action", "sprite": "ranger",
	},
}

const CLASS_KEYS := ["warrior", "mage", "rogue", "cleric", "ranger"]

## Returns the class data dict, defaulting to warrior (mirrors get_class()).
func get_class_data(key: String) -> Dictionary:
	return CLASS_DATA.get(key.to_lower(), CLASS_DATA["warrior"])
