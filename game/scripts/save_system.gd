extends Node
## 로컬 저장 슬롯 1개 (docs/save-and-android-v0.1.md).
##   user://save_1.json  — 현재 저장
##   user://save_1.bak   — 직전 정상 저장 (교체 직전에 보관)
##   user://save_1.tmp   — 쓰는 중인 파일. flush·close 뒤에만 교체한다.
## 불러오기 순서: 현재 → 임시(교체 중 중단된 경우) → 백업. 모두 실패하면 원본을 지우지 않고 오류를 알린다.

signal saved(ok: bool)

const SCHEMA_VERSION := 1

var path := "user://save_1.json"
var enabled := true
var seq := 0  ## 저장 순번. 늦게 만든 스냅샷이 항상 더 큰 값을 가진다.
var last_error := ""
var loaded_from := ""  ## "main" / "tmp" / "backup"
var load_warning := ""  ## 현재 저장 대신 임시·백업으로 복구했을 때의 이유 (이후 저장해도 지우지 않는다)


func tmp_path() -> String:
	return path.get_basename() + ".tmp"


func bak_path() -> String:
	return path.get_basename() + ".bak"


func has_any_file() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(tmp_path()) or FileAccess.file_exists(bak_path())


## 스냅샷을 원자적으로 저장한다. 성공하면 true.
func save(snapshot: Dictionary) -> bool:
	if not enabled:
		return false
	seq += 1
	snapshot["schema_version"] = SCHEMA_VERSION
	snapshot["seq"] = seq
	snapshot["saved_at"] = Time.get_unix_time_from_system()
	var text := JSON.stringify(snapshot, "\t")
	var f := FileAccess.open(tmp_path(), FileAccess.WRITE)
	if f == null:
		return _fail("임시 파일을 열 수 없음 (%s)" % error_string(FileAccess.get_open_error()))
	f.store_string(text)
	f.flush()
	var write_err := f.get_error()
	f.close()
	if write_err != OK:
		return _fail("임시 파일 쓰기 실패 (%s)" % error_string(write_err))
	# 방금 쓴 파일을 다시 읽어 검증한 뒤에만 교체한다.
	var check := _read(tmp_path())
	if check.is_empty():
		return _fail("임시 파일 검증 실패: " + last_error)
	var abs_main := ProjectSettings.globalize_path(path)
	var abs_bak := ProjectSettings.globalize_path(bak_path())
	var abs_tmp := ProjectSettings.globalize_path(tmp_path())
	if FileAccess.file_exists(path) and _read(path).is_empty():
		# 현재 파일이 깨져 있으면 백업 자리로 옮기지 않는다 (직전 정상 백업을 지키고, 깨진 원본은 따로 보관).
		var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
		DirAccess.rename_absolute(abs_main, ProjectSettings.globalize_path(path.get_basename() + ".corrupt-%s.json" % stamp))
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path()):
			DirAccess.remove_absolute(abs_bak)
		var e1 := DirAccess.rename_absolute(abs_main, abs_bak)
		if e1 != OK:
			return _fail("기존 저장 보관 실패 (%s)" % error_string(e1))
	var e2 := DirAccess.rename_absolute(abs_tmp, abs_main)
	if e2 != OK:
		return _fail("저장 교체 실패 (%s)" % error_string(e2))
	last_error = ""
	saved.emit(true)
	return true


func _fail(msg: String) -> bool:
	last_error = msg
	push_warning("저장 실패: " + msg)
	saved.emit(false)
	return false


## 가장 최근의 정상 스냅샷을 돌려준다. 없거나 모두 깨졌으면 {} (last_error에 이유).
func load_latest() -> Dictionary:
	var errors: Array[String] = []
	for candidate in [[path, "main"], [tmp_path(), "tmp"], [bak_path(), "backup"]]:
		var p: String = candidate[0]
		if not FileAccess.file_exists(p):
			continue
		var d := _read(p)
		if not d.is_empty():
			loaded_from = candidate[1]
			seq = maxi(seq, int(d.get("seq", 0)))
			last_error = ""
			load_warning = "" if loaded_from == "main" else "현재 저장을 읽지 못해 %s 파일로 복구: %s" % [loaded_from, ", ".join(errors)]
			return d
		errors.append("%s: %s" % [candidate[1], last_error])
	last_error = ", ".join(errors) if not errors.is_empty() else "저장 없음"
	return {}


func _read(p: String) -> Dictionary:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		last_error = "열 수 없음"
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		last_error = "JSON 오류 %d행: %s" % [json.get_error_line(), json.get_error_message()]
		return {}
	var d = json.data
	if typeof(d) != TYPE_DICTIONARY:
		last_error = "최상위가 객체가 아님"
		return {}
	if int(d.get("schema_version", -1)) != SCHEMA_VERSION:
		last_error = "지원하지 않는 버전 %s" % str(d.get("schema_version", "?"))
		return {}
	var problem := validate(d)
	if problem != "":
		last_error = problem
		return {}
	return d


## 필수 키와 값의 형식·범위를 검사한다. 문제가 있으면 설명, 없으면 "".
func validate(d: Dictionary) -> String:
	for key in ["stage", "area", "resume", "game", "world", "nodes"]:
		if not d.has(key):
			return "필수 항목 없음: " + key
	var g = d["game"]
	if typeof(g) != TYPE_DICTIONARY:
		return "game 형식 오류"
	for key in ["level", "xp", "currency", "items", "skills", "weapon", "weapon_plus", "spirits", "active_spirit", "claimed_rewards", "flags"]:
		if not g.has(key):
			return "game." + key + " 없음"
	if int(g["level"]) < 1 or int(g["level"]) >= GameState.XP_TABLE.size() or int(g["xp"]) < 0 or int(g["currency"]) < 0:
		return "레벨·경험치·재화 범위 오류"
	if not GameState.WEAPONS.has(String(g["weapon"])) or int(g["weapon_plus"]) < 0 or int(g["weapon_plus"]) > GameState.MAX_PLUS:
		return "장비 값 오류"
	for id in g["spirits"]:
		if not String(id) in ["도톰", "줄비"]:
			return "알 수 없는 영물: " + str(id)
	if typeof(g["items"]) != TYPE_DICTIONARY:
		return "아이템 형식 오류"
	for k in g["items"]:
		if int(g["items"][k]) < 0:
			return "아이템 수량 음수: " + str(k)
	if not String(d["area"]) in ["overworld", "dungeon"]:
		return "지역 값 오류"
	var r = d["resume"]
	if typeof(r) != TYPE_ARRAY or r.size() != 2:
		return "재개 위치 형식 오류"
	return ""


## 저장 파일을 지우지 않고 다른 이름으로 보관한다 (새로 시작할 때). label: corrupt / old
func quarantine(label: String = "corrupt") -> Array[String]:
	var moved: Array[String] = []
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	for p: String in [path, tmp_path(), bak_path()]:
		if FileAccess.file_exists(p):
			var dst: String = p.get_basename() + ".%s-%s.%s" % [label, stamp, p.get_extension()]
			if DirAccess.rename_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(dst)) == OK:
				moved.append(dst)
	return moved
