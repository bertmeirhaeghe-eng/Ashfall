class_name UiTheme
extends RefCounted
## Shared dark/gold UI theme for the HUD, menus and briefing screens.

const GOLD := Color(0.85, 0.66, 0.2)
const PANEL_BG := Color(0.055, 0.065, 0.08, 0.95)


static func make() -> Theme:
	var th := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_BG
	panel.border_color = GOLD.darkened(0.3)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(3)
	panel.set_content_margin_all(8)
	th.set_stylebox("panel", "PanelContainer", panel)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.11, 0.12, 0.15)
	normal.border_color = Color(0.3, 0.3, 0.34)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.17, 0.21)
	hover.border_color = GOLD
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.22, 0.2, 0.12)
	pressed.border_color = GOLD
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.08, 0.08, 0.09)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.border_color = GOLD.lightened(0.2)
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("hover_pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", focus)
	th.set_color("font_color", "Button", Color(0.9, 0.9, 0.88))
	th.set_color("font_hover_color", "Button", Color(1, 0.95, 0.8))
	th.set_color("font_pressed_color", "Button", GOLD)
	th.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.45))
	th.set_font_size("font_size", "Button", 13)
	th.set_color("font_color", "Label", Color(0.9, 0.9, 0.88))
	th.set_font_size("font_size", "Label", 13)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.8))
	th.set_constant("shadow_offset_x", "Label", 1)
	th.set_constant("shadow_offset_y", "Label", 1)
	th.set_color("default_color", "RichTextLabel", Color(0.9, 0.9, 0.88))
	th.set_font_size("normal_font_size", "RichTextLabel", 15)
	th.set_font_size("bold_font_size", "RichTextLabel", 15)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.1, 0.12)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = Color(0.3, 0.85, 0.4)
	th.set_stylebox("background", "ProgressBar", bar_bg)
	th.set_stylebox("fill", "ProgressBar", bar_fg)
	return th
