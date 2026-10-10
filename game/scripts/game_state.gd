extends Node
## 플레이어 성장·보유 상태. 퀘스트 보상은 claim_reward()로 한 번만 지급한다.

signal changed

## 레벨별 누적 필요 경험치 (index = 레벨). 기획서 5장의 초기 가설용 임시값.
const XP_TABLE: Array[int] = [0, 0, 100, 250, 450, 700, 1000, 1350, 1750]

## 무기 기본 배율. 강화 1단계마다 +8% (기획서 7장: 실패·파괴 없는 확정 강화, 첫 시제품은 +2까지).
const WEAPONS := {
	"연습용 목도": {"mult": 1.0, "trait": ""},
	"기본 장도": {"mult": 1.2, "trait": ""},
	"물길 장도": {"mult": 1.35, "trait": "회피 직후 첫 공격 시 결력 3 회복 (6초 대기)"},
}
const PLUS_BONUS := 0.08
const MAX_PLUS := 2

## 제작·강화 비용 (기획서 7장 첫 제작 가설)
const RECIPES := {
	"물길 장도": {"수초섬유": 3, "하천광": 2, "재화": 30},
}
const UPGRADE_COST := {
	1: {"하천광": 2, "재화": 20},
	2: {"하천광": 3, "재화": 30},
}

var level: int = 1
var xp: int = 0
var currency: int = 0
var items: Dictionary = {}
var skills: Array[String] = []
var weapon: String = "연습용 목도"
var weapon_plus: int = 0
var known_recipes: Array[String] = []
var claimed_rewards: Dictionary = {}
## 영물: 계약한 영물과 활성 칸. 첫 시제품은 활성 1칸 (기획서 6장 규칙 2).
var spirits: Array[String] = []
## 계약 전 임시 동행 (Q4의 줄비). 변신은 계약 뒤에만 가능하다.
var temp_spirits: Array[String] = []
var active_spirit: String = ""
## 퀘스트 기록 (예: Q3 성공 조건인 동행 탐지·장비 이동 효과 사용 여부)
var flags: Dictionary = {}

var ui_font: SystemFont
var world_font: SystemFont


func _ready() -> void:
	var names := PackedStringArray(["Malgun Gothic", "맑은 고딕", "Noto Sans CJK KR", "Noto Sans KR", "Apple SD Gothic Neo", "sans-serif"])
	ui_font = SystemFont.new()
	ui_font.font_names = names
	ui_font.font_weight = 600
	# 월드 글자는 카메라 확대 시 흐려지지 않도록 MSDF로 그린다.
	world_font = SystemFont.new()
	world_font.font_names = names
	world_font.font_weight = 700
	world_font.multichannel_signed_distance_field = true


func add_xp(amount: int) -> int:
	xp += amount
	var gained := 0
	while level + 1 < XP_TABLE.size() and xp >= XP_TABLE[level + 1]:
		level += 1
		gained += 1
	changed.emit()
	return gained


## 목표 레벨에 필요한 만큼만 경험치를 채운다. 이미 넘었으면 아무것도 하지 않는다.
func xp_to_level(target: int) -> int:
	if target < XP_TABLE.size() and xp < XP_TABLE[target]:
		return add_xp(XP_TABLE[target] - xp)
	return 0


func add_currency(amount: int) -> void:
	currency += amount
	changed.emit()


func add_item(id: String, count: int = 1) -> void:
	items[id] = int(items.get(id, 0)) + count
	if int(items[id]) <= 0:
		items.erase(id)
	changed.emit()


func count(id: String) -> int:
	return currency if id == "재화" else int(items.get(id, 0))


func has_skill(skill: String) -> bool:
	return skills.has(skill)


func learn_skill(skill: String) -> void:
	if not skills.has(skill):
		skills.append(skill)
		changed.emit()


func contract_spirit(id: String) -> void:
	if not spirits.has(id):
		spirits.append(id)
	temp_spirits.erase(id)
	if active_spirit == "":
		active_spirit = id
	changed.emit()


## 활성으로 고를 수 있는 영물 (계약 + 임시 동행)
func available_spirits() -> Array[String]:
	var out: Array[String] = spirits.duplicate()
	for id in temp_spirits:
		if not out.has(id):
			out.append(id)
	return out


func set_flag(id: String, value = true) -> void:
	flags[id] = value


func flag(id: String) -> bool:
	return bool(flags.get(id, false))


# ── 장비 ─────────────────────────────────────────────────

func weapon_multiplier() -> float:
	var base: float = WEAPONS.get(weapon, {"mult": 1.0})["mult"]
	return base * (1.0 + PLUS_BONUS * weapon_plus)


func weapon_label() -> String:
	return weapon + (" +%d" % weapon_plus if weapon_plus > 0 else "")


func weapon_trait() -> String:
	return String(WEAPONS.get(weapon, {"trait": ""})["trait"])


func can_pay(cost: Dictionary) -> bool:
	for k in cost:
		if count(k) < int(cost[k]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	for k in cost:
		if k == "재화":
			currency -= int(cost[k])
		else:
			add_item(k, -int(cost[k]))
	changed.emit()
	return true


func craft_weapon(id: String) -> bool:
	if not known_recipes.has(id) or not pay(RECIPES[id]):
		return false
	weapon = id
	weapon_plus = 0
	changed.emit()
	return true


func next_upgrade_cost() -> Dictionary:
	return UPGRADE_COST.get(weapon_plus + 1, {})


func can_upgrade() -> bool:
	return weapon != "연습용 목도" and weapon_plus < MAX_PLUS and can_pay(next_upgrade_cost())


func upgrade_weapon() -> bool:
	if weapon == "연습용 목도" or weapon_plus >= MAX_PLUS or not pay(next_upgrade_cost()):
		return false
	weapon_plus += 1
	changed.emit()
	return true


func claim_reward(id: String) -> bool:
	if claimed_rewards.has(id):
		return false
	claimed_rewards[id] = true
	return true
