class_name CustomerDatabase
extends Resource

@export var customers: Array[CustomerData] = []
@export var request_quips: Array[String] = []
@export var positive_quips: Array[String] = []
@export var negative_quips: Array[String] = []


func random_customer() -> CustomerData:
	return customers.pick_random()


func random_request_quip(potion_name: String) -> String:
	return request_quips.pick_random().replace("{potion_name}", potion_name)


func random_positive_quip() -> String:
	return positive_quips.pick_random()


func random_negative_quip() -> String:
	return negative_quips.pick_random()
