extends Control
class_name PotionShopScreen

enum State {
	WAIT_FOR_CUSTOMER,
	CUSTOMER_WAITING,
	ADDING_INGREDIENTS,
	BREWING,
	CUSTOMER_REACTION,
}

enum ReactionOutcome { HAPPY, UNHAPPY }

signal state_changed(old_state: State, new_state: State)

@export var recipe_db: RecipeDatabase
@export var customer_db: CustomerDatabase
@export var next_customer_cooldown_seconds: float = 2.0

var current_state: State = State.WAIT_FOR_CUSTOMER
var current_request: StringName = &""
var cauldron_contents: Array[StringName] = []
var last_reaction_outcome: ReactionOutcome = ReactionOutcome.HAPPY

var _current_customer: CustomerData = null
var _page: int = 0
var _tiles: Array[Control] = []

var _cooldown_timer: Timer
var _anim_timer: Timer

@onready var _recipe_name: Label = %RecipeName
@onready var _recipe_desc: RichTextLabel = %RecipeDesc
@onready var _slots: Array[Panel] = [%Slot1, %Slot2, %Slot3]
@onready var _btn_prev: Button = %BtnPrev
@onready var _btn_next: Button = %BtnNext
@onready var _pantry_grid: GridContainer = %PantryGrid
@onready var _active_row: HBoxContainer = %ActiveIngredientRow
@onready var _brew_button: Button = %BrewButton
@onready var _empty_button: Button = %EmptyPotButton
@onready var _speech_text: RichTextLabel = %SpeechText
@onready var _avatar_emoji: Label = %AvatarEmoji
@onready var _customer_name: Label = %CustomerName
@onready var _customer_column: VBoxContainer = %CustomerColumn
var _cauldron: Node2D
var _cauldron_liquid: Sprite2D
var _speech_group: Control

# Default cauldron colors to restore after a brew (from cauldron.tscn).
const _CAULDRON_LIQUID_DEFAULT := Color(5.7756904e-07, 0.7441967, 0.96189946, 1)
const _BREW_FAIL_COLOR := Color(0.35, 0.25, 0.15, 1)


func _ready() -> void:
	print("Log can be found here:", OS.get_user_data_dir(), "/logs/godot.log")
	_cauldron = %Cauldron
	_cauldron_liquid = _cauldron.get_node("Liquid")
	_speech_group = _customer_column.get_node("SpeechBubbleGroup")
	_setup_timers()
	_setup_pantry()
	_btn_prev.pressed.connect(_on_prev_pressed)
	_btn_next.pressed.connect(_on_next_pressed)
	_brew_button.pressed.connect(_on_brew_pressed)
	_empty_button.pressed.connect(_on_empty_pressed)
	for button: Button in [_btn_prev, _btn_next, _brew_button, _empty_button]:
		_add_hover_juice(button)
		button.pressed.connect(Juice.press_pop.bind(button))
	_show_recipe_page()
	_clear_brew()
	_speech_text.text = ""
	_avatar_emoji.text = ""
	_customer_name.text = ""
	_customer_column.visible = false
	Juice.breathe(_cauldron)
	_enter_state(current_state)


## Connect hover grow/reset feedback to any Control.
func _add_hover_juice(c: Control) -> void:
	c.mouse_entered.connect(Juice.hover_grow.bind(c))
	c.mouse_exited.connect(Juice.hover_reset.bind(c))


func _setup_timers() -> void:
	_cooldown_timer = Timer.new()
	_cooldown_timer.one_shot = true
	_cooldown_timer.timeout.connect(_on_cooldown_finished)
	add_child(_cooldown_timer)

	_anim_timer = Timer.new()
	_anim_timer.one_shot = true
	add_child(_anim_timer)


func _setup_pantry() -> void:
	for tile: Control in _pantry_grid.get_children():
		_tiles.append(tile)
		tile.gui_input.connect(_on_tile_gui_input.bind(tile))
		_add_hover_juice(tile)
		# Let clicks reach the tile instead of being eaten by its labels.
		for child: Node in tile.find_children("*", "Control", true, false):
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_tile_state(tile, false)


# ---------------------------------------------------------------------------
# FSM core
# ---------------------------------------------------------------------------

func transition_to(new_state: State) -> void:
	if new_state == current_state:
		return
	_exit_state(current_state)
	var old_state : PotionShopScreen.State = current_state
	current_state = new_state
	_enter_state(current_state)
	state_changed.emit(old_state, new_state)


func _enter_state(state: State) -> void:
	match state:
		State.WAIT_FOR_CUSTOMER:
			_cooldown_timer.start(next_customer_cooldown_seconds)
		State.CUSTOMER_WAITING:
			_show_request()
			_set_input_enabled(true)
		State.ADDING_INGREDIENTS:
			_set_input_enabled(true)
		State.BREWING:
			_set_input_enabled(false)
			_play_brew()
		State.CUSTOMER_REACTION:
			_play_reaction()


func _exit_state(state: State) -> void:
	match state:
		State.CUSTOMER_REACTION:
			_reset_for_next_customer()


# ---------------------------------------------------------------------------
# Recipe pages
# ---------------------------------------------------------------------------

func _on_prev_pressed() -> void:
	if recipe_db == null or recipe_db.recipes.is_empty():
		return
	_page = (_page - 1 + recipe_db.recipes.size()) % recipe_db.recipes.size()
	_show_recipe_page()


func _on_next_pressed() -> void:
	if recipe_db == null or recipe_db.recipes.is_empty():
		return
	_page = (_page + 1) % recipe_db.recipes.size()
	_show_recipe_page()


func _show_recipe_page() -> void:
	if recipe_db == null or recipe_db.recipes.is_empty():
		return
	var recipe := recipe_db.recipes[_page]
	_recipe_name.text = recipe.potion_name
	_recipe_desc.text = "[center]%s[/center]" % recipe.description
	for i: int in _slots.size():
		var slot := _slots[i]
		if i < recipe.required_ingredients.size():
			slot.visible = true
			(slot.get_node("Emoji") as Label).text = recipe.required_ingredients[i]
		else:
			slot.visible = false


# ---------------------------------------------------------------------------
# Pantry selection (toggle / set semantics)
# ---------------------------------------------------------------------------

func _on_tile_gui_input(event: InputEvent, tile: Control) -> void:
	if current_state not in [State.CUSTOMER_WAITING, State.ADDING_INGREDIENTS]:
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_toggle_tile(tile)
	tile.accept_event()


func _toggle_tile(tile: Control) -> void:
	var emoji := StringName((tile.get_node("VBox/Emoji") as Label).text)
	var selected := emoji in cauldron_contents
	if selected:
		cauldron_contents.erase(emoji)
	else:
		cauldron_contents.append(emoji)
	_apply_tile_state(tile, not selected)
	Juice.press_pop(tile)
	_rebuild_active_row()
	if not cauldron_contents.is_empty():
		transition_to(State.ADDING_INGREDIENTS)


func _apply_tile_state(tile: Control, selected: bool) -> void:
	tile.theme_type_variation = &"PantryItemSelected" if selected else &"PantryItem"
	var name_label := tile.get_node("VBox/Name") as Label
	name_label.theme_type_variation = &"PantryLabelActive" if selected else &"PantryLabel"
	var base_name := name_label.text.trim_suffix(" ✓")
	name_label.text = base_name + " ✓" if selected else base_name


# ---------------------------------------------------------------------------
# Active ingredient row
# ---------------------------------------------------------------------------

func _rebuild_active_row() -> void:
	for child in _active_row.get_children():
		child.queue_free()
	for emoji: StringName in cauldron_contents:
		var well := _make_well(String(emoji), false)
		_active_row.add_child(well)
		Juice.pop_in(well)
	if cauldron_contents.size() < 3:
		_active_row.add_child(_make_well("+", true))
	_brew_button.disabled = cauldron_contents.is_empty()


func _make_well(text: String, empty: bool) -> Panel:
	var well := Panel.new()
	well.custom_minimum_size = Vector2(70, 70)
	well.theme_type_variation = &"WellEmpty" if empty else &"WellFilled"
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"PantryLabel" if empty else &"EmojiLabel"
	label.add_theme_font_size_override("font_size", 30 if empty else 38)
	label.text = text
	well.add_child(label)
	return well


# ---------------------------------------------------------------------------
# Brewing
# ---------------------------------------------------------------------------

func _on_brew_pressed() -> void:
	if current_state == State.ADDING_INGREDIENTS and not cauldron_contents.is_empty():
		transition_to(State.BREWING)


func _play_brew() -> void:
	var valid := _is_valid_recipe(cauldron_contents, current_request)
	last_reaction_outcome = ReactionOutcome.HAPPY if valid else ReactionOutcome.UNHAPPY
	var target := _BREW_FAIL_COLOR
	if valid:
		var recipe := recipe_db.get_recipe(current_request) if recipe_db else null
		if recipe:
			target = recipe.color
	var tween := create_tween()
	tween.tween_property(_cauldron_liquid, "self_modulate", target, 1.0)
	Juice.brew_pulse(_cauldron)
	_anim_timer.timeout.connect(_on_brew_finished, CONNECT_ONE_SHOT)
	_anim_timer.start(1.5)


func _on_brew_finished() -> void:
	Juice.punch(_cauldron)
	if current_state == State.BREWING:
		transition_to(State.CUSTOMER_REACTION)


# ---------------------------------------------------------------------------
# Empty the pot
# ---------------------------------------------------------------------------

func _on_empty_pressed() -> void:
	if current_state != State.ADDING_INGREDIENTS:
		return
	# Stay in ADDING_INGREDIENTS so the request quip isn't re-rolled.
	_clear_brew()


func _clear_brew() -> void:
	cauldron_contents.clear()
	for tile: Control in _tiles:
		_apply_tile_state(tile, false)
	_rebuild_active_row()
	_tween_cauldron_default()


func _tween_cauldron_default() -> void:
	var tween := create_tween()
	tween.tween_property(_cauldron_liquid, "self_modulate", _CAULDRON_LIQUID_DEFAULT, 0.6)


# ---------------------------------------------------------------------------
# Customer
# ---------------------------------------------------------------------------

func _show_request() -> void:
	if _current_customer == null:
		return
	_avatar_emoji.text = _current_customer.emoji
	_customer_name.text = _current_customer.customer_name
	if recipe_db and customer_db:
		var recipe := recipe_db.get_recipe(current_request)
		if recipe:
			var quip := customer_db.random_request_quip("[b]%s[/b]" % recipe.potion_name)
			_speech_text.text = "\"%s\"" % quip
	Juice.fade_show(_customer_column)
	Juice.pop_in(_speech_group)
	Juice.breathe(_avatar_emoji, 0.04, 3.0)


func _play_reaction() -> void:
	if customer_db:
		if last_reaction_outcome == ReactionOutcome.HAPPY:
			_speech_text.text = "\"%s\"" % customer_db.random_positive_quip()
		else:
			_speech_text.text = "\"%s\"" % customer_db.random_negative_quip()
	Juice.pop_in(_speech_group)
	Juice.stop_breathe(_avatar_emoji)
	if last_reaction_outcome == ReactionOutcome.HAPPY:
		Juice.bounce(_avatar_emoji)
	else:
		Juice.shake(_avatar_emoji)
	_anim_timer.timeout.connect(_on_reaction_finished, CONNECT_ONE_SHOT)
	_anim_timer.start(2.5)


func _on_reaction_finished() -> void:
	if current_state == State.CUSTOMER_REACTION:
		transition_to(State.WAIT_FOR_CUSTOMER)


func _reset_for_next_customer() -> void:
	_clear_brew()
	Juice.stop_breathe(_avatar_emoji)
	# Fade out with the current content still showing; the next customer
	# overwrites the text on the way back in.
	Juice.fade_hide(_customer_column)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _set_input_enabled(enabled: bool) -> void:
	for tile: Control in _tiles:
		tile.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		if not enabled:
			Juice.hover_reset(tile)
	_brew_button.disabled = not enabled or cauldron_contents.is_empty()
	_empty_button.disabled = not enabled


func _on_cooldown_finished() -> void:
	if current_state == State.WAIT_FOR_CUSTOMER:
		current_request = _pick_next_request()
		_current_customer = customer_db.random_customer() if customer_db else null
		transition_to(State.CUSTOMER_WAITING)


func _is_valid_recipe(contents: Array[StringName], request_id: StringName) -> bool:
	if recipe_db == null:
		return false
	return recipe_db.is_valid_recipe(contents, request_id)


func _pick_next_request() -> StringName:
	if recipe_db == null or recipe_db.recipes.is_empty():
		return &""
	return (recipe_db.recipes.pick_random() as PotionRecipe).id
