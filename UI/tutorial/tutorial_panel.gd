extends PanelContainer
class_name TutorialPanel

const PENDING_COLOR: Color = KeywordService.HIGHLIGHT_ACTION_COLOR
const COMPLETE_COLOR: Color = Color(0.42, 0.92, 0.5, 1.0)

@export var header_label: InteractiveRichTextLabel
@export var checklist_container: VBoxContainer
@export var paragraph_label: InteractiveRichTextLabel
@export var footer_label: InteractiveRichTextLabel

var _active_chapter: TutorialContent.Chapter
var _completed_facts: Dictionary[int, bool] = {}

func show_intro_chapter(chapter: TutorialContent.Chapter, completed_facts: Dictionary[int, bool]) -> void: ##renders onboarding conditions inline inside the main textbox so requirement text can recolor from blue to green as facts complete
	visible = true
	_active_chapter = chapter
	_completed_facts = completed_facts.duplicate()
	header_label.visible = false
	checklist_container.visible = false
	footer_label.visible = false
	footer_label.set_parsed_text("")
	paragraph_label.visible = true
	paragraph_label.set_parsed_text(_build_intro_text())

func show_legacy_message(text: String) -> void: ##reuses the same panel shell for queued one-shot tutorials without intro-specific inline condition text
	visible = true
	_active_chapter = null
	_completed_facts.clear()
	header_label.visible = false
	checklist_container.visible = false
	paragraph_label.visible = not text.is_empty()
	paragraph_label.set_parsed_text(text)
	footer_label.visible = false
	footer_label.set_parsed_text("")

func set_fact_completed(fact: int) -> void: ##updates the inline condition colors once a sticky onboarding fact completes
	if _active_chapter == null:
		return
	if _completed_facts.get(fact, false):
		return
	_completed_facts[fact] = true
	paragraph_label.set_parsed_text(_build_intro_text())

func clear_content() -> void:
	_active_chapter = null
	_completed_facts.clear()
	header_label.visible = false
	header_label.set_parsed_text("")
	checklist_container.visible = false
	paragraph_label.visible = false
	paragraph_label.set_parsed_text("")
	footer_label.visible = false
	footer_label.set_parsed_text("")
	visible = false

func _build_intro_text() -> String:
	if _active_chapter == null:
		return ""

	var lines: Array[String] = []
	for item: TutorialContent.ChecklistItem in _active_chapter.checklist_items:
		var color_hex: String = (COMPLETE_COLOR if _completed_facts.get(item.fact, false) else PENDING_COLOR).to_html(false)
		lines.append("[color=#%s]%s[/color]" % [color_hex, KeywordService.parse_text_for_bbcode(item.text)])

	var body_text: String = ""
	if not _active_chapter.paragraph_text.is_empty():
		body_text += KeywordService.parse_text_for_bbcode(_active_chapter.paragraph_text)
	if not lines.is_empty():
		if not body_text.is_empty():
			body_text += "\n\n"
		body_text += "\n\n".join(lines)
	if _is_active_chapter_complete() and not _active_chapter.footer_text.is_empty():
		if not body_text.is_empty():
			body_text += "\n\n"
		body_text += KeywordService.parse_text_for_bbcode(_active_chapter.footer_text)
	return body_text

func _is_active_chapter_complete() -> bool:
	for item: TutorialContent.ChecklistItem in _active_chapter.checklist_items:
		if not _completed_facts.get(item.fact, false):
			return false
	return true
