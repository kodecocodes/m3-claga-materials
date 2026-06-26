class_name Ingredient
extends Node2D

signal clicked(emoji: String, from_global: Vector2)

@export var emoji: String = "🌿":
	set(value):
		emoji = value
		if is_node_ready():
			$EmojiLabel.text = value

@onready var _area: Area2D = $Area2D


func _ready() -> void:
	$EmojiLabel.text = emoji
	_area.input_event.connect(_on_area_input)


func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(emoji, global_position)
		_punch()


## Small scale-punch so a click feels responsive.
func _punch() -> void:
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2(1.15, 1.15), 0.08)
	t.tween_property(self, "scale", Vector2.ONE, 0.12)
