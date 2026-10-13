## First-chapter front-end state. Uses the existing SaveGame.flow_state contract.
## Never advances a battle or grants rewards; those remain in their domain services.
class_name CampaignFlow
extends RefCounted

static var replay_story_id := ""
static var replay_return_key := "archive"
static var last_result: Dictionary = {}
static var inspected_character_id := "amamiya_mio"
static var open_campus_menu := false
static var briefing_return_key := "home"

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
	if not SaveService.new_game(player_name.strip_edges()):
		return false
	replay_story_id = ""
	replay_return_key = "archive"
	last_result = {}
	inspected_character_id = "amamiya_mio"
	if not persist({"campaign_active": true, "mode": "story", "current_story_id": "prologue_transfer",
		"current_story_node": "0", "pending_stage_id": "1-1", "last_stable_screen": "title"}):
		return false
	return SceneRouter.go_to("story")

static func resume() -> bool:
	replay_story_id = ""
	if not SaveService.ensure_loaded():
		return false
	var flow := state()
	var pending := str(flow.get("pending_story_after", ""))
	var current := str(flow.get("current_story_id", ""))
	if (not pending.is_empty() and not story_allowed(pending)) or (not current.is_empty() and not story_allowed(current)):
		if not persist({"pending_story_after":"", "current_story_id":"", "current_story_node":"", "mode":"hub"}):return false
		return SceneRouter.go_to("home")
	if not str(flow.get("pending_story_after", "")).is_empty():
		return open_story(str(flow["pending_story_after"]), str(flow.get("pending_stage_id", "")), "post_battle", true)
	if str(flow.get("mode", "hub")) == "story" and not str(flow.get("current_story_id", "")).is_empty():
		return SceneRouter.go_to("story")
	if str(flow.get("mode", "")) == "pre_battle":
		return SceneRouter.go_to("briefing")
	return SceneRouter.go_to("home")

static func continue_to_campus() -> bool:
	if not SaveService.ensure_loaded(): return false
	replay_story_id = ""
	briefing_return_key = "home"
	open_campus_menu = false
	# Landing in campus must not consume or reset an unfinished story/briefing.
	return SceneRouter.go_to("home")

static func briefing_back_key() -> String:
	return "stage_select" if briefing_return_key == "stage_select" else "home"

static func done(story_id: String) -> bool:
	return bool(SaveService.get_current().get("story", {}).get("flags", {}).get("done:" + story_id, false))

static func next_stage() -> String:
	for i: int in range(1, 11):
		var sid := "1-%d" % i
		if not StageRewardService.is_first_cleared(sid):
			return sid
	return ""

static func open_stage(sid: String,return_key: String = "home") -> bool:
	var cfg := DataRegistry.get_entry("stages", sid)
	if not can_open_stage(sid):
		return false
	briefing_return_key = "stage_select" if return_key == "stage_select" else "home"
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
	if not story_allowed(story_id):return false
	replay_story_id = ""
	var node := str(state().get("current_story_node", "0")) if preserve_node and str(state().get("current_story_id", "")) == story_id else "0"
	if not persist({"campaign_active": true, "mode": mode, "current_story_id": story_id,
		"current_story_node": node, "pending_stage_id": sid}):
		return false
	return SceneRouter.go_to("story")

static func finish_story(story_id: String) -> bool:
	var cfg := DataRegistry.get_entry("story", story_id)
	if not story_allowed(story_id):
		return false
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
	var optional := str(cfg.get("category", "")) in ["character_event", "environment_event"]
	flow["mode"] = "hub" if after or optional else "pre_battle"
	flow["current_story_id"] = ""
	flow["current_story_node"] = ""
	flow["pending_story_after"] = ""
	flow["last_stable_screen"] = "home"
	save["flow_state"] = flow
	if not SaveService.commit(save):
		return false
	return SceneRouter.go_to("home" if after or optional else "briefing")

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
	if not can_open_stage(sid):
		return false
	PrototypeEntry.set_pending_stage_id(sid)
	return SceneRouter.go_to("battle")

static func after_battle(victory: bool = true) -> bool:
	if not victory:
		if not record_failed_attempt_return():
			return false
		return SceneRouter.go_to("home")
	var story_id := str(state().get("pending_story_after", ""))
	if not story_id.is_empty() and story_allowed(story_id):
		return open_story(story_id, str(state().get("pending_stage_id", "")), "post_battle", true)
	return SceneRouter.go_to("home")

## A failed replay must not erase the required story earned by an earlier win.
## Failure itself creates neither a clear nor a new story entitlement.
static func record_failed_attempt_return() -> bool:
	var pending := str(state().get("pending_story_after", ""))
	var preserve := not pending.is_empty() and not done(pending) and story_allowed(pending)
	return persist({"mode":"post_battle" if preserve else "hub",
		"pending_story_after":pending if preserve else "",
		"current_story_id":pending if preserve else "",
		"current_story_node":str(state().get("current_story_node","0")) if preserve else ""})

## Entry guards apply to every menu, resume and battle launch, not only tiles.
static func can_open_stage(sid: String) -> bool:
	if not StageRewardService.cfg_has_content(DataRegistry.get_entry("stages",sid)):
		return false
	var pieces := sid.split("-")
	if pieces.size()!=2 or pieces[0]!="1" or not pieces[1].is_valid_int(): return false
	var number := int(pieces[1])
	if number<1 or number>10: return false
	for i: int in range(1,number):
		if not StageRewardService.is_first_cleared("1-%d" % i): return false
	return true

static func story_allowed(story_id: String) -> bool:
	var cfg := DataRegistry.get_entry("story",story_id)
	if cfg.is_empty():return false
	if str(cfg.get("category","")) in ["character_event","environment_event"]:
		return CampusHub.available(cfg)
	for i: int in range(1,11):
		var stage := DataRegistry.get_entry("stages","1-%d" % i)
		if str(stage.get("storyAfter",""))==story_id:
			return StageRewardService.is_first_cleared("1-%d" % i)
		if str(stage.get("storyBefore",""))==story_id:
			return can_open_stage("1-%d" % i)
	return true

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
