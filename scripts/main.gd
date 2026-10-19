extends Node2D

const TILE := 32
const COLS := 13
const ROWS := 11
const BOARD_X := 32
const BOARD_Y := 76
const MOVE_DELAY := 0.12
const BOMB_FUSE := 2.5
const BLAST_TIME := 0.60
const PLAYER_START := Vector2i(1, 1)
const TOTAL_LEVELS := 10
const MAX_BLAST_RANGE := 2

var walls: Array = []
var blocks: Array = []
var bombs: Array = []
var blasts: Array = []
var enemies: Array[Vector2i] = []
var powerups: Array = []
var exit_cell := Vector2i(11, 9)
var level := 1
var lives := 3
var blast_range := 1
var level_start_blast_range := 1
var level_start_score := 0
var player := PLAYER_START
var player_facing := Vector2i.RIGHT
var game_state := "title"
var has_saved_game := false
var sound_enabled := true
var move_clock := 0.0
var enemy_clock := 0.0
var held_touch_dir := Vector2i.ZERO
var sound_player: AudioStreamPlayer
var sound_cache: Dictionary = {}
var score := 0
var message := "A CLASSIC MAZE ADVENTURE"

func _ready() -> void:
	randomize()
	sound_player = AudioStreamPlayer.new()
	add_child(sound_player)
	_build_sounds()
	queue_redraw()

func _process(delta: float) -> void:
	if game_state != "playing":
		return

	move_clock += delta
	enemy_clock += delta

	var direction := _get_held_direction()
	if direction != Vector2i.ZERO and move_clock >= MOVE_DELAY:
		move_clock = 0.0
		_try_move(direction)

	for i in range(bombs.size() - 1, -1, -1):
		var remaining_fuse: float = float(bombs[i].get("fuse", 0.0)) - delta
		bombs[i]["fuse"] = remaining_fuse
		if remaining_fuse <= 0.0:
			_explode(i)

	for i in range(blasts.size() - 1, -1, -1):
		blasts[i].time -= delta
		if blasts[i].time <= 0.0:
			blasts.remove_at(i)

	if enemy_clock >= maxf(0.58, 0.88 - float(level - 1) * 0.025):
		enemy_clock = 0.0
		_move_enemies()

	queue_redraw()

func _get_held_direction() -> Vector2i:
	return held_touch_dir

func _input(event: InputEvent) -> void:
	# Android system Back key only; gameplay itself uses touchscreen controls.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_BACK:
		if game_state == "playing":
			_pause_game()
		elif game_state == "paused":
			game_state = "title"
			queue_redraw()
		else:
			game_state = "title"
			queue_redraw()
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_pointer(event.position, true)
		else:
			held_touch_dir = Vector2i.ZERO
	elif event is InputEventScreenDrag:
		if game_state == "playing":
			held_touch_dir = _direction_at(event.position)
func _handle_pointer(pos: Vector2, is_touch: bool) -> void:
	if game_state != "playing":
		_handle_menu_pointer(pos)
		return

	if Rect2(414, 8, 52, 48).has_point(pos):
		_pause_game()
		return
	if Rect2(330, 510, 110, 100).has_point(pos):
		_place_bomb()
		return

	var direction := _direction_at(pos)
	if direction != Vector2i.ZERO:
		held_touch_dir = direction
		# Move once immediately. Holding the pad repeats only after the normal delay.
		move_clock = 0.0
		_try_move(direction)
	elif pos.y < 70 and pos.x < 100:
		_pause_game()

func _direction_at(pos: Vector2) -> Vector2i:
	# Forgiving touch pad: anywhere inside the large pad zone selects the nearest direction.
	if not Rect2(18, 456, 250, 184).has_point(pos):
		return Vector2i.ZERO
	var center := Vector2(134, 554)
	var offset := pos - center
	if absf(offset.x) > absf(offset.y):
		return Vector2i.RIGHT if offset.x >= 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if offset.y >= 0.0 else Vector2i.UP

func _handle_menu_pointer(pos: Vector2) -> void:
	if game_state == "title":
		if Rect2(120, 306, 240, 50).has_point(pos):
			_start_game()
		elif Rect2(120, 366, 240, 50).has_point(pos):
			if has_saved_game:
				game_state = "playing"
				_play_sound("select")
		elif Rect2(120, 426, 240, 50).has_point(pos):
			_toggle_sound()
		elif Rect2(120, 486, 240, 50).has_point(pos):
			get_tree().quit()
	elif game_state == "paused":
		if Rect2(120, 286, 240, 48).has_point(pos):
			game_state = "playing"
			_play_sound("select")
		elif Rect2(120, 344, 240, 48).has_point(pos):
			_start_game()
		elif Rect2(120, 402, 240, 48).has_point(pos):
			game_state = "title"
			_play_sound("select")
		elif Rect2(120, 460, 240, 48).has_point(pos):
			_toggle_sound()
	elif game_state == "won" or game_state == "lost":
		if Rect2(120, 306, 240, 50).has_point(pos):
			_start_game()
		elif Rect2(120, 366, 240, 50).has_point(pos):
			game_state = "title"
			_play_sound("select")
		elif Rect2(120, 426, 240, 50).has_point(pos):
			_toggle_sound()
	queue_redraw()

func _start_game() -> void:
	level = 1
	lives = 3
	blast_range = 1
	score = 0
	_build_level(true)

func _build_level(new_level: bool = false) -> void:
	if new_level:
		level_start_blast_range = blast_range
		level_start_score = score
	else:
		blast_range = level_start_blast_range
		score = level_start_score
	walls.clear()
	blocks.clear()
	bombs.clear()
	blasts.clear()
	enemies.clear()
	player = PLAYER_START
	player_facing = Vector2i.RIGHT
	move_clock = 0.0
	enemy_clock = 0.0
	held_touch_dir = Vector2i.ZERO
	powerups.clear()
	message = "LIVES %d: DEFEAT ENEMIES" % lives
	for y in range(ROWS):
		var wall_row: Array = []
		var block_row: Array = []
		for x in range(COLS):
			var solid := x == 0 or y == 0 or x == COLS - 1 or y == ROWS - 1 or (x % 2 == 0 and y % 2 == 0)
			wall_row.append(solid)
			var near_start := x <= 2 and y <= 2
			var near_exit := x >= COLS - 3 and y >= ROWS - 3
			var block := not solid and not near_start and not near_exit and randf() < 0.30
			block_row.append(block)
		walls.append(wall_row)
		blocks.append(block_row)
	# The exit is hidden under a destructible block until revealed.
	exit_cell = Vector2i(COLS - 2, ROWS - 2)
	blocks[exit_cell.y][exit_cell.x] = true
	var spawn_candidates: Array[Vector2i] = [Vector2i(11, 1), Vector2i(9, 1), Vector2i(11, 5), Vector2i(7, 7), Vector2i(9, 9), Vector2i(5, 9), Vector2i(11, 7)]
	var enemy_count := mini(2 + int((level - 1) / 2), 6)
	for spawn in spawn_candidates:
		if enemies.size() >= enemy_count:
			break
		if not walls[spawn.y][spawn.x]:
			blocks[spawn.y][spawn.x] = false
			if not enemies.has(spawn) and spawn != exit_cell:
				enemies.append(spawn)
	has_saved_game = true
	game_state = "playing"
	_play_sound("select")
	queue_redraw()

func _pause_game() -> void:
	if game_state == "playing":
		game_state = "paused"
		held_touch_dir = Vector2i.ZERO
		_play_sound("select")
		queue_redraw()

func _try_move(dir: Vector2i) -> void:
	if game_state != "playing":
		return
	player_facing = dir
	var target := player + dir
	if _is_open(target):
		player = target
		_play_sound("move")
		_collect_powerup(player)
		if enemies.has(player):
			_handle_player_death("CAUGHT!")
		elif player == exit_cell and enemies.is_empty():
			_advance_level()
	queue_redraw()

func _is_open(p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= COLS or p.y >= ROWS:
		return false
	if walls[p.y][p.x] or blocks[p.y][p.x]:
		return false
	for bomb in bombs:
		if bomb.cell == p:
			return false
	return true

func _place_bomb() -> void:
	if game_state != "playing" or bombs.size() >= 1:
		return
	for bomb in bombs:
		if bomb.cell == player:
			return
	bombs.append({"cell": player, "fuse": BOMB_FUSE})
	_play_sound("plant")
	queue_redraw()

func _explode(index: int) -> void:
	var cell: Vector2i = bombs[index].cell
	bombs.remove_at(index)
	# Always include the bomb tile so every detonation has a visible centre.
	var affected: Array[Vector2i] = [cell]
	# Classic Bomberman: every bomb blasts outward in all four directions.
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for dir in directions:
		for distance in range(1, blast_range + 1):
			var p: Vector2i = cell + dir * distance
			if p.x < 0 or p.y < 0 or p.x >= COLS or p.y >= ROWS or walls[p.y][p.x]:
				break
			affected.append(p)
			if blocks[p.y][p.x]:
				blocks[p.y][p.x] = false
				_drop_powerup(p)
				score += 10
				break
	_play_sound("explosion")
	for cell_pos in affected:
		if cell_pos == player:
			_handle_player_death("BOOM!")
		if enemies.has(cell_pos):
			enemies.erase(cell_pos)
			score += 100
	blasts.append({"cells": affected, "time": BLAST_TIME})
	if enemies.is_empty() and game_state == "playing":
		message = "EXIT REVEALED! FIND THE DOOR"
	queue_redraw()

func _drop_powerup(cell: Vector2i) -> void:
	if cell == exit_cell:
		return
	if randf() < 0.20:
		powerups.append({"cell": cell, "kind": "range"})

func _collect_powerup(cell: Vector2i) -> void:
	for i in range(powerups.size() - 1, -1, -1):
		if powerups[i].cell != cell:
			continue
		var kind: String = powerups[i].kind
		blast_range = mini(blast_range + 1, MAX_BLAST_RANGE)
		message = "BLAST RANGE: %d" % blast_range
		_play_sound("select")
		powerups.remove_at(i)
		break

func _advance_level() -> void:
	if level >= TOTAL_LEVELS:
		_end_game("won", "ALL 10 LEVELS CLEARED!")
		return
	level += 1
	lives = 3
	_build_level(true)

func _move_enemies() -> void:
	for i in range(enemies.size()):
		var enemy: Vector2i = enemies[i]
		var next_step := Vector2i.ZERO
		if _enemy_can_see_player(enemy):
			next_step = _get_chase_step(enemy)
		if next_step == Vector2i.ZERO:
			var choices: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
			choices.shuffle()
			for direction in choices:
				var target: Vector2i = enemy + direction
				if target == player:
					_end_game("lost", "CAUGHT!")
					return
				if _is_open(target) and not enemies.has(target):
					next_step = target
					break
		if next_step != Vector2i.ZERO:
			if next_step == player:
				_end_game("lost", "CAUGHT!")
				return
			enemies[i] = next_step

func _enemy_can_see_player(enemy: Vector2i) -> bool:
	# Enemies spot the player along a clear horizontal or vertical corridor.
	if enemy.x == player.x:
		var step_y := 1 if player.y > enemy.y else -1
		for y in range(enemy.y + step_y, player.y, step_y):
			if walls[y][enemy.x] or blocks[y][enemy.x]:
				return false
		return true
	if enemy.y == player.y:
		var step_x := 1 if player.x > enemy.x else -1
		for x in range(enemy.x + step_x, player.x, step_x):
			if walls[enemy.y][x] or blocks[enemy.y][x]:
				return false
		return true
	return false

func _get_chase_step(start: Vector2i) -> Vector2i:
	# Breadth-first search finds a shortest walkable route toward the player.
	var queue: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: start}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var found := false
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == player:
			found = true
			break
		for direction in directions:
			var target: Vector2i = current + direction
			if came_from.has(target):
				continue
			if target != player and (not _is_open(target) or enemies.has(target)):
				continue
			if target == player and enemies.has(target):
				continue
			came_from[target] = current
			queue.append(target)
	if not found:
		return Vector2i.ZERO
	var step := player
	while came_from[step] != start:
		step = came_from[step]
	return step


func _handle_player_death(reason: String) -> void:
	lives -= 1
	if lives > 0:
		message = "LIFE LOST: %d LEFT" % lives
		_build_level(false)
		return
	_end_game("lost", "%s - GAME OVER" % reason)

func _end_game(result: String, text_value: String) -> void:
	game_state = result
	message = text_value
	held_touch_dir = Vector2i.ZERO
	_play_sound("win" if result == "won" else "lose")
	queue_redraw()

func _build_sounds() -> void:
	sound_cache["move"] = _make_sound("move")
	sound_cache["plant"] = _make_sound("plant")
	sound_cache["explosion"] = _make_sound("explosion")
	sound_cache["select"] = _make_sound("select")
	sound_cache["win"] = _make_sound("win")
	sound_cache["lose"] = _make_sound("lose")

func _make_sound(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var duration := 0.12
	if kind == "plant":
		duration = 0.24
	elif kind == "explosion":
		duration = 0.52
	elif kind == "win":
		duration = 0.55
	elif kind == "lose":
		duration = 0.42
	elif kind == "select":
		duration = 0.09
	var count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / float(rate)
		var envelope := pow(maxf(0.0, 1.0 - t / duration), 2.0)
		var sample := 0.0
		if kind == "explosion":
			var low_boom := sin(TAU * (68.0 - 28.0 * t / duration) * t)
			sample = (randf_range(-0.8, 0.8) * 0.72 + low_boom * 0.28) * envelope
		elif kind == "plant":
			sample = sin(TAU * (240.0 + 520.0 * t / duration) * t) * envelope * 0.55
		elif kind == "move":
			sample = sin(TAU * 620.0 * t) * envelope * 0.20
		elif kind == "select":
			sample = sin(TAU * 880.0 * t) * envelope * 0.22
		elif kind == "win":
			var frequency := 440.0 if t < duration * 0.33 else (554.0 if t < duration * 0.66 else 659.0)
			sample = sin(TAU * frequency * t) * envelope * 0.35
		else:
			sample = sin(TAU * (300.0 - 210.0 * t / duration) * t) * envelope * 0.35
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream

func _play_sound(kind: String) -> void:
	if not sound_enabled or not is_instance_valid(sound_player):
		return
	var stream: AudioStreamWAV = sound_cache.get(kind)
	if stream == null:
		return
	sound_player.stop()
	sound_player.stream = stream
	sound_player.play()

func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	if not sound_enabled:
		sound_player.stop()
	else:
		_play_sound("select")
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 640), Color("#101827"))
	_draw_header()
	if game_state == "title":
		_draw_title()
	elif game_state == "playing":
		_draw_board()
		_draw_controls()
	elif game_state == "paused":
		_draw_board()
		_draw_controls()
		_draw_overlay("PAUSED", ["RESUME", "RESTART", "MAIN MENU", _sound_label()], [286, 344, 402, 460])
	elif game_state == "won":
		_draw_board()
		_draw_overlay("YOU WIN!", ["PLAY AGAIN", "MAIN MENU", _sound_label()], [306, 366, 426])
	elif game_state == "lost":
		_draw_board()
		_draw_overlay(message, ["TRY AGAIN", "MAIN MENU", _sound_label()], [306, 366, 426])

func _draw_header() -> void:
	draw_rect(Rect2(0, 0, 480, 66), Color("#17283a"))
	draw_string(ThemeDB.fallback_font, Vector2(20, 30), "BOMBERMAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("#ffe66d"))
	if game_state == "playing" or game_state == "paused" or game_state == "won" or game_state == "lost":
		draw_string(ThemeDB.fallback_font, Vector2(20, 52), "LEVEL %d/10" % level, HORIZONTAL_ALIGNMENT_LEFT, 220, 11, Color("#a9c6d4"))
		draw_string(ThemeDB.fallback_font, Vector2(300, 34), "SCORE %04d" % score, HORIZONTAL_ALIGNMENT_LEFT, 105, 12, Color("#ffffff"))
		for i in range(3):
			_draw_life_heart(Vector2(350 + i * 23, 51), i < lives)
		draw_rect(Rect2(414, 8, 52, 48), Color("#254454"))
		draw_rect(Rect2(418, 12, 44, 40), Color("#347f9c"))
		draw_string(ThemeDB.fallback_font, Vector2(429, 38), "II", HORIZONTAL_ALIGNMENT_LEFT, 30, 19, Color.WHITE)


func _draw_life_heart(center: Vector2, is_alive: bool) -> void:
	# Tiny shaded hearts sit beneath the score; lost lives remain dimmed.
	var heart_color := Color("#f04462") if is_alive else Color("#465362")
	var shadow_color := Color("#241b2a") if is_alive else Color("#303b48")
	for offset in [Vector2(0, 1)]:
		draw_circle(center + offset + Vector2(-4, -2), 4.5, shadow_color)
		draw_circle(center + offset + Vector2(4, -2), 4.5, shadow_color)
		draw_colored_polygon(PackedVector2Array([
			center + offset + Vector2(-8, -1),
			center + offset + Vector2(8, -1),
			center + offset + Vector2(0, 8)
		]), shadow_color)
	draw_circle(center + Vector2(-4, -3), 4, heart_color)
	draw_circle(center + Vector2(4, -3), 4, heart_color)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-8, -2),
		center + Vector2(8, -2),
		center + Vector2(0, 7)
	]), heart_color)

func _draw_title() -> void:
	draw_rect(Rect2(24, 94, 432, 176), Color("#17283a"))
	draw_rect(Rect2(30, 100, 420, 164), Color("#20394a"))
	_draw_mini_character(Vector2(115, 155), Color("#ffd34e"))
	_draw_mini_bomb(Vector2(240, 158))
	_draw_mini_character(Vector2(365, 155), Color("#d94b55"))
	draw_string(ThemeDB.fallback_font, Vector2(60, 215), "BOMBS. BLOCKS. SURVIVE.", HORIZONTAL_ALIGNMENT_LEFT, 360, 16, Color("#f4f7fa"))
	draw_string(ThemeDB.fallback_font, Vector2(76, 246), "DEFEAT THE ENEMIES TO WIN", HORIZONTAL_ALIGNMENT_LEFT, 330, 12, Color("#a9c6d4"))
	_draw_button(Rect2(120, 306, 240, 50), "PLAY", true)
	_draw_button(Rect2(120, 366, 240, 50), "RESUME" if has_saved_game else "RESUME (NOT STARTED)", has_saved_game)
	_draw_button(Rect2(120, 426, 240, 50), _sound_label(), false)
	_draw_button(Rect2(120, 486, 240, 50), "EXIT GAME", false)
	draw_string(ThemeDB.fallback_font, Vector2(56, 556), "MOVE: TAP OR HOLD THE D-PAD", HORIZONTAL_ALIGNMENT_LEFT, 380, 13, Color("#a9c6d4"))
	draw_string(ThemeDB.fallback_font, Vector2(56, 578), "BOMB: TAP THE BOMB BUTTON", HORIZONTAL_ALIGNMENT_LEFT, 380, 13, Color("#a9c6d4"))

func _draw_board() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(32, 70), message, HORIZONTAL_ALIGNMENT_LEFT, 430, 10, Color("#f4f7fa"))
	for y in range(ROWS):
		for x in range(COLS):
			var rect := Rect2(BOARD_X + x * TILE, BOARD_Y + y * TILE, TILE, TILE)
			if walls[y][x]:
				draw_rect(rect, Color("#245b77"))
				draw_rect(rect.grow(-4), Color("#347f9c"))
				draw_rect(Rect2(rect.position + Vector2(5, 5), Vector2(7, 4)), Color("#69b7c9"))
				draw_rect(Rect2(rect.position + Vector2(19, 19), Vector2(7, 4)), Color("#245b77"))
			else:
				draw_rect(rect, Color("#20394a"))
				draw_rect(Rect2(rect.position + Vector2(1, 1), Vector2(30, 30)), Color("#254454"))
				if blocks[y][x]:
					draw_rect(rect.grow(-3), Color("#b96d42"))
					draw_rect(Rect2(rect.position + Vector2(4, 5), Vector2(10, 5)), Color("#e6a05d"))
					draw_rect(Rect2(rect.position + Vector2(17, 19), Vector2(10, 5)), Color("#8b4d39"))
					draw_line(rect.position + Vector2(16, 4), rect.position + Vector2(16, 27), Color("#8b4d39"), 2)
	for powerup in powerups:
		var pc := _center(powerup.cell)
		draw_rect(Rect2(pc + Vector2(-9, -9), Vector2(18, 18)), Color("#54d6ff"))
		draw_string(ThemeDB.fallback_font, pc + Vector2(-5, 5), "R", HORIZONTAL_ALIGNMENT_LEFT, 12, 13, Color("#102030"))
	if blocks[exit_cell.y][exit_cell.x] == false and enemies.is_empty():
		var door_rect := Rect2(BOARD_X + exit_cell.x * TILE + 5, BOARD_Y + exit_cell.y * TILE + 3, 22, 27)
		draw_rect(door_rect, Color("#f5d76e"))
		draw_rect(door_rect.grow(-4), Color("#7b5428"))
		draw_circle(door_rect.position + Vector2(16, 14), 2, Color("#ffe66d"))
	for bomb in bombs:
		var center := _center(bomb.cell)
		draw_circle(center, 11, Color("#15171d"))
		draw_circle(center + Vector2(-3, -4), 3, Color("#c6c9cf"))
		draw_line(center + Vector2(5, -8), center + Vector2(10, -14), Color("#ffcb5c"), 3)
		draw_circle(center + Vector2(11, -14), 2, Color("#ff6b35"))
	for blast in blasts:
		for cell in blast.cells:
			var rect := Rect2(BOARD_X + cell.x * TILE + 2, BOARD_Y + cell.y * TILE + 2, TILE - 4, TILE - 4)
			draw_rect(rect, Color("#ff8c26"))
			draw_rect(rect.grow(-7), Color("#ffd34e"))
			draw_rect(rect.grow(-13), Color("#fff2a6"))
	for enemy in enemies:
		_draw_enemy(_center(enemy))
	_draw_player()

func _draw_controls() -> void:
	# Large, forgiving D-pad background with broad directional zones.
	draw_rect(Rect2(18, 456, 250, 184), Color("#17283a"))
	draw_rect(Rect2(24, 462, 238, 172), Color("#20394a"))
	_draw_button(Rect2(38, 532, 82, 56), "<", false)
	_draw_button(Rect2(148, 532, 82, 56), ">", false)
	_draw_button(Rect2(92, 474, 82, 56), "^", false)
	_draw_button(Rect2(92, 584, 82, 56), "v", false)
	_draw_button(Rect2(330, 510, 110, 100), "BOMB", true)
	draw_string(ThemeDB.fallback_font, Vector2(34, 496), "MOVE", HORIZONTAL_ALIGNMENT_LEFT, 80, 10, Color("#a9c6d4"))
	draw_string(ThemeDB.fallback_font, Vector2(350, 626), "TAP TO PLANT", HORIZONTAL_ALIGNMENT_LEFT, 100, 10, Color("#a9c6d4"))

func _draw_overlay(title_text: String, labels: Array, y_positions: Array) -> void:
	draw_rect(Rect2(34, 200, 412, 360), Color(0.03, 0.06, 0.10, 0.96))
	draw_rect(Rect2(40, 206, 400, 348), Color("#17283a"))
	draw_string(ThemeDB.fallback_font, Vector2(65, 258), title_text, HORIZONTAL_ALIGNMENT_LEFT, 350, 25, Color("#ffe66d"))
	for i in range(labels.size()):
		_draw_button(Rect2(120, y_positions[i], 240, 48), str(labels[i]), i == 0)

func _draw_button(rect: Rect2, label: String, highlighted: bool) -> void:
	draw_rect(rect, Color("#b96d42") if highlighted else Color("#254454"))
	draw_rect(rect.grow(-3), Color("#e6a05d") if highlighted else Color("#347f9c"))
	var font_size := 14 if label.length() < 16 else 10
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 12, rect.position.y + rect.size.y * 0.62), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 24, font_size, Color("#ffffff"))

func _draw_player() -> void:
	var r := Rect2(BOARD_X + player.x * TILE + 5, BOARD_Y + player.y * TILE + 4, 22, 24)
	draw_rect(r, Color("#ffd34e"))
	draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(16, 8)), Color("#f8f1d0"))
	draw_rect(Rect2(r.position + Vector2(5, 6), Vector2(3, 4)), Color("#18212d"))
	draw_rect(Rect2(r.position + Vector2(14, 6), Vector2(3, 4)), Color("#18212d"))
	draw_rect(Rect2(r.position + Vector2(4, 17), Vector2(5, 5)), Color("#e78c36"))
	draw_rect(Rect2(r.position + Vector2(13, 17), Vector2(5, 5)), Color("#e78c36"))

func _draw_enemy(center: Vector2) -> void:
	# Give the enemy a small demon-like silhouette instead of a cute round face.
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-8, -7), center + Vector2(-12, -17),
		center + Vector2(-2, -12), center + Vector2(2, -12),
		center + Vector2(12, -17), center + Vector2(8, -6)
	]), Color("#641d2b"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-11, 1), center + Vector2(-16, -2),
		center + Vector2(-11, -6), center + Vector2(-9, 5)
	]), Color("#8f2637"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(11, 1), center + Vector2(16, -2),
		center + Vector2(11, -6), center + Vector2(9, 5)
	]), Color("#8f2637"))
	draw_circle(center, 12, Color("#a52d40"))
	draw_circle(center + Vector2(0, 3), 9, Color("#7c1e30"))
	# Narrow, slanted eyes and heavy brows make the expression look hostile.
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-9, -5), center + Vector2(-2, -3),
		center + Vector2(-3, 0), center + Vector2(-9, -1)
	]), Color("#ffd34e"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(9, -5), center + Vector2(2, -3),
		center + Vector2(3, 0), center + Vector2(9, -1)
	]), Color("#ffd34e"))
	draw_line(center + Vector2(-10, -8), center + Vector2(-2, -4), Color("#32101b"), 3)
	draw_line(center + Vector2(10, -8), center + Vector2(2, -4), Color("#32101b"), 3)
	draw_line(center + Vector2(-5, -3), center + Vector2(-5, -1), Color("#32101b"), 2)
	draw_line(center + Vector2(5, -3), center + Vector2(5, -1), Color("#32101b"), 2)
	# Jagged dark mouth with two sharp fangs.
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-7, 4), center + Vector2(-3, 5),
		center + Vector2(0, 4), center + Vector2(3, 5),
		center + Vector2(7, 4), center + Vector2(5, 9),
		center + Vector2(-5, 9)
	]), Color("#210b13"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-4, 5), center + Vector2(-1, 5),
		center + Vector2(-3, 8)
	]), Color("#f3e8d7"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(2, 5), center + Vector2(5, 5),
		center + Vector2(4, 8)
	]), Color("#f3e8d7"))
	draw_line(center + Vector2(-7, 11), center + Vector2(7, 11), Color("#4a1424"), 2)

func _draw_mini_character(center: Vector2, tint: Color) -> void:
	draw_rect(Rect2(center + Vector2(-17, -18), Vector2(34, 36)), tint)
	draw_rect(Rect2(center + Vector2(-12, -12), Vector2(24, 13)), Color("#f8f1d0"))
	draw_rect(Rect2(center + Vector2(-8, -8), Vector2(4, 6)), Color("#18212d"))
	draw_rect(Rect2(center + Vector2(4, -8), Vector2(4, 6)), Color("#18212d"))
	draw_rect(Rect2(center + Vector2(-12, 9), Vector2(8, 7)), Color("#e78c36"))
	draw_rect(Rect2(center + Vector2(4, 9), Vector2(8, 7)), Color("#e78c36"))

func _draw_mini_bomb(center: Vector2) -> void:
	draw_circle(center, 25, Color("#090d14"))
	draw_circle(center + Vector2(-7, -8), 7, Color("#c6c9cf"))
	draw_line(center + Vector2(9, -19), center + Vector2(18, -29), Color("#ffcb5c"), 4)
	draw_circle(center + Vector2(19, -30), 4, Color("#ff6b35"))

func _center(cell: Vector2i) -> Vector2:
	return Vector2(BOARD_X + cell.x * TILE + TILE / 2, BOARD_Y + cell.y * TILE + TILE / 2)

func _sound_label() -> String:
	return "SOUND: ON" if sound_enabled else "SOUND: OFF"
