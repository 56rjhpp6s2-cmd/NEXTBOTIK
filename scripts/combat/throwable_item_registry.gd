class_name ThrowableItemRegistry
extends RefCounted
## Built-in school items and the face-specific weaknesses they unlock.

const STANDARD := "standard"
const TEST_TUBE := "test_tube"
const LITERATURE_BOOK := "literature_book"
const CONSTITUTION := "constitution"

const DEFINITIONS := {
	"BZ_test_tube.png": {
		"kind": TEST_TUBE,
		"title": "ПРОБИРКА",
		"description": "Единственный предмет, способный ранить Елену Финкельштейн.",
		"path": "res://assets/projectiles/test_tube.png",
	},
	"BZ_literature_book.png": {
		"kind": LITERATURE_BOOK,
		"title": "УЧЕБНИК ЛИТЕРАТУРЫ",
		"description": "Единственный предмет, способный ранить Коган на розовом фоне.",
		"path": "res://assets/projectiles/literature_book.png",
	},
	"BZ_constitution.png": {
		"kind": CONSTITUTION,
		"title": "КОНСТИТУЦИЯ",
		"description": "Единственный предмет, способный ранить чёрно-белого некстбота.",
		"path": "res://assets/projectiles/constitution.png",
	},
}

static func kind_for_filename(filename: String) -> String:
	return str(DEFINITIONS.get(filename, {}).get("kind", STANDARD))

static func definition_for_filename(filename: String) -> Dictionary:
	return DEFINITIONS.get(filename, {})

static func required_kind(target: Object) -> String:
	if not is_instance_valid(target) or not target is NextbotEnemy:
		return STANDARD
	var bot := target as NextbotEnemy
	# Bosses and user-created Sandbox faces retain normal PNG combat rules.
	if bot.is_boss or bot.custom_face != null:
		return STANDARD
	match posmod(bot.face_variant, 3):
		0:
			return CONSTITUTION
		1:
			return TEST_TUBE
		2:
			return LITERATURE_BOOK
	return STANDARD

static func can_damage(target: Object, item_kind: String) -> bool:
	var required := required_kind(target)
	return required == STANDARD or item_kind == required

static func required_title(target: Object) -> String:
	match required_kind(target):
		TEST_TUBE:
			return "НУЖНА ПРОБИРКА"
		LITERATURE_BOOK:
			return "НУЖЕН УЧЕБНИК ЛИТЕРАТУРЫ"
		CONSTITUTION:
			return "НУЖНА КОНСТИТУЦИЯ"
	return "НЕВОСПРИИМЧИВ"
