extends RefCounted
class_name FoliageState

var removed_ids: Dictionary = {}

func remove(foliage_id: String) -> void:
	removed_ids[foliage_id] = true

func is_removed(foliage_id: String) -> bool:
	return bool(removed_ids.get(foliage_id, false))

func to_dict() -> Array[String]:
	var ids: Array[String] = []
	for foliage_id: Variant in removed_ids:
		ids.append(str(foliage_id))
	ids.sort()
	return ids

func from_dict(data: Variant) -> void:
	removed_ids.clear()
	if data is Array:
		for foliage_id: Variant in data:
			removed_ids[str(foliage_id)] = true
	elif data is Dictionary:
		for foliage_id: Variant in data:
			if bool(data[foliage_id]):
				removed_ids[str(foliage_id)] = true
