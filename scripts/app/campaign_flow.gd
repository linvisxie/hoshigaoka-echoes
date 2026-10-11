## First-chapter front-end state. Uses the existing SaveGame.flow_state contract.
## Never advances a battle or grants rewards; those remain in their domain services.
class_name CampaignFlow
extends RefCounted

static var replay_story_id := ""
static var last_result: Dictionary = {}
static var inspected_character_id := "amamiya_mio"

static func state() -> Dictionary:
	return SaveService.get_current().get("flow_state", {})

static func persist(values: Dictionary) -> bool:
	if not SaveService.ensure_loaded():
		return false
	var save := SaveService.snapshot()
	var flow: Dictionary = save.get("flow_state", {})
	flow.merge(values, true)
	save["flow_state"] = flow
	return SaveService.commit(save)

static func start_new(player_name: String) -> bool:
	replay_story_id = ""
	if not SaveService.new_game(player_name.strip_edges()):
		return false
	if not persist({"campaign_active": true, "mode": "story", "current_story_id": "prologue_transfer",
		"current_story_node": "0", "pending_stage_id": "1-1", "last_stable_screen": "title"}):
		return false
	return SceneRouter.go_to("story")

static func resume() -> bool:
	replay_story_id = ""
	if not SaveService.ensure_loaded():
		return false
	var flow := state()
	if not str(flow.get("pending_story_after", "")).is_empty():
		return open_story(str(flow["pending_story_after"]), str(flow.get("pending_stage_id", "")), "post_battle", true)
	if str(flow.get("mode", "hub")) == "story" and not str(flow.get("current_story_id", "")).is_empty():
		return SceneRouter.go_to("story")
	if str(flow.get("mode", "")) == "pre_battle":
		return SceneRouter.go_to("briefing")
	return SceneRouter.go_to("home")

static func done(story_id: String) -> bool:
	return bool(SaveService.get_current().get("story", {}).get("flags", {}).get("done:" + story_id, false))

static func next_stage() -> String:
	for i: int in range(1, 11):
		var sid := "1-%d" % i
		if not StageRewardService.is_first_cleared(sid):
			return sid
	return ""

static func open_stage(sid: String) -> bool:
	var cfg := DataRegistry.get_entry("stages", sid)
	if not StageRewardService.cfg_has_content(cfg):
		return false
	# A pending required story cannot be bypassed by another menu entry.
	if not str(state().get("pending_story_after", "")).is_empty():
		return resume()
	var before := str(cfg.get("storyBefore", ""))
	if not StageRewardService.is_first_cleared(sid) and not before.is_empty() and not done(before):
		return open_story(before, sid, "story")
	if not persist({"campaign_active": true, "mode": "pre_battle", "pending_stage_id": sid,
		"current_story_id": "", "current_story_node": "", "last_stable_screen": "home"}):
		return false
	return SceneRouter.go_to("briefing")

static func open_story(story_id: String, sid: String, mode: String, preserve_node: bool = false) -> bool:
	replay_story_id = ""
	var node := str(state().get("current_story_node", "0")) if preserve_node and str(state().get("current_story_id", "")) == story_id else "0"
	if not persist({"campaign_active": true, "mode": mode, "current_story_id": story_id,
		"current_story_node": node, "pending_stage_id": sid}):
		return false
	return SceneRouter.go_to("story")

static func finish_story(story_id: String) -> bool:
	var cfg := DataRegistry.get_entry("story", story_id)
	var save := SaveService.snapshot()
	var story: Dictionary = save.get("story", {"readNodes": [], "choices": {}, "flags": {}})
	var flags: Dictionary = story.get("flags", {})
	flags["done:" + story_id] = true
	for flag: String in cfg.get("completionFlags", []):
		flags[flag] = true
	story["flags"] = flags
	save["story"] = story
	var flow: Dictionary = save.get("flow_state", {})
	var after := str(flow.get("pending_story_after", "")) == story_id
	flow["mode"] = "hub" if after else "pre_battle"
	flow["current_story_id"] = ""
	flow["current_story_node"] = ""
	flow["pending_story_after"] = ""
	flow["last_stable_screen"] = "home"
	save["flow_state"] = flow
	if not SaveService.commit(save):
		return false
	return SceneRouter.go_to("home" if after else "briefing")

static func record_node(story_id: String, index: int) -> bool:
	if not SaveService.ensure_loaded():
		return false
	var save := SaveService.snapshot()
	var story: Dictionary = save.get("story", {})
	var reads: Array = story.get("readNodes", [])
	var key := "%s:%d" % [story_id, index]
	if not reads.has(key):
		reads.append(key)
	story["readNodes"] = reads
	save["story"] = story
	var flow: Dictionary = save.get("flow_state", {})
	flow["current_story_node"] = str(index)
	save["flow_state"] = flow
	return SaveService.commit(save)

static func launch_battle() -> bool:
	var sid := str(state().get("pending_stage_id", ""))
	if sid.is_empty():
		return false
	PrototypeEntry.set_pending_stage_id(sid)
	return SceneRouter.go_to("battle")

static func after_battle() -> bool:
	var story_id := str(state().get("pending_story_after", ""))
	if not story_id.is_empty():
		return open_story(story_id, str(state().get("pending_stage_id", "")), "post_battle", true)
	return SceneRouter.go_to("home")

static func character_unlocked(cid: String) -> bool:
	if cid == "amamiya_mio":
		return true
	if cid == "kamiya_yuma":
		return done("ch1_1_3_before") or StageRewardService.is_first_cleared("1-3")
	if cid == "ogawa_yui":
		return done("ch1_1_6_before") or StageRewardService.is_first_cleared("1-6")
	if cid == "minase_sara":
		return done("ch1_1_8_before") or StageRewardService.is_first_cleared("1-8")
	if cid == "shiraishi_chinatsu":
		return StageRewardService.is_first_cleared("1-10") and done("ch1_1_10_after")
	if cid == "fujiwara_rin":
		return StageRewardService.is_first_cleared("1-5") and done("ch1_1_5_after")
	return false

## Replays may use the club member who joined after the fifth-stage ending.
## The immutable stage table and the first-clear two-person tutorial stay intact.
static func effective_stage_config(config: Dictionary) -> Dictionary:
	var result := config.duplicate(true)
	if str(result.get("stageId", "")) in ["1-3", "1-4", "1-5"] and character_unlocked("fujiwara_rin"):
		var roster: Array = result.get("availableCharacters", []).duplicate()
		if not roster.has("fujiwara_rin"):
			roster.append("fujiwara_rin")
		result["availableCharacters"] = roster
	if str(result.get("stageId", "")).begins_with("1-") and int(str(result.get("stageId", "1-0")).get_slice("-",1)) >= 6 and character_unlocked("shiraishi_chinatsu"):
		var roster: Array = result.get("availableCharacters", []).duplicate()
		if not roster.has("shiraishi_chinatsu"): roster.append("shiraishi_chinatsu")
		result["availableCharacters"] = roster
	return result
