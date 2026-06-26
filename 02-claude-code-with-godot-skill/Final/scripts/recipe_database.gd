class_name RecipeDatabase
extends Resource

@export var recipes: Array[PotionRecipe] = []
@export var shelf_ingredients: Array[IngredientData] = []


func get_recipe(id: StringName) -> PotionRecipe:
	for r: PotionRecipe in recipes:
		if r.id == id:
			return r
	return null


func is_valid_recipe(contents: Array[StringName], request_id: StringName) -> bool:
	var recipe := get_recipe(request_id)
	if recipe == null or contents.size() != recipe.required_ingredients.size():
		return false
	var sorted_contents := contents.map(func(s: StringName) -> String: return String(s))
	sorted_contents.sort()
	var sorted_required := recipe.required_ingredients.duplicate()
	sorted_required.sort()
	return sorted_contents == sorted_required
