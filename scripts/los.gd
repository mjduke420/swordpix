extends RefCounted
## Pure line-of-sight helpers (Bresenham raycast fog of war). Preloaded and
## instantiated by callers (game.gd render + the headless test) — calling
## instance methods on a `.new()` is version-robust, unlike static-via-preload
## (broken in Godot 4.7) or class_name globals (absent in headless runs).

# Tiles that block vision (walls, trees, rocks, stalagmites).
const SIGHT_BLOCKERS := ["#", "T", "*", "^"]


func blocks_sight(map: Array, x: int, y: int) -> bool:
	if y < 0 or y >= map.size() or x < 0 or x >= map[y].size():
		return true
	return map[y][x] in SIGHT_BLOCKERS


## Tiles visible from (px, py) within radius. Rays stop at the first blocker,
## but the blocker tile itself is marked visible (you see the wall/tree).
func compute_visible(map: Array, px: int, py: int, radius: int) -> Dictionary:
	var vis := {}
	vis[Vector2i(px, py)] = true
	for ty in range(py - radius, py + radius + 1):
		for tx in range(px - radius, px + radius + 1):
			if Vector2(tx, ty).distance_to(Vector2(px, py)) > radius:
				continue
			var cells := bresenham(px, py, tx, ty)
			for i in range(cells.size()):
				var c: Vector2i = cells[i]
				vis[c] = true
				if i > 0 and blocks_sight(map, c.x, c.y):
					break
	return vis


func bresenham(x0: int, y0: int, x1: int, y1: int) -> Array:
	var cells: Array = []
	var dx: int = abs(x1 - x0)
	var dy: int = -abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var cx := x0
	var cy := y0
	while true:
		cells.append(Vector2i(cx, cy))
		if cx == x1 and cy == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			cx += sx
		if e2 <= dx:
			err += dx
			cy += sy
	return cells
