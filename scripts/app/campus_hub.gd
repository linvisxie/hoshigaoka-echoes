## Optional campus encounters use the same saved story IDs as the archive.
class_name CampusHub
extends RefCounted

static func events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: String in DataRegistry.get_ids("story"):
		var event := DataRegistry.get_entry("story",raw)
		if str(event.get("category","")) in ["character_event","environment_event"] and available(event):
			out.append(event)
	out.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.get("hubOrder",0)) < int(b.get("hubOrder",0)))
	return out

static func available(event: Dictionary) -> bool:
	var cid := str(event.get("requiresCharacter",""))
	if not cid.is_empty() and not CampaignFlow.character_unlocked(cid): return false
	var stage := str(event.get("requiresClear",""))
	return stage.is_empty() or StageRewardService.is_first_cleared(stage)

static func unread_count() -> int:
	var count := 0
	for event: Dictionary in events():
		if not CampaignFlow.done(str(event.storyId)): count += 1
	return count

static func visit(story_id: String) -> bool:
	var event := DataRegistry.get_entry("story",story_id)
	if not available(event) or event.is_empty():return false
	if CampaignFlow.done(story_id):
		CampaignFlow.replay_story_id = story_id
		CampaignFlow.replay_return_key = "home"
		return SceneRouter.go_to("story")
	return CampaignFlow.open_story(story_id,"","hub_event")
