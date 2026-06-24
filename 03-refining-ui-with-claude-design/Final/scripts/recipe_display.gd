extends VBoxContainer
class_name RecipeDisplay

@onready var _name_label: Label = $NameLabel
@onready var _ingredients_label: Label = $IngredientsLabel
@onready var _description_label: Label = $DescriptionLabel


func open(recipe: PotionRecipe) -> void:
	_name_label.text = recipe.potion_name
	_ingredients_label.text = " ".join(recipe.required_ingredients)
	_description_label.text = recipe.description
	visible = true


func close() -> void:
	visible = false
