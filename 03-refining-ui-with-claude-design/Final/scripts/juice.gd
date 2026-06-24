class_name Juice
extends RefCounted

## Static, code-driven "game feel" tween helpers.
##
## Every helper stores its tween in a node meta key and kills the previous one
## before starting a new one, so repeated calls (e.g. rapid hovers) never fight
## each other. Works on any CanvasItem (Control or Node2D) — pivot centering is
## only applied to Control nodes, since Node2D scales around its own origin.

const _KEY_SCALE := "_juice_scale"
const _KEY_POP := "_juice_pop"
const _KEY_FADE := "_juice_fade"
const _KEY_BREATHE := "_juice_breathe"
const _KEY_MOVE := "_juice_move"


# ---------------------------------------------------------------------------
# Hover / press feedback (buttons, tiles)
# ---------------------------------------------------------------------------

static func hover_grow(c: Control, target_scale := 1.06) -> void:
	_center_pivot(c)
	var t := _restart(c, _KEY_SCALE)
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2.ONE * target_scale, 0.15)


static func hover_reset(c: Control) -> void:
	_center_pivot(c)
	var t := _restart(c, _KEY_SCALE)
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2.ONE, 0.12)


static func press_pop(c: Control) -> void:
	_center_pivot(c)
	var t := _restart(c, _KEY_SCALE)
	t.tween_property(c, "scale", Vector2.ONE * 0.92, 0.06)
	t.tween_property(c, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Appearance: pop-in and fades
# ---------------------------------------------------------------------------

static func pop_in(c: CanvasItem, dur := 0.28) -> void:
	if c is Control:
		_center_pivot(c)
	c.scale = Vector2(0.6, 0.6)
	c.modulate.a = 0.0
	var t := _restart(c, _KEY_POP).set_parallel(true)
	t.tween_property(c, "scale", Vector2.ONE, dur) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "modulate:a", 1.0, dur * 0.7)


static func fade_show(node: CanvasItem, dur := 0.3) -> void:
	if node.visible and node.modulate.a >= 0.99:
		return
	node.modulate.a = 0.0
	node.visible = true
	var t := _restart(node, _KEY_FADE)
	t.tween_property(node, "modulate:a", 1.0, dur)


static func fade_hide(node: CanvasItem, dur := 0.3) -> void:
	if not node.visible:
		return
	var t := _restart(node, _KEY_FADE)
	t.tween_property(node, "modulate:a", 0.0, dur)
	t.tween_callback(func() -> void: node.visible = false)


# ---------------------------------------------------------------------------
# Idle "breathing" (looping)
# ---------------------------------------------------------------------------

static func breathe(node: CanvasItem, amount := 0.03, period := 2.4) -> void:
	if node is Control:
		_center_pivot(node)
	var t := _restart(node, _KEY_BREATHE).set_loops()
	t.tween_property(node, "scale", Vector2.ONE * (1.0 + amount), period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(node, "scale", Vector2.ONE, period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func stop_breathe(node: CanvasItem) -> void:
	_kill(node, _KEY_BREATHE)
	node.scale = Vector2.ONE


## One-shot scale overshoot ("pop"). Shares the breathe slot so it never fights
## idle breathing; resumes breathing once it settles.
static func punch(node: CanvasItem, amount := 0.14) -> void:
	if node is Control:
		_center_pivot(node)
	var t := _restart(node, _KEY_BREATHE)
	t.tween_property(node, "scale", Vector2.ONE * (1.0 + amount), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(breathe.bind(node))


## Stronger looping pulse for the active-brew window. Reuses the breathe slot,
## so it overrides idle breathing; call stop_breathe() to end it.
static func brew_pulse(node: CanvasItem, amount := 0.06, period := 0.5) -> void:
	if node is Control:
		_center_pivot(node)
	var t := _restart(node, _KEY_BREATHE).set_loops()
	t.tween_property(node, "scale", Vector2.ONE * (1.0 + amount), period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(node, "scale", Vector2.ONE * (1.0 - amount * 0.5), period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------------------
# Reactions (one-shot)
# ---------------------------------------------------------------------------

static func bounce(node: CanvasItem, height := 38.0) -> void:
	var base := _base_pos(node)
	var t := _restart(node, _KEY_MOVE)
	t.tween_property(node, "position:y", base.y - height, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "position:y", base.y, 0.45) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


static func shake(node: CanvasItem, intensity := 12.0, dur := 0.4) -> void:
	var base := _base_pos(node)
	var t := _restart(node, _KEY_MOVE)
	var steps := 8
	for i in steps:
		var falloff := 1.0 - float(i) / steps
		var off := Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)) * falloff
		t.tween_property(node, "position", base + off, dur / steps)
	t.tween_property(node, "position", base, dur / steps)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _restart(node: Node, key: String) -> Tween:
	_kill(node, key)
	var t := node.create_tween()
	node.set_meta(key, t)
	return t


static func _kill(node: Node, key: String) -> void:
	if not node.has_meta(key):
		return
	var prev = node.get_meta(key)
	if prev is Tween and prev.is_valid():
		prev.kill()


static func _center_pivot(c: Control) -> void:
	if c.size != Vector2.ZERO:
		c.pivot_offset = c.size * 0.5


static func _base_pos(node: CanvasItem) -> Vector2:
	if not node.has_meta("_juice_base_pos"):
		node.set_meta("_juice_base_pos", node.position)
	return node.get_meta("_juice_base_pos")
