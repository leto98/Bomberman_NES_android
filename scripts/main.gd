extends Node2D

const TILE := 32
const COLS := 13
const ROWS := 11
const BOARD_X := 32
const BOARD_Y := 74
const MOVE_DELAY := 0.14
const BOMB_FUSE := 1.35
const BLAST_TIME := 0.38

var walls: Array = []
var blocks: Array = []
var bombs: Array = []
var blasts: Array = []
var enemies: Array[Vector2i] = []
var player := Vector2i(1, 1)
var move_clock := 0.0
var enemy_clock := 0.0
var game_over := false
var message := "CLEAR THE MAZE!"

func _ready() -> void:
	_start_game()

func _start_game() -> void:
	walls.clear()
	blocks.clear()
	bombs.clear()
	blasts.clear()
	enemies.clear()
	player = Vector2i(1, 1)
	game_over = false
	message = "CLEAR THE MAZE!"
	for y in range(ROWS):
		var wall_row: Array = []
		var block_row: Array = []
		for x in range(COLS):
			var solid := x == 0 or y == 0 or x == COLS - 1 or y == ROWS - 1 or (x % 2 == 0 and y % 2 == 0)
			wall_row.append(solid)
			var near_start := x <= 2 and y <= 2
			var block := not solid and not near_start and randf() < 0.34
			block_row.append(block)
		walls.append(wall_row)
		blocks.append(block_row)
	enemies = [Vector2i(11, 1), Vector2i(11, 9), Vector2i(7, 7)]
	for e in enemies:
		blocks[e.y][e.x] = false
	queue_redraw()

func _process(delta: float) -> void:
	if game_over:
		return
	move_clock += delta
	enemy_clock += delta
	for i in range(bombs.size() - 1, -1, -1):
		bombs[i].fuse -= delta
		if bombs[i].fuse <= 0.0:
			_explode(i)
	for i in range(blasts.size() - 1, -1, -1):
		blasts[i].time -= delta
		if blasts[i].time <= 0.0:
			blasts.remove_at(i)
	if enemy_clock >= 0.85:
		enemy_clock = 0.0
		_move_enemies()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and game_over:
			_start_game()
			return
		if event.keycode == KEY_SPACE:
			_place_bomb()
		elif event.keycode in [KEY_UP, KEY_W]:
			_try_move(Vector2i(0, -1))
		elif event.keycode in [KEY_DOWN, KEY_S]:
			_try_move(Vector2i(0, 1))
		elif event.keycode in [KEY_LEFT, KEY_A]:
			_try_move(Vector2i(-1, 0))
		elif event.keycode in [KEY_RIGHT, KEY_D]:
			_try_move(Vector2i(1, 0))
	elif event is InputEventScreenTouch and event.pressed:
		_handle_touch(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(event.position)

func _handle_touch(pos: Vector2) -> void:
	if game_over:
		_start_game()
		return
	if pos.y < 480:
		return
	if pos.x < 112:
		_try_move(Vector2i(-1, 0))
	elif pos.x < 224:
		_try_move(Vector2i(0, 1))
	elif pos.x < 336:
		_try_move(Vector2i(0, -1))
	elif pos.x < 390:
		_try_move(Vector2i(1, 0))
	else:
		_place_bomb()

func _try_move(dir: Vector2i) -> void:
	if game_over:
		return
	if move_clock < MOVE_DELAY:
		return
	move_clock = 0.0
	var target := player + dir
	if _is_open(target):
		player = target
		if enemies.has(player):
			_end_game("CAUGHT! TAP TO RETRY")
		if enemies.is_empty():
			_end_game("MAZE CLEARED! TAP TO PLAY")
	queue_redraw()

func _is_open(p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= COLS or p.y >= ROWS:
		return false
	if walls[p.y][p.x] or blocks[p.y][p.x]:
		return false
	for b in bombs:
		if b.cell == p:
			return false
	return true

func _place_bomb() -> void:
	if game_over or bombs.size() >= 2:
		return
	for b in bombs:
		if b.cell == player:
			return
	bombs.append({"cell": player, "fuse": BOMB_FUSE})
	queue_redraw()

func _explode(index: int) -> void:
	var cell: Vector2i = bombs[index].cell
	bombs.remove_at(index)
	var affected: Array[Vector2i] = [cell]
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		for distance in range(1, 3):
			var p: Vector2i = cell + dir * distance
			if p.x < 0 or p.y < 0 or p.x >= COLS or p.y >= ROWS or walls[p.y][p.x]:
				break
			affected.append(p)
			if blocks[p.y][p.x]:
				blocks[p.y][p.x] = false
				break
	for p in affected:
		if p == player:
			_end_game("BOOM! TAP TO RETRY")
		if enemies.has(p):
			enemies.erase(p)
	blasts.append({"cells": affected, "time": BLAST_TIME})
	if enemies.is_empty() and not game_over:
		_end_game("MAZE CLEARED! TAP TO PLAY")
	queue_redraw()

func _move_enemies() -> void:
	for i in range(enemies.size()):
		var e: Vector2i = enemies[i]
		var choices: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		choices.shuffle()
		for d in choices:
			var p: Vector2i = e + d
			if p == player:
				_end_game("CAUGHT! TAP TO RETRY")
				return
			if _is_open(p) and not enemies.has(p):
				enemies[i] = p
				break

func _end_game(text_value: String) -> void:
	game_over = true
	message = text_value
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(480, 640)), Color("#101c2b"))
	draw_string(ThemeDB.fallback_font, Vector2(24, 30), "BOMBERMAN 8-BIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#ffe66d"))
	draw_string(ThemeDB.fallback_font, Vector2(24, 54), message, HORIZONTAL_ALIGNMENT_LEFT, 430, 13, Color("#f4f7fa"))
	for y in range(ROWS):
		for x in range(COLS):
			var rect := Rect2(BOARD_X + x * TILE, BOARD_Y + y * TILE, TILE, TILE)
			if walls[y][x]:
				draw_rect(rect, Color("#245b77"))
				draw_rect(rect.grow(-4), Color("#347f9c"))
				draw_rect(Rect2(rect.position + Vector2(5, 5), Vector2(7, 4)), Color("#69b7c9"))
			else:
				draw_rect(rect, Color("#20394a"))
				draw_rect(Rect2(rect.position + Vector2(1, 1), Vector2(30, 30)), Color("#254454"))
				if blocks[y][x]:
					draw_rect(rect.grow(-3), Color("#b96d42"))
					draw_rect(Rect2(rect.position + Vector2(4, 5), Vector2(10, 5)), Color("#e6a05d"))
					draw_rect(Rect2(rect.position + Vector2(17, 19), Vector2(10, 5)), Color("#8b4d39"))
	for b in bombs:
		var c: Vector2i = b.cell
		var center := _center(c)
		draw_circle(center, 11, Color("#15171d"))
		draw_circle(center + Vector2(-3, -4), 3, Color("#c6c9cf"))
		draw_line(center + Vector2(5, -8), center + Vector2(10, -14), Color("#ffcb5c"), 3)
	for blast in blasts:
		for c in blast.cells:
			draw_rect(Rect2(BOARD_X + c.x * TILE + 3, BOARD_Y + c.y * TILE + 3, TILE - 6, TILE - 6), Color("#ffb52e"))
			draw_rect(Rect2(BOARD_X + c.x * TILE + 10, BOARD_Y + c.y * TILE + 10, TILE - 20, TILE - 20), Color("#fff2a6"))
	for e in enemies:
		var c := _center(e)
		draw_circle(c, 12, Color("#d94b55"))
		draw_circle(c + Vector2(-4, -3), 3, Color.WHITE)
		draw_circle(c + Vector2(4, -3), 3, Color.WHITE)
		draw_circle(c + Vector2(-4, -3), 1.5, Color("#18212d"))
		draw_circle(c + Vector2(4, -3), 1.5, Color("#18212d"))
	_draw_player()
	_draw_controls()
	if game_over:
		draw_rect(Rect2(24, 250, 432, 84), Color(0.02, 0.05, 0.09, 0.92))
		draw_string(ThemeDB.fallback_font, Vector2(44, 286), message, HORIZONTAL_ALIGNMENT_LEFT, 390, 17, Color("#ffe66d"))
		draw_string(ThemeDB.fallback_font, Vector2(44, 312), "TAP SCREEN OR PRESS R", HORIZONTAL_ALIGNMENT_LEFT, 390, 12, Color.WHITE)

func _center(p: Vector2i) -> Vector2:
	return Vector2(BOARD_X + p.x * TILE + TILE / 2, BOARD_Y + p.y * TILE + TILE / 2)

func _draw_player() -> void:
	var r := Rect2(BOARD_X + player.x * TILE + 5, BOARD_Y + player.y * TILE + 4, 22, 24)
	draw_rect(r, Color("#ffd34e"))
	draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(16, 8)), Color("#f8f1d0"))
	draw_rect(Rect2(r.position + Vector2(5, 6), Vector2(3, 4)), Color("#18212d"))
	draw_rect(Rect2(r.position + Vector2(14, 6), Vector2(3, 4)), Color("#18212d"))
	draw_rect(Rect2(r.position + Vector2(4, 17), Vector2(5, 5)), Color("#e78c36"))
	draw_rect(Rect2(r.position + Vector2(13, 17), Vector2(5, 5)), Color("#e78c36"))

func _draw_controls() -> void:
	var buttons := [
		[Rect2(28, 505, 82, 54), "LEFT"],
		[Rect2(116, 505, 82, 54), "DOWN"],
		[Rect2(204, 505, 82, 54), "UP"],
		[Rect2(292, 505, 70, 54), "RIGHT"],
		[Rect2(370, 505, 82, 54), "BOMB"]
	]
	for item in buttons:
		var rect: Rect2 = item[0]
		draw_rect(rect, Color("#254454"))
		draw_rect(rect.grow(-3), Color("#347f9c"))
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 8, rect.position.y + 32), item[1], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 12, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(32, 590), "KEYBOARD: WASD / ARROWS + SPACE", HORIZONTAL_ALIGNMENT_LEFT, 420, 12, Color("#a9c6d4"))
