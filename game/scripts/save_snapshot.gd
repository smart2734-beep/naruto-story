extends RefCounted
## 게임 상태 ↔ 저장 스냅샷 (schema_version 1).
## 저장하지 않는 것: 카메라 이동, 대사 진행, 적의 예고·위치, 회피·변신·기술 중간 타이머, 체력·결력(재개 시 가득).
## 재개 위치는 항상 안전한 체크포인트다 (틈 위·난간 안·쓰러지는 중 위치에서 재개하지 않는다).

const Main := preload("res://scripts/main.gd")
const Dotom := preload("res://scripts/spirit_dotom.gd")
const Julbi := preload("res://scripts/spirit_julbi.gd")
const Worker := preload("res://scripts/npc_worker.gd")
const Boss := preload("res://scripts/enemy_boss_claw.gd")
const World := preload("res://scripts/world.gd")
const Dungeon := preload("res://scripts/dungeon.gd")


static func _v(p: Vector2) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]


static func _p(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## 저장·불러오기 대상 상호작용물 (안정적인 ID → 노드)
static func saveables(m) -> Dictionary:
	var d := {
		"danu": m.danu, "crate": m.crate, "haon": m.haon, "maedeup": m.maedeup,
		"anchor": m.anchor_spot, "pressure_handle": m.handle_spot,
		"dogyeom": m.dogyeom, "bench_village": m.bench_village, "bench_mill": m.bench_mill, "ring": m.ring_spot,
		"hatch": m.hatch_spot, "plaque": m.plaque_spot, "wheel_l": m.handle_l_spot, "wheel_r": m.handle_r_spot,
		"sluice": m.sluice_spot, "core": m.core_spot, "worker": m.worker,
	}
	for i in m.ropes.size():
		d["rope%d" % i] = m.ropes[i]
	for i in m.hooks.size():
		d["hook%d" % i] = m.hooks[i]
	return d


## 지금 상태로 이어서 할 때 돌아갈 안전 지점
static func resume_point(m) -> Vector2:
	var p: Vector2 = m.player.position
	if m.in_dungeon:
		return m.dungeon.checkpoint_for(p)
	if p.x < World.COL_W and p.y > World.FIELD_BOTTOM:
		return Main.VILLAGE_START
	return m.checkpoint_for(p)


static func build(m) -> Dictionary:
	var gs = GameState
	var nodes := {}
	var sv := saveables(m)
	for id in sv:
		var n = sv[id]
		nodes[id] = {"pos": _v(n.position), "visible": n.visible, "interactable": n.interactable, "checked": n.checked,
			"name": n.display_name, "label": n.action_label}
	var w = m.world
	var revealed: Array = []
	for wp in w.weak_planks:
		revealed.append(wp["revealed"])
	var leaves: Array = []
	for lp in w.leaf_marks:
		leaves.append(_v(lp))
	return {
		"stage": Main.Stage.keys()[m.stage],
		"area": "dungeon" if m.in_dungeon else "overworld",
		"resume": _v(resume_point(m)),
		"carrying": m.player.carrying,
		"gear": m.player.gear,
		"once": m._once.duplicate(),
		"game": {
			"level": gs.level, "xp": gs.xp, "currency": gs.currency, "items": gs.items.duplicate(),
			"skills": Array(gs.skills), "weapon": gs.weapon, "weapon_plus": gs.weapon_plus,
			"known_recipes": Array(gs.known_recipes), "claimed_rewards": gs.claimed_rewards.duplicate(),
			"spirits": Array(gs.spirits), "temp_spirits": Array(gs.temp_spirits), "active_spirit": gs.active_spirit,
			"flags": gs.flags.duplicate(),
		},
		"world": {
			"east_open": not w.blocker_enabled("east_barrier"),
			"steps_open": not w.blocker_enabled("steps_barrier"),
			"anchor_built": w.anchor_built, "gap_fixed": w.gap_fixed, "backflow": w.backflow,
			"hatch_open": w.hatch_open, "plank_revealed": revealed, "leaf_marks": leaves,
		},
		"dotom": {"nest_pos": _v(m.dotom.nest_pos), "nest_at_home": m.dotom.nest_at_home},
		"dungeon": {"drained": m.dungeon.drained, "handle_l": m.dungeon.handle_l, "handle_r": m.dungeon.handle_r,
			"boss_stopped": not m.boss.alive},
		"worker": {"state": Worker.WState.keys()[m.worker.wstate]},
		"nodes": nodes,
	}


## 스냅샷을 적용한다. 진행 중간에 끊긴 단계는 이어갈 수 있는 단계로 정리한다.
static func apply(m, d: Dictionary) -> void:
	var gs = GameState
	var g: Dictionary = d["game"]
	gs.level = int(g["level"])
	gs.xp = int(g["xp"])
	gs.currency = int(g["currency"])
	gs.items = {}
	for k in g["items"]:
		gs.items[String(k)] = int(g["items"][k])
	gs.skills.assign(g["skills"])
	gs.weapon = String(g["weapon"])
	gs.weapon_plus = int(g["weapon_plus"])
	gs.known_recipes.assign(g.get("known_recipes", []))
	gs.claimed_rewards = (g["claimed_rewards"] as Dictionary).duplicate()
	gs.spirits.assign(g["spirits"])
	gs.temp_spirits.assign(g.get("temp_spirits", []))
	gs.active_spirit = String(g["active_spirit"])
	gs.flags = (g["flags"] as Dictionary).duplicate()
	m._once = (d.get("once", {}) as Dictionary).duplicate()

	# 지도 변화
	var w = m.world
	var wd: Dictionary = d["world"]
	w.set_blocker("east_barrier", not bool(wd["east_open"]))
	w.set_blocker("steps_barrier", not bool(wd["steps_open"]))
	if bool(wd["anchor_built"]):
		w.build_anchor()
	if bool(wd["gap_fixed"]):
		w.fix_gap()
	w.backflow = float(wd["backflow"])
	w.hatch_open = bool(wd["hatch_open"])
	var revealed: Array = wd.get("plank_revealed", [])
	for i in mini(revealed.size(), w.weak_planks.size()):
		w.weak_planks[i]["revealed"] = bool(revealed[i])
	w.leaf_marks.clear()
	for lp in wd.get("leaf_marks", []):
		w.leaf_marks.append(_p(lp))

	# 상호작용물
	var sv := saveables(m)
	var nd: Dictionary = d["nodes"]
	for id in sv:
		if not nd.has(id):
			continue
		var n = sv[id]
		var s: Dictionary = nd[id]
		n.position = _p(s["pos"])
		n.visible = bool(s["visible"])
		n.interactable = bool(s["interactable"])
		n.checked = bool(s["checked"])
		n.display_name = String(s["name"])
		n.action_label = String(s["label"])
		n.walk_target = null

	# 던전
	var dg: Dictionary = d["dungeon"]
	m.dungeon.restore(int(dg["handle_l"]), int(dg["handle_r"]), bool(dg["drained"]))
	if bool(dg["boss_stopped"]):
		m.boss.restore_stopped()

	# 도톰 둥지 위치는 단계 정리보다 먼저 되살린다 (정리 단계가 고칠 수 있게)
	m.dotom.nest_pos = _p(d["dotom"]["nest_pos"])
	m.dotom.nest_at_home = bool(d["dotom"]["nest_at_home"])
	var stage: int = Main.Stage.get(String(d["stage"]), Main.Stage.TALK_DANU)
	stage = _normalize(m, stage, d)

	# 영물 노드와 장비 상태
	var gear := String(d.get("gear", ""))
	if not gs.spirits.has(gear):
		gear = ""
	m.player.gear = gear if gear == gs.active_spirit else ""
	for id in ["도톰", "줄비"]:
		var node = m.spirit_nodes[id]
		if gs.available_spirits().has(id):
			if id == gs.active_spirit:
				if m.player.gear == id:
					node.equip()
				else:
					node.become_companion()
			else:
				node.rest()
	if not gs.available_spirits().has("도톰"):
		m.dotom.state = Dotom.State.NEST
		m.dotom.position = World.NEST_POS
		m.dotom.calm_enabled = stage == Main.Stage.Q2_CALM

	# 재개 위치와 지역
	m.in_dungeon = String(d["area"]) == "dungeon"
	m._apply_camera_limits(m.DUNGEON_LIMITS if m.in_dungeon else m.OVERWORLD_LIMITS)
	var at := _p(d["resume"])
	if stage == Main.Stage.Q5_BOSS:
		at = Dungeon.ROOM3_START
	elif stage == Main.Stage.Q5_END:
		at = m.danu.position + Vector2(0, 40)
	m.player.respawn(at)
	m.player.dead = false
	m.player.hp = m.player.max_hp
	m.player.carrying = bool(d.get("carrying", false))
	m.camera.reset_smoothing()
	var active = m.active_node()
	if active != null and active.visible:
		active.position = at + Vector2(14, 6)

	# 정비공
	var ws := String(d["worker"]["state"])
	match stage:
		Main.Stage.Q5_ESCORT:
			m.worker.reset_at(at + Vector2(-24, 0), Worker.WState.FOLLOW)
		Main.Stage.Q5_BOSS, Main.Stage.Q5_CORE:
			m.worker.reset_at(Dungeon.WAIT_SPOT, Worker.WState.WAIT)
		_:
			if Worker.WState.has(ws):
				m.worker.wstate = Worker.WState[ws]
	if stage == Main.Stage.Q5_END:
		m.worker.visible = false
		m.worker.interactable = false

	m.hud.hud_reset()
	m.stage = stage
	m._enter_stage(stage)
	m._refresh_spirit_hud()
	if stage == Main.Stage.Q5_BOSS:
		m.boss.reset_fight()
		m.boss.wake()


## 대사 콜백이나 연출 도중에 끊긴 단계를, 이미 지급된 보상·장비를 확인해 이어갈 단계로 바꾼다.
static func _normalize(m, stage: int, d: Dictionary) -> int:
	var gs = GameState
	var S = Main.Stage
	if stage == S.BACKFLOW:
		# Q1 보상은 이미 받았다. 역류 연출 뒤의 매듭 대화부터.
		m.world.backflow = 1.0
		m.maedeup.visible = true
		m.maedeup.interactable = true
		m.maedeup.position = Vector2(220, 200)
		stage = S.TALK_MAEDEUP
	if (stage == S.Q2_FOLLOW or stage == S.Q2_CONTRACT) and not gs.claimed_rewards.has("Q2"):
		# 도톰 안내 도중: 둥지 곁에서 다시 다가가기부터 (계약 전이라 잃는 것 없음)
		m.dotom.nest_at_home = true
		m.dotom.nest_pos = World.NEST_POS
		m.dotom.has_nest = false
		stage = S.Q2_CALM
	if gs.claimed_rewards.has("Q3"):
		# 압력을 뺐다: 역류 연출 중간 값으로 저장됐어도 멈춘 물길로 되살린다.
		m.world.fix_gap()
		m.world.backflow = 0.0
		m.handle_spot.interactable = false
		if stage < S.Q3_DONE:
			stage = S.Q3_DONE
	if stage == S.Q4_CRAFT and gs.weapon == "물길 장도":
		stage = S.Q4_GO_MILL  # 제작은 끝났다. 재료를 다시 요구하지 않는다.
	# Q4_UPGRADE에서 이미 +1이면 main.load_snapshot()이 완료를 인정한다.
	if gs.claimed_rewards.has("Q5") and stage < S.Q5_END:
		m.boss.restore_stopped()
		stage = S.Q5_END
	if stage == S.Q5_END:
		d["area"] = "overworld"
	return stage
