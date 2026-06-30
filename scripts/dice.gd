extends Node
## Dice — autoload. Port of game_state.py roll_dice / roll_saving_throw helpers.
## All randomness in game logic must go through here (mirrors the Python rule:
## "Use roll_dice for all randomness — never call random directly").

var _dice_re := RegEx.new()

func _ready() -> void:
	# Format: "2d6", "3d4+5", "1d20-1"
	_dice_re.compile("^(\\d+)d(\\d+)([+-]\\d+)?$")

## Roll a dice string. advantage/disadvantage roll twice and take max/min.
func roll(dice_str: String, advantage := false, disadvantage := false) -> int:
	var s := dice_str.replace(" ", "")
	var m := _dice_re.search(s)
	if m == null:
		return 0
	var num := int(m.get_string(1))
	var sides := int(m.get_string(2))
	var mod := 0
	if m.get_string(3) != "":
		mod = int(m.get_string(3))

	if advantage and not disadvantage:
		return max(_roll_once(num, sides, mod), _roll_once(num, sides, mod))
	if disadvantage and not advantage:
		return min(_roll_once(num, sides, mod), _roll_once(num, sides, mod))
	return _roll_once(num, sides, mod)

func _roll_once(num: int, sides: int, mod: int) -> int:
	var total := mod
	for _i in range(num):
		total += randi_range(1, sides)
	return total

## Raw d20.
func d20() -> int:
	return randi_range(1, 20)

## 1d20 + stat modifier vs DC. Returns {success, roll, mod}.
func saving_throw(modifiers: Dictionary, stat_name: String, dc: int) -> Dictionary:
	var mod: int = modifiers.get(stat_name, 0)
	var r := d20()
	return {"success": (r + mod) >= dc, "roll": r, "mod": mod}
