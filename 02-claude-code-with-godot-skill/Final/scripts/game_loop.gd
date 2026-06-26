class_name GameLoop
extends Node2D

## Core gameplay FSM for the shop. Single source of truth: `current_state`,
## with every transition routed through `transition_to()`. State side-effects
## (UI, input locking, animations) live in `_enter_state` / `_exit_state`.
## All polish is driven by Tweens (no AnimationPlayer).

const EMOJI_FONT := preload("res://fonts/NotoColorEmoji-Regular.ttf")

enum State {
	WAIT_FOR_CUSTOMER,
	CUSTOMER_WAITING,
	VIEWING_RECIPE,
	ADDING_INGREDIENTS,
	BREWING,
	BOTTLE_READY,
	SERVING_CUSTOMER,
	CUSTOMER_REACTION,
}

enum ReactionOutcome { HAPPY, UNHAPPY }

signal state_changed(old_state: State, new_state: State)

@export var recipe_db: RecipeDatabase
@export var customer_db: CustomerDatabase
@export var next_customer_cooldown_seconds: float = 2.0
@export var brew_duration: float = 1.6

var current_state: State = State.WAIT_FOR_CUSTOMER
var current_request: StringName = &""
var cauldron_contents: Array[StringName] = []
var last_reaction_outcome: ReactionOutcome = ReactionOutcome.HAPPY

var _current_customer: CustomerData
var _customer_present: bool = false
var _customer_home: Vector2
var _potion_home: Vector2
var _liquid_base_scale: Vector2
var _liquid_base_color: Color

@onready var _ingredients_root: Node2D = $IngedientShelf/Ingredients
@onready var _cauldron: Node2D = $Cauldron
@onready var _cauldron_liquid: Sprite2D = $Cauldron/Liquid
@onready var _cauldron_area: Area2D = $Cauldron/Area2D
@onready var _recipe_book_area: Area2D = $RecipeBook/Area2D
@onready var _recipe_panel: Panel = $RecipeBookPanel
@onready var _recipe_name_label: Label = $RecipeBookPanel/VBox/RecipeNameLabel
@onready var _recipe_ingredients_label: Label = $RecipeBookPanel/VBox/RecipeIngredientsLabel
@onready var _recipe_close_button: Button = $RecipeBookPanel/VBox/CloseButton
@onready var _potion: Sprite2D = $Potion
@onready var _potion_liquid: Sprite2D = $Potion/PotionLiquidSprite
@onready var _potion_area: Area2D = $Potion/Area2D
@onready var _customer_label: Label = $CustomerEmojiLabel
@onready var _greeting_label: Label = $GreetingLabel
@onready var _contents_label: Label = $CauldronContentsLabel
@onready var _discard_button: Button = $DiscardButton

@onready var _cooldown_timer: Timer = Timer.new()


func _ready() -> void:
	# Area2D click picking is off by default on the root viewport.
	get_viewport().physics_object_picking = true

	_customer_home = _customer_label.position
	_potion_home = _potion.position
	_liquid_base_scale = _cauldron_liquid.scale
	_liquid_base_color = _cauldron_liquid.self_modulate
	_customer_label.pivot_offset = _customer_label.size * 0.5

	_cooldown_timer.one_shot = true
	_cooldown_timer.timeout.connect(_on_cooldown_finished)
	add_child(_cooldown_timer)

	_setup_shelf()

	_cauldron_area.input_event.connect(_on_area_input.bind(_on_cauldron_clicked))
	_recipe_book_area.input_event.connect(_on_area_input.bind(_on_recipe_book_clicked))
	_potion_area.input_event.connect(_on_area_input.bind(_on_bottle_clicked))
	_discard_button.pressed.connect(_on_discard_clicked)
	_recipe_close_button.pressed.connect(_on_recipe_book_closed)

	_potion.visible = false
	_recipe_panel.visible = false
	_customer_label.modulate.a = 0.0
	_greeting_label.modulate.a = 0.0
	_contents_label.text = ""

	_enter_state(current_state)


## Assigns the shelf emojis from the database and wires each ingredient's click.
func _setup_shelf() -> void:
	var shelf := recipe_db.shelf_ingredients
	var nodes := _ingredients_root.get_children()
	for i in nodes.size():
		var ing := nodes[i] as Ingredient
		if ing == null:
			continue
		if i < shelf.size():
			ing.emoji = shelf[i].emoji
		ing.clicked.connect(_on_ingredient_clicked)


# --- Transition core (from .design/fsm.md) ----------------------------

func transition_to(new_state: State) -> void:
	if new_state == current_state:
		return
	_exit_state(current_state)
	var old_state: State = current_state
	current_state = new_state
	_enter_state(current_state)
	state_changed.emit(old_state, new_state)


func _enter_state(state: State) -> void:
	match state:
		State.WAIT_FOR_CUSTOMER:
			_cooldown_timer.start(next_customer_cooldown_seconds)
		State.CUSTOMER_WAITING:
			_show_customer()
		State.VIEWING_RECIPE:
			_open_recipe_book()
		State.ADDING_INGREDIENTS:
			pass
		State.BREWING:
			_play_brew()
		State.BOTTLE_READY:
			_spawn_bottle()
		State.SERVING_CUSTOMER:
			_play_handoff()
		State.CUSTOMER_REACTION:
			_play_reaction()


func _exit_state(state: State) -> void:
	match state:
		State.VIEWING_RECIPE:
			_close_recipe_book()
		State.CUSTOMER_REACTION:
			_dismiss_customer()
		_:
			pass


# --- Input handlers (guarded by current_state) ------------------------

func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int, action: Callable) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		action.call()


func _on_recipe_book_clicked() -> void:
	match current_state:
		State.CUSTOMER_WAITING, State.ADDING_INGREDIENTS:
			transition_to(State.VIEWING_RECIPE)
		State.VIEWING_RECIPE:
			_on_recipe_book_closed()


func _on_recipe_book_closed() -> void:
	if current_state != State.VIEWING_RECIPE:
		return
	if cauldron_contents.is_empty():
		transition_to(State.CUSTOMER_WAITING)
	else:
		transition_to(State.ADDING_INGREDIENTS)


func _on_ingredient_clicked(emoji: String, from_global: Vector2) -> void:
	match current_state:
		State.CUSTOMER_WAITING, State.VIEWING_RECIPE, State.ADDING_INGREDIENTS:
			cauldron_contents.append(StringName(emoji))
			_update_contents_label()
			_fly_to_cauldron(emoji, from_global)
			transition_to(State.ADDING_INGREDIENTS)


func _on_discard_clicked() -> void:
	if current_state != State.ADDING_INGREDIENTS or cauldron_contents.is_empty():
		return
	cauldron_contents.clear()
	_show_discard_feedback()


func _on_cauldron_clicked() -> void:
	if current_state == State.ADDING_INGREDIENTS and not cauldron_contents.is_empty():
		transition_to(State.BREWING)


func _on_bottle_clicked() -> void:
	if current_state == State.BOTTLE_READY:
		transition_to(State.SERVING_CUSTOMER)


# --- Timer / animation completion callbacks ---------------------------

func _on_cooldown_finished() -> void:
	if current_state != State.WAIT_FOR_CUSTOMER:
		return
	current_request = recipe_db.recipes.pick_random().id
	_current_customer = customer_db.random_customer()
	transition_to(State.CUSTOMER_WAITING)


func _on_brew_finished() -> void:
	if current_state != State.BREWING:
		return
	_cauldron_liquid.scale = _liquid_base_scale
	_cauldron_liquid.self_modulate = _liquid_base_color

	var valid := recipe_db.is_valid_recipe(cauldron_contents, current_request)
	cauldron_contents.clear()
	_contents_label.text = ""

	if valid:
		transition_to(State.BOTTLE_READY)
	else:
		last_reaction_outcome = ReactionOutcome.UNHAPPY
		transition_to(State.CUSTOMER_REACTION)


func _on_handoff_finished() -> void:
	if current_state != State.SERVING_CUSTOMER:
		return
	_potion.visible = false
	_potion.scale = Vector2(0.25, 0.25)
	last_reaction_outcome = ReactionOutcome.HAPPY
	transition_to(State.CUSTOMER_REACTION)


func _on_reaction_finished() -> void:
	if current_state != State.CUSTOMER_REACTION:
		return
	_customer_label.position = _customer_home
	_customer_label.scale = Vector2.ONE
	transition_to(State.WAIT_FOR_CUSTOMER)


# --- Customer visuals -------------------------------------------------

func _show_customer() -> void:
	if _customer_present:
		return
	_customer_present = true
	var recipe := recipe_db.get_recipe(current_request)
	var potion_name := recipe.potion_name if recipe else "potion"
	_customer_label.text = _current_customer.emoji
	_greeting_label.text = customer_db.random_request_quip(potion_name)

	_customer_label.position = _customer_home + Vector2(700, 0)
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_customer_label, "position", _customer_home, 0.6)
	t.tween_property(_customer_label, "modulate:a", 1.0, 0.5)
	t.tween_property(_greeting_label, "modulate:a", 1.0, 0.5)


func _dismiss_customer() -> void:
	_customer_present = false
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(_customer_label, "position", _customer_home + Vector2(700, 0), 0.5)
	t.tween_property(_customer_label, "modulate:a", 0.0, 0.45)
	t.tween_property(_greeting_label, "modulate:a", 0.0, 0.45)


func _play_reaction() -> void:
	if last_reaction_outcome == ReactionOutcome.HAPPY:
		_greeting_label.text = customer_db.random_positive_quip()
		_happy_bounce()
	else:
		_greeting_label.text = customer_db.random_negative_quip()
		_unhappy_shake()


func _happy_bounce() -> void:
	var base := _customer_label.position
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(_customer_label, "scale", Vector2(1.25, 1.25), 0.15)
	t.parallel().tween_property(_customer_label, "position:y", base.y - 70.0, 0.15)
	t.tween_property(_customer_label, "position:y", base.y, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_customer_label, "scale", Vector2.ONE, 0.35)
	t.tween_interval(0.5)
	t.finished.connect(_on_reaction_finished, CONNECT_ONE_SHOT)


func _unhappy_shake() -> void:
	var base := _customer_label.position
	var t := create_tween()
	for i in 6:
		var dir := 1.0 if i % 2 == 0 else -1.0
		t.tween_property(_customer_label, "position:x", base.x + 28.0 * dir, 0.05)
	t.tween_property(_customer_label, "position:x", base.x, 0.05)
	t.tween_interval(0.5)
	t.finished.connect(_on_reaction_finished, CONNECT_ONE_SHOT)


# --- Recipe book ------------------------------------------------------

func _open_recipe_book() -> void:
	var recipe := recipe_db.get_recipe(current_request)
	if recipe:
		_recipe_name_label.text = recipe.potion_name
		_recipe_ingredients_label.text = " ".join(recipe.required_ingredients)

	_recipe_panel.visible = true
	_recipe_panel.pivot_offset = _recipe_panel.size * 0.5
	_recipe_panel.scale = Vector2.ZERO
	_recipe_panel.modulate.a = 0.0
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_recipe_panel, "scale", Vector2.ONE, 0.35)
	t.tween_property(_recipe_panel, "modulate:a", 1.0, 0.3)


func _close_recipe_book() -> void:
	var panel := _recipe_panel
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(panel, "scale", Vector2.ZERO, 0.25)
	t.tween_property(panel, "modulate:a", 0.0, 0.22)
	t.chain().tween_callback(func() -> void: panel.visible = false)


# --- Cauldron / ingredients ------------------------------------------

func _update_contents_label() -> void:
	_contents_label.modulate.a = 1.0
	_contents_label.scale = Vector2.ONE
	var parts: Array[String] = []
	for e: StringName in cauldron_contents:
		parts.append(String(e))
	_contents_label.text = " ".join(parts)


## Spawns a temporary emoji label and tweens it into the cauldron mouth.
func _fly_to_cauldron(emoji: String, from_global: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = emoji
	lbl.add_theme_font_override("font", EMOJI_FONT)
	lbl.add_theme_font_size_override("font_size", 70)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 50
	add_child(lbl)
	lbl.global_position = from_global - Vector2(35, 45)

	var target := _cauldron_liquid.global_position - Vector2(35, 45)
	var t := create_tween().set_parallel(true)
	t.tween_property(lbl, "global_position", target, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(lbl, "scale", Vector2(0.3, 0.3), 0.45)
	t.chain().tween_callback(lbl.queue_free)
	_splash()


## Quick vertical bob of the cauldron liquid, reused for adds and discards.
func _splash() -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(_cauldron_liquid, "scale:y", _liquid_base_scale.y * 1.25, 0.08)
	t.tween_property(_cauldron_liquid, "scale:y", _liquid_base_scale.y, 0.12)


func _show_discard_feedback() -> void:
	_splash()
	_contents_label.pivot_offset = _contents_label.size * 0.5
	var t := create_tween().set_parallel(true)
	t.tween_property(_contents_label, "scale", Vector2(1.3, 1.3), 0.12)
	t.tween_property(_contents_label, "modulate:a", 0.0, 0.18)
	t.chain().tween_callback(func() -> void:
		_contents_label.text = ""
		_contents_label.scale = Vector2.ONE
		_contents_label.modulate.a = 1.0)


# --- Brewing / bottle / handoff --------------------------------------

func _play_brew() -> void:
	var loops: int = maxi(1, int(brew_duration / 0.36))
	var wobble := create_tween().set_loops(loops).set_trans(Tween.TRANS_SINE)
	wobble.tween_property(_cauldron_liquid, "scale:y", _liquid_base_scale.y * 1.3, 0.18)
	wobble.tween_property(_cauldron_liquid, "scale:y", _liquid_base_scale.y * 0.85, 0.18)
	wobble.finished.connect(_on_brew_finished, CONNECT_ONE_SHOT)

	var glow := create_tween()
	glow.tween_property(_cauldron_liquid, "self_modulate", Color(1.0, 0.55, 1.0), brew_duration * 0.5)
	glow.tween_property(_cauldron_liquid, "self_modulate", _liquid_base_color, brew_duration * 0.5)


func _spawn_bottle() -> void:
	var recipe := recipe_db.get_recipe(current_request)
	if recipe:
		_potion_liquid.modulate = recipe.color
	_potion.position = _potion_home
	_potion.scale = Vector2.ZERO
	_potion.visible = true
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_potion, "scale", Vector2(0.25, 0.25), 0.4)


func _play_handoff() -> void:
	var target := _customer_label.global_position + _customer_label.size * 0.5
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_potion, "global_position", target, 0.6)
	t.tween_property(_potion, "scale", Vector2(0.12, 0.12), 0.6)
	t.chain().tween_callback(_on_handoff_finished)
