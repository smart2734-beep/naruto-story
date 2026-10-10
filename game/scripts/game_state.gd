extends Node
## 플레이어 성장·보유 상태. 퀘스트 보상은 claim_reward()로 한 번만 지급한다.

signal changed

## 레벨별 누적 필요 경험치 (index = 레벨). 기획서 5장의 초기 가설용 임시값.
const XP_TABLE: Array[int] = [0, 0, 100, 250, 450, 700, 1000, 1350, 1750]

var level: int = 1
var xp: int = 0
var currency: int = 0
var items: Dictionary = {}
var skills: Array[String] = []
var weapon: String = "연습용 목도"
var claimed_rewards: Dictionary = {}

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
	changed.emit()


func has_skill(skill: String) -> bool:
	return skills.has(skill)


func learn_skill(skill: String) -> void:
	if not skills.has(skill):
		skills.append(skill)
		changed.emit()


func weapon_multiplier() -> float:
	return 1.2 if weapon == "기본 장도" else 1.0


func claim_reward(id: String) -> bool:
	if claimed_rewards.has(id):
		return false
	claimed_rewards[id] = true
	return true
