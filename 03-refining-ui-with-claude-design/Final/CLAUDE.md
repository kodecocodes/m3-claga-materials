# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Witch's Apprentice** — a Godot 4.6 potion-shop game. The player brews potions for customers by clicking emoji ingredients and managing a cauldron.

## Log File

You can find the log for the game after every run here:
"%APPDATA%\Godot\app_userdata\Witch's Apprentice (final)\logs\godot.log"

## Running the Game

Open the project in Godot 4.6 and press F5, or run from the command line:

Gotdot executable location: "U:\Godot\_Editors\win64_stable\Godot.exe"

```
[godot executable] --path "." res://scenes/potion_shop_screen.tscn
```

The main scene is `scenes/potion_shop_screen.tscn`. There are no build scripts, tests, or linters — this is a pure Godot project.

## Screenshots

After running the project, search for "DEBUG" in the window title bar to find the right window to take a screenshot of.

## Architecture

The game is a single `Control`-based UI screen (not a `Node2D` world). All layout uses Control nodes themed by `themes/potion_shop.tres`.

### Scene Tree (potion_shop_screen.tscn)
- `PotionShopScreen` (Control, script `scripts/potion_shop_screen.gd`) — root + FSM owner; `recipe_db` / `customer_db` wired via `@export` in the inspector
  - `Background` (ColorRect)
  - `ScreenTitle` (Label)
  - `RecipeBookPanel` — recipe page: `RecipeName`, ingredient `Slot1/2/3` (Panel + Emoji Label), `RecipeDesc` (RichTextLabel), and `BtnPrev`/`BtnNext` nav buttons
  - `PantrySection` → `PantryGrid` (GridContainer) — pantry tiles (`PanelContainer`, one per ingredient); each has a `VBox` with `Emoji` + `Name` labels
  - `CauldronColumn` — `ActiveIngredientRow` (HBoxContainer of "well" panels), `BrewButton`, `EmptyPotButton`, and a `Cauldron` instance
  - `CustomerColumn` — `SpeechBubbleGroup` (BubblePanel + `SpeechText` RichTextLabel + rotated tail), `CustomerName`, and `AvatarPanel` → `AvatarEmoji`

### Key Scenes & Scripts
- `scripts/potion_shop_screen.gd` (`class_name PotionShopScreen`) — owns the entire FSM and all UI wiring. Pantry tiles are clicked via per-tile `gui_input` (`_on_tile_gui_input` → `_toggle_tile`); buttons use their `pressed` signals.
- `scenes/cauldron.tscn` — layered Sprite2D nodes slicing regions from `sprites/cauldron.svg`: `Background`, `Liquid`, `Front`. `Liquid` uses `self_modulate` for color changes (tinted on brew).
- `themes/potion_shop.tres` — central UI theme. Behavior depends on theme **type variations**: `PantryItem` / `PantryItemSelected`, `PantryLabel` / `PantryLabelActive`, `WellFilled` / `WellEmpty`, `BrewButton`, `EmptyPotButton`, `NavButton`, `RecipeSlot`, `SpeechBubble`, `EmojiLabel`, etc. Selecting a tile swaps its variation rather than re-styling inline.
- `scripts/juice.gd` (`class_name Juice`) — static tween helpers for game feel (see "Game feel / juice" below).

### Data Resources (`data/`)
- `data/recipe_database.tres` — `RecipeDatabase` resource; holds `recipes: Array[PotionRecipe]` and `shelf_ingredients: Array[IngredientData]`. Edit in Godot inspector to add/change recipes or shelf items.
- `data/customer_database.tres` — `CustomerDatabase` resource; holds `customers`, `request_quips`, `positive_quips`, `negative_quips`. Quips use `{potion_name}` placeholder.

### Resource Classes (`scripts/`)
- `IngredientData` — `emoji`, `ingredient_name`
- `PotionRecipe` — `id: StringName`, `potion_name`, `color`, `description`, `required_ingredients: Array[String]`
- `CustomerData` — `emoji`, `customer_name`

### Fonts
- `fonts/NotoColorEmoji-Regular.ttf` — all emoji rendering (customers, ingredients)
- `fonts/Augusta.ttf` — decorative UI labels

### Design Assets (`.design/`)
Planning documents, not runtime files:
- `fsm.md` — FSM spec and GDScript implementation pattern.
- `potions.md` — 3 potions with names, hex colors, and ingredient lists
- `potion_ingredient_emojis.md` — emoji ingredient catalog by category
- `customer_emojis.md` — emoji roster for customer display
- `customer_quips.md` — flavor text for requests and reactions

## Game Logic Overview

The core loop is an **enum-based FSM** in `scripts/potion_shop_screen.gd` (`PotionShopScreen`), with 5 states:

```
WAIT_FOR_CUSTOMER → CUSTOMER_WAITING → ADDING_INGREDIENTS → BREWING
        ↑                                                      ↓
        └──────────────── CUSTOMER_REACTION ←──────────────────┘
```

`transition_to(new_state)` runs `_exit_state` / `_enter_state` and emits `state_changed`.

Key behaviors:
- Pantry tiles are clicked via per-tile `gui_input` (`_on_tile_gui_input` → `_toggle_tile`); buttons use their `pressed` signals. There is no `_unhandled_input` / Area2D routing.
- Selecting/deselecting a tile toggles its emoji in `cauldron_contents` and swaps its theme type variation; first selection moves to `ADDING_INGREDIENTS`.
- Recipe validation (`RecipeDatabase.is_valid_recipe`) sorts both arrays and compares — order-independent.
- `cauldron_contents: Array[StringName]` accumulates emoji StringNames; cleared by `_clear_brew` after brewing or on "Empty the pot".
- Two timers created at runtime: `_cooldown_timer` (between customers) and `_anim_timer` (brew/reaction durations).
- `BREWING` validates the contents: valid → `last_reaction_outcome = HAPPY` and the cauldron liquid tints to the recipe color; invalid → `UNHAPPY` and a muddy color. Either way it advances to `CUSTOMER_REACTION`, which shows a positive/negative quip, then returns to `WAIT_FOR_CUSTOMER`.

## Game feel / juice

`scripts/juice.gd` (`class_name Juice`) holds **static** tween helpers used by `potion_shop_screen.gd` for code-driven game feel — button hover/press, fade-in/out of the customer panel, pop-in for ingredient wells and speech, idle "breathing" on the cauldron and avatar, a brew pulse, and happy-bounce / sad-shake reactions. Each helper stores its tween in a node meta key and kills the prior one before starting, so repeated calls don't fight (per the tween skill's "kill before replace" rule). No animation assets are involved — it is all tweens.

## Renderer

Uses **GL Compatibility** renderer with D3D12 on Windows and **Jolt Physics** for 3D (unused in current 2D scenes). Viewport is 1920×1080 with `canvas_items` stretch mode.
