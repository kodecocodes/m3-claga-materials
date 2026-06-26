# Witch's Apprentice — Core Loop FSM (Godot 4)

## Overview

This document describes a finite state machine (FSM) for the core gameplay loop of *Witch's Apprentice*. It covers the flow from customer arrival through potion delivery and back, and includes a recommended Godot 4 implementation pattern using an enum-based state machine on a single node.

---

## State Diagram

```
┌─────────────────┐
│  WAIT_FOR_CUSTOMER │◄────────────────────────────────┐
└────────┬─────────┘                                   │
         │ cooldown elapses → customer spawns          │
         ▼                                             │
┌─────────────────┐                                    │
│ CUSTOMER_WAITING │                                    │
└────────┬─────────┘                                   │
         │ click recipe book                           │
         ▼                                             │
┌─────────────────┐                                    │
│  VIEWING_RECIPE  │                                    │
└────────┬─────────┘                                   │
         │ close book / click ingredient               │
         ▼                                             │
┌─────────────────┐                                    │
│ ADDING_INGREDIENTS │◄──┐ click ingredient (loop)      │
│                  │────┘ click discard (clear, loop)  │
└────────┬─────────┘                                   │
         │ click cauldron                              │
         ▼                                             │
┌─────────────────┐                                    │
│    BREWING       │──── brew_finished (invalid) ──────┤
└────────┬─────────┘                                   │
         │ brew_finished (valid)                       │
         ▼                                             │
┌─────────────────┐                                    │
│  BOTTLE_READY    │                                    │
└────────┬─────────┘                                   │
         │ click bottle                                │
         ▼                                             │
┌─────────────────┐                                    │
│ SERVING_CUSTOMER │                                    │
└────────┬─────────┘                                   │
         │ handoff done                 ▼              │
         │                  ┌─────────────────┐        │
         └─────────────────►│ CUSTOMER_REACTION │───────┘
                            └─────────────────┘
                       (happy: delivered correct potion
                        unhappy: wrong potion brewed)
```

---

## States

| State | Description | Player Input Accepted | Exit Condition |
|---|---|---|---|
| `WAIT_FOR_CUSTOMER` | No customer present; cooldown counts down before the next customer spawns. | None (or idle animations) | See transition table |
| `CUSTOMER_WAITING` | Customer has arrived and displayed their potion request (e.g., via speech bubble/icon). | Click recipe book, click ingredient shelves | See transition table |
| `VIEWING_RECIPE` | Recipe book UI is open, showing the recipe for the requested potion. | Click ingredient (closes book), click close button | See transition table |
| `ADDING_INGREDIENTS` | Player is clicking ingredients on shelves; each click adds one to the cauldron's current mix (append-only). | Click ingredient shelves, click cauldron, click recipe book, click discard | See transition table |
| `BREWING` | Brew animation/VFX plays; cauldron contents evaluated against recipe. | None (input locked) | See transition table |
| `BOTTLE_READY` | Filled bottle sits on the counter, ready to be picked up. A correct potion always exists at this point. | Click bottle | See transition table |
| `SERVING_CUSTOMER` | Hand-off animation; bottle moves from counter to customer. | None (input locked) | See transition table |
| `CUSTOMER_REACTION` | Customer reacts happy (delivered the correct potion) or unhappy (wrong potion brewed), then leaves. | None (input locked), or click to skip/dismiss | See transition table |

---

## Transition Table

| From | Event | To | Notes |
|---|---|---|---|
| `WAIT_FOR_CUSTOMER` | `customer_spawned` | `CUSTOMER_WAITING` | Set `current_request` to a random/queued recipe ID |
| `CUSTOMER_WAITING` | `recipe_book_clicked` | `VIEWING_RECIPE` | |
| `CUSTOMER_WAITING` | `ingredient_clicked` | `ADDING_INGREDIENTS` | Allows skipping the book if player knows the recipe |
| `VIEWING_RECIPE` | `book_closed` | `CUSTOMER_WAITING` or `ADDING_INGREDIENTS` | Depends on `cauldron_contents.is_empty()` |
| `VIEWING_RECIPE` | `ingredient_clicked` | `ADDING_INGREDIENTS` | Book auto-closes, ingredient is added |
| `ADDING_INGREDIENTS` | `ingredient_clicked` | `ADDING_INGREDIENTS` | Self-loop; appends to `cauldron_contents` |
| `ADDING_INGREDIENTS` | `recipe_book_clicked` | `VIEWING_RECIPE` | Returns here on close |
| `ADDING_INGREDIENTS` | `discard_clicked` | `ADDING_INGREDIENTS` | Self-loop; `cauldron_contents` cleared (toss the batch) |
| `ADDING_INGREDIENTS` | `cauldron_clicked` | `BREWING` | Only if `cauldron_contents` is non-empty |
| `BREWING` | `brew_finished` (valid) | `BOTTLE_READY` | `cauldron_contents` cleared, bottle spawned with potion type |
| `BREWING` | `brew_finished` (invalid) | `CUSTOMER_REACTION` | `cauldron_contents` cleared, unhappy outcome — customer leaves |
| `BOTTLE_READY` | `bottle_clicked` | `SERVING_CUSTOMER` | |
| `SERVING_CUSTOMER` | `handoff_finished` | `CUSTOMER_REACTION` | Bottle came from `BOTTLE_READY` (valid brew only) → always a happy reaction |
| `CUSTOMER_REACTION` | `reaction_finished` | `WAIT_FOR_CUSTOMER` | Customer exits; `WAIT_FOR_CUSTOMER` starts the next-customer cooldown timer |

---

## Godot 4 Implementation Pattern

### 1. Enum-based state machine on a single `GameLoop` node

```gdscript
extends Node
class_name GameLoop

## Core loop states for the shop gameplay.
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

## Whether the customer received their potion in time.
enum ReactionOutcome {
	HAPPY,
	UNHAPPY,
}

## Emitted whenever the FSM transitions, useful for UI/animation hooks.
signal state_changed(old_state: State, new_state: State)

@export var next_customer_cooldown_seconds: float = 2.0

var current_state: State = State.WAIT_FOR_CUSTOMER

# Runtime data the FSM operates on.
var current_request: StringName = &""
var cauldron_contents: Array[StringName] = []
var last_reaction_outcome: ReactionOutcome = ReactionOutcome.HAPPY

@onready var _cooldown_timer: Timer = Timer.new()


func _ready() -> void:
	_cooldown_timer.one_shot = true
	_cooldown_timer.timeout.connect(_on_cooldown_finished)
	add_child(_cooldown_timer)

	_enter_state(current_state)


## Central transition function. All state changes go through here
## so logging, signals, and validation stay in one place.
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
			_show_request_bubble(current_request)
		State.VIEWING_RECIPE:
			_open_recipe_book(current_request)
		State.ADDING_INGREDIENTS:
			_enable_ingredient_input(true)
		State.BREWING:
			_enable_ingredient_input(false)
			_play_brew_animation()
		State.BOTTLE_READY:
			_spawn_bottle()
		State.SERVING_CUSTOMER:
			_play_handoff_animation()
		State.CUSTOMER_REACTION:
			_evaluate_and_play_reaction()


func _exit_state(state: State) -> void:
	_previous_state = state
	match state:
		State.VIEWING_RECIPE:
			_close_recipe_book()
		State.CUSTOMER_REACTION:
			_dismiss_customer()

var _previous_state: State = State.WAIT_FOR_CUSTOMER


# --- Input handlers (connect these to UI signals) ---------------------

func _on_recipe_book_clicked() -> void:
	match current_state:
		State.CUSTOMER_WAITING, State.ADDING_INGREDIENTS:
			transition_to(State.VIEWING_RECIPE)


func _on_recipe_book_closed() -> void:
	if current_state != State.VIEWING_RECIPE:
		return

	if cauldron_contents.is_empty():
		transition_to(State.CUSTOMER_WAITING)
	else:
		transition_to(State.ADDING_INGREDIENTS)


func _on_ingredient_clicked(ingredient_id: StringName) -> void:
	match current_state:
		State.CUSTOMER_WAITING, State.VIEWING_RECIPE, State.ADDING_INGREDIENTS:
			cauldron_contents.append(ingredient_id)
			_update_cauldron_visual(cauldron_contents)
			transition_to(State.ADDING_INGREDIENTS)


## Tosses the current batch. Cauldron empties, player stays in ADDING_INGREDIENTS.
func _on_discard_clicked() -> void:
	if current_state != State.ADDING_INGREDIENTS:
		return
	if cauldron_contents.is_empty():
		return

	cauldron_contents.clear()
	_update_cauldron_visual(cauldron_contents)
	_show_discard_feedback()


func _on_cauldron_clicked() -> void:
	if current_state == State.ADDING_INGREDIENTS and not cauldron_contents.is_empty():
		transition_to(State.BREWING)


func _on_bottle_clicked() -> void:
	if current_state == State.BOTTLE_READY:
		transition_to(State.SERVING_CUSTOMER)


# --- Animation/timer callbacks (connect via AnimationPlayer signals) --

func _on_brew_animation_finished() -> void:
	if current_state != State.BREWING:
		return

	var valid := _is_valid_recipe(cauldron_contents, current_request)
	cauldron_contents.clear()
	if valid:
		transition_to(State.BOTTLE_READY)
	else:
		last_reaction_outcome = ReactionOutcome.UNHAPPY
		transition_to(State.CUSTOMER_REACTION)


func _on_handoff_animation_finished() -> void:
	if current_state == State.SERVING_CUSTOMER:
		# Delivered a bottle from BOTTLE_READY → always the correct potion.
		last_reaction_outcome = ReactionOutcome.HAPPY
		transition_to(State.CUSTOMER_REACTION)


func _on_reaction_finished() -> void:
	if current_state == State.CUSTOMER_REACTION:
		transition_to(State.WAIT_FOR_CUSTOMER)


## Called when the next-customer cooldown (started on entering
## WAIT_FOR_CUSTOMER) finishes.
func _on_cooldown_finished() -> void:
	if current_state == State.WAIT_FOR_CUSTOMER:
		current_request = _pick_next_request()
		transition_to(State.CUSTOMER_WAITING)


# --- Stub helper functions (implement per your scene structure) -------

func _show_request_bubble(_request_id: StringName) -> void:
	pass

func _open_recipe_book(_request_id: StringName) -> void:
	pass

func _close_recipe_book() -> void:
	pass

func _enable_ingredient_input(_enabled: bool) -> void:
	pass

func _play_brew_animation() -> void:
	pass

func _spawn_bottle() -> void:
	pass

func _play_handoff_animation() -> void:
	pass

## Plays happy/unhappy animation based on `last_reaction_outcome`,
## updates score/currency, then emits `_on_reaction_finished` when done
## (e.g. via an AnimationPlayer "animation_finished" signal connection).
func _evaluate_and_play_reaction() -> void:
	pass

func _dismiss_customer() -> void:
	pass

func _update_cauldron_visual(_contents: Array[StringName]) -> void:
	pass

func _show_discard_feedback() -> void:
	pass

func _is_valid_recipe(contents: Array[StringName], request_id: StringName) -> bool:
	# Compare against a Recipe resource/dictionary, ignoring order.
	return false

func _pick_next_request() -> StringName:
	# Pick a random recipe ID from your available recipes/Resources.
	return &""
```

### 2. Notes on this implementation

- **Single source of truth:** `current_state` lives in one place, and all transitions go through `transition_to()`. This avoids scattered boolean flags (`is_brewing`, `book_open`, etc.) that tend to drift out of sync.
- **`_enter_state` / `_exit_state` pattern:** Keeps side effects (opening UI, locking input, starting animations, timers) tied directly to state changes rather than duplicated across input handlers.
- **Signals for decoupling:** `state_changed` lets UI scripts (recipe book, cauldron, bottle, customer) react to FSM changes without the FSM needing direct references to every node — connect to it from each UI controller in `_ready()`.
- **Guard clauses:** Each `_on_*` handler checks `current_state` before acting, so stray clicks during locked states (`BREWING`, `SERVING_CUSTOMER`, etc.) are ignored automatically.
- **Recipe matching:** `_is_valid_recipe()` is the key gameplay hook — likely backed by a `Recipe` Resource (`.tres`) containing an `Array[StringName]` of required ingredient IDs, compared against `cauldron_contents` (consider sorting both arrays or using a `Dictionary` of counts if order/duplicates matter).
- **Ingredient rendering:** Since ingredients use Noto Color Emoji, each ingredient ID can map to a Unicode emoji string in a `Label`/`RichTextLabel` for the shelf icons, cauldron contents preview, and recipe book — no sprite assets needed for placeholders.
- **Wrong-brew unhappy path:** When `brew_finished` fires and `_is_valid_recipe()` returns false, `cauldron_contents` is cleared and the FSM goes directly to `CUSTOMER_REACTION` with `UNHAPPY`. No patience timer — the customer leaves because you brewed the wrong thing, not because time ran out.
- **Discard:** `_on_discard_clicked()` clears `cauldron_contents` but stays in `ADDING_INGREDIENTS` — it's a self-loop, not a state transition, since nothing about the FSM state changes.
- **Always-correct serving:** Because `BOTTLE_READY` only exists when `_is_valid_recipe()` returned true, any bottle that reaches `SERVING_CUSTOMER` is guaranteed correct — `_on_handoff_animation_finished()` hardcodes `ReactionOutcome.HAPPY`.
- **Next-customer cooldown:** `_cooldown_timer` starts when entering `WAIT_FOR_CUSTOMER` (whether the previous customer was happy or unhappy) and, on finishing, picks the next request and transitions to `CUSTOMER_WAITING`.
