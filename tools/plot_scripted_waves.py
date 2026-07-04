from __future__ import annotations

import html
import pathlib
import re


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "Indexes" / "wave_enemies.gd"
CURRENT_OUTPUT_PATH = ROOT / "docs" / "scripted_wave_composition.svg"
COMPARISON_OUTPUT_PATH = ROOT / "docs" / "scripted_wave_comparison.svg"
PROPOSAL_OUTPUT_PATH = ROOT / "docs" / "proposed_scripted_waves.md"

PLUS_WEIGHT = 1.6

BASE_ENEMY_ORDER = [
	"BASIC",
	"BUFF",
	"DRIFTER",
	"WARRIOR",
	"HEALER",
	"TROLL",
	"GIANT",
	"SPRINTER",
	"ARCHER",
	"HULK",
]

FULL_ENEMY_ORDER = [
	"BASIC",
	"BUFF",
	"DRIFTER",
	"WARRIOR",
	"WARRIOR_PLUS",
	"HEALER",
	"TROLL",
	"TROLL_PLUS",
	"GIANT",
	"GIANT_PLUS",
	"SPRINTER",
	"SPRINTER_PLUS",
	"ARCHER",
	"HULK",
	"HULK_PLUS",
]

ENEMY_LABELS = {
	"BASIC": "Goblin",
	"BUFF": "Orc",
	"DRIFTER": "Assassin",
	"WARRIOR": "Warrior",
	"WARRIOR_PLUS": "Warrior+",
	"HEALER": "Healer",
	"TROLL": "Troll",
	"TROLL_PLUS": "Troll+",
	"GIANT": "Giant",
	"GIANT_PLUS": "Giant+",
	"SPRINTER": "Sprinter",
	"SPRINTER_PLUS": "Sprinter+",
	"ARCHER": "Archer",
	"HULK": "Hulk",
	"HULK_PLUS": "Hulk+",
}

COLORS = {
	"BASIC": "#d9c27a",
	"BUFF": "#c79b5f",
	"DRIFTER": "#9bc36d",
	"WARRIOR": "#a07c71",
	"WARRIOR_PLUS": "#844c48",
	"HEALER": "#77b7a4",
	"TROLL": "#6d9071",
	"TROLL_PLUS": "#6e5b51",
	"GIANT": "#7f8fb7",
	"GIANT_PLUS": "#71649c",
	"SPRINTER": "#c28ec7",
	"SPRINTER_PLUS": "#9f5f74",
	"ARCHER": "#d77f7f",
	"HULK": "#5d6b84",
	"HULK_PLUS": "#4b405f",
}

PROPOSED_WAVES: dict[int, dict[str, int]] = {
	1: {"BASIC": 4},
	2: {"BASIC": 6},
	3: {"BASIC": 1, "BUFF": 4},
	4: {"BASIC": 1, "DRIFTER": 5},
	5: {"BASIC": 4, "BUFF": 2, "DRIFTER": 4, "HEALER": 2},
	6: {"WARRIOR": 4},
	7: {"BASIC": 1, "BUFF": 3, "DRIFTER": 3, "WARRIOR": 4, "HEALER": 1},
	8: {"BASIC": 4, "WARRIOR": 6, "TROLL": 2},
	9: {"BUFF": 3, "DRIFTER": 4, "WARRIOR": 5, "TROLL": 3, "HEALER": 1},
	10: {"BUFF": 4, "DRIFTER": 5, "WARRIOR": 6, "TROLL": 4, "HEALER": 1},
	11: {"WARRIOR": 28, "HEALER": 2},
	12: {"GIANT": 8},
	13: {"GIANT": 8, "WARRIOR": 8, "HEALER": 2},
	14: {"SPRINTER": 24},
	15: {"BUFF": 1, "DRIFTER": 3, "WARRIOR": 10, "HEALER": 1, "TROLL": 5, "GIANT": 4, "SPRINTER": 8},
	16: {"WARRIOR": 12, "WARRIOR_PLUS": 12, "TROLL": 4, "SPRINTER": 2},
	17: {"WARRIOR": 8, "WARRIOR_PLUS": 10, "SPRINTER": 10, "HEALER": 3},
	18: {"HULK": 4, "WARRIOR": 10, "WARRIOR_PLUS": 10, "SPRINTER": 8},
	19: {"HULK": 4, "WARRIOR": 8, "WARRIOR_PLUS": 8, "GIANT": 6, "TROLL": 4, "HEALER": 2},
	20: {"GIANT_PLUS": 10, "GIANT": 4, "WARRIOR": 12, "HEALER": 2},
	21: {"HULK": 4, "WARRIOR": 8, "WARRIOR_PLUS": 12, "GIANT_PLUS": 8, "SPRINTER": 4, "SPRINTER_PLUS": 6, "TROLL": 4, "HEALER": 3},
	22: {"HULK": 4, "HULK_PLUS": 6, "WARRIOR": 6, "WARRIOR_PLUS": 14, "SPRINTER": 3, "SPRINTER_PLUS": 10, "TROLL": 4},
	23: {"HULK_PLUS": 6, "GIANT_PLUS": 4, "WARRIOR": 4, "WARRIOR_PLUS": 18, "SPRINTER": 2, "SPRINTER_PLUS": 14, "TROLL": 4, "HEALER": 4},
	24: {"HULK": 4, "HULK_PLUS": 8, "GIANT_PLUS": 6, "WARRIOR": 2, "WARRIOR_PLUS": 25, "SPRINTER": 2, "SPRINTER_PLUS": 20, "TROLL": 6, "HEALER": 5},
}


def main() -> None:
	current_waves = _apply_runtime_scaling(_parse_scripted_waves(SOURCE_PATH.read_text(encoding="utf-8")))
	proposed_waves = _apply_runtime_scaling(PROPOSED_WAVES)
	CURRENT_OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
	CURRENT_OUTPUT_PATH.write_text(
		_build_single_chart_svg(
			current_waves,
			title="Current Scripted Wave Enemy Composition",
			subtitle="normal runtime counts after wave scaling",
			enemy_order=BASE_ENEMY_ORDER,
			pressure_label="total enemies",
		),
		encoding="utf-8",
	)
	COMPARISON_OUTPUT_PATH.write_text(
		_build_comparison_svg(current_waves, proposed_waves),
		encoding="utf-8",
	)
	PROPOSAL_OUTPUT_PATH.write_text(_build_proposal_markdown(PROPOSED_WAVES, proposed_waves), encoding="utf-8")
	print(f"wrote {CURRENT_OUTPUT_PATH}")
	print(f"wrote {COMPARISON_OUTPUT_PATH}")
	print(f"wrote {PROPOSAL_OUTPUT_PATH}")


def _parse_scripted_waves(source: str) -> dict[int, dict[str, int]]:
	waves: dict[int, dict[str, int]] = {}
	stack_pattern = re.compile(r"Units\.Type\.([A-Z_]+)\s*,\s*(\d+)")
	current_wave: int | None = None
	current_counts: dict[str, int] = {}

	for raw_line in source.splitlines():
		line = raw_line.strip()
		wave_match = re.match(r"(\d+)\s*:\s*\[$", line)
		if wave_match:
			current_wave = int(wave_match.group(1))
			current_counts = {}
			continue

		if current_wave is None:
			continue

		if line == "],":
			waves[current_wave] = current_counts
			current_wave = None
			current_counts = {}
			continue

		stack_match = stack_pattern.search(line)
		if not stack_match:
			continue

		enemy_type, count_text = stack_match.groups()
		current_counts[enemy_type] = current_counts.get(enemy_type, 0) + int(count_text)

	return dict(sorted(waves.items()))


def _apply_runtime_scaling(waves: dict[int, dict[str, int]]) -> dict[int, dict[str, int]]:
	scaled_waves: dict[int, dict[str, int]] = {}
	for wave, counts in waves.items():
		scale = _get_normal_wave_scale(wave)
		scaled_counts: dict[str, int] = {}
		for enemy_type, count in counts.items():
			scaled_counts[enemy_type] = round(count * scale)
		scaled_waves[wave] = scaled_counts
	return scaled_waves


def _get_normal_wave_scale(wave: int) -> float:
	return 1.0 + max(wave - 3, 0) * 0.05


def _build_single_chart_svg(
	waves: dict[int, dict[str, int]],
	*,
	title: str,
	subtitle: str,
	enemy_order: list[str],
	pressure_label: str,
) -> str:
	panel = _build_chart_panel(
		waves,
		title=title,
		subtitle=subtitle,
		enemy_order=enemy_order,
		pressure_label=pressure_label,
		panel_x=0,
		panel_y=0,
		panel_width=980,
		panel_height=760,
	)
	return "\n".join(
		[
			f'<svg xmlns="http://www.w3.org/2000/svg" width="{panel["width"]}" height="{panel["height"]}" viewBox="0 0 {panel["width"]} {panel["height"]}" fill="none">',
			'<rect width="100%" height="100%" fill="#f7f1df"/>',
			panel["content"],
			"</svg>",
		]
	)


def _build_comparison_svg(current_waves: dict[int, dict[str, int]], proposed_waves: dict[int, dict[str, int]]) -> str:
	panel_width = 980
	panel_height = 640
	gap = 40
	top_panel = _build_chart_panel(
		current_waves,
		title="Current Scripted Waves",
		subtitle="raw scripted counts by wave",
		enemy_order=FULL_ENEMY_ORDER,
		pressure_label="total enemies",
		panel_x=0,
		panel_y=0,
		panel_width=panel_width,
		panel_height=panel_height,
	)
	bottom_panel = _build_chart_panel(
		proposed_waves,
		title="Proposed Redesign",
		subtitle="normal-baseline roster with '+' enemies weighted as 1.6x on the pressure line",
		enemy_order=FULL_ENEMY_ORDER,
		pressure_label="normal-equivalent pressure",
		panel_x=0,
		panel_y=panel_height + gap,
		panel_width=panel_width,
		panel_height=panel_height,
	)
	width = panel_width
	height = panel_height * 2 + gap

	return "\n".join(
		[
			f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" fill="none">',
			'<rect width="100%" height="100%" fill="#f7f1df"/>',
			top_panel["content"],
			bottom_panel["content"],
			_text(width - 22, 26, "pressure line", 12, "#4b5f8a", anchor="end", weight="700"),
			"</svg>",
		]
	)


def _build_chart_panel(
	waves: dict[int, dict[str, int]],
	*,
	title: str,
	subtitle: str,
	enemy_order: list[str],
	pressure_label: str,
	panel_x: int,
	panel_y: int,
	panel_width: int,
	panel_height: int,
) -> dict[str, str | int]:
	margin_left = 78
	margin_right = 24
	margin_top = 64
	margin_bottom = 136
	chart_height = 360
	bar_width = 22
	bar_gap = 8
	chart_width = len(waves) * (bar_width + bar_gap) - bar_gap
	chart_x = panel_x + margin_left
	chart_y = panel_y + margin_top
	max_total = max(sum(counts.values()) for counts in waves.values())
	max_pressure = max(_get_pressure_total(counts) for counts in waves.values())
	usable_max = _ceil_step(max(max_total, max_pressure), 10)
	scale = chart_height / usable_max
	legend_columns = 5
	legend_x = chart_x
	legend_y = panel_y + panel_height - 82

	parts: list[str] = [
		_text(panel_x + panel_width / 2, panel_y + 28, title, 24, "#44382f", anchor="middle", weight="700"),
		_text(panel_x + panel_width / 2, panel_y + 50, subtitle, 13, "#76675a", anchor="middle"),
	]

	for tick in range(0, usable_max + 1, 10):
		y = chart_y + chart_height - tick * scale
		parts.append(
			f'<line x1="{chart_x}" y1="{y:.2f}" x2="{chart_x + chart_width}" y2="{y:.2f}" stroke="#dfd2bb" stroke-width="1"/>'
		)
		parts.append(_text(chart_x - 10, y + 4, str(tick), 12, "#76675a", anchor="end"))

	parts.append(
		f'<line x1="{chart_x}" y1="{chart_y}" x2="{chart_x}" y2="{chart_y + chart_height}" stroke="#8b7c6c" stroke-width="1.5"/>'
	)
	parts.append(
		f'<line x1="{chart_x}" y1="{chart_y + chart_height}" x2="{chart_x + chart_width}" y2="{chart_y + chart_height}" stroke="#8b7c6c" stroke-width="1.5"/>'
	)

	line_points: list[tuple[float, float]] = []
	for index, (wave_number, counts) in enumerate(waves.items()):
		x = chart_x + index * (bar_width + bar_gap)
		y_cursor = chart_y + chart_height
		total = sum(counts.values())
		for enemy_type in enemy_order:
			count = counts.get(enemy_type, 0)
			if count <= 0:
				continue
			segment_height = count * scale
			y_cursor -= segment_height
			parts.append(
				f'<rect x="{x}" y="{y_cursor:.2f}" width="{bar_width}" height="{segment_height:.2f}" fill="{COLORS[enemy_type]}" stroke="#f7f1df" stroke-width="1"/>'
			)

		pressure_total = _get_pressure_total(counts)
		line_x = x + bar_width / 2
		line_y = chart_y + chart_height - pressure_total * scale
		line_points.append((line_x, line_y))

		parts.append(_text(x + bar_width / 2, chart_y + chart_height + 18, str(wave_number), 11, "#5b4d42", anchor="middle"))
		parts.append(_text(x + bar_width / 2, y_cursor - 8, str(total), 11, "#4b3f36", anchor="middle", weight="700"))

	if line_points:
		point_string = " ".join(f"{x:.2f},{y:.2f}" for x, y in line_points)
		parts.append(
			f'<polyline fill="none" stroke="#4b5f8a" stroke-width="2.5" points="{point_string}"/>'
		)
		for x, y in line_points:
			parts.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="2.8" fill="#4b5f8a"/>')

	parts.append(_text(chart_x + chart_width / 2, panel_y + panel_height - 112, "Wave", 14, "#5b4d42", anchor="middle", weight="700"))
	parts.append(
		f'<g transform="translate({panel_x + 22}, {chart_y + chart_height / 2}) rotate(-90)">' +
		_text(0, 0, "Enemy Count", 14, "#5b4d42", anchor="middle", weight="700") +
		"</g>"
	)
	parts.append(_text(chart_x + chart_width, chart_y - 10, pressure_label, 12, "#4b5f8a", anchor="end", weight="700"))

	for index, enemy_type in enumerate(enemy_order):
		column = index % legend_columns
		row = index // legend_columns
		x = legend_x + column * 164
		y = legend_y + row * 24
		parts.append(f'<rect x="{x}" y="{y}" width="16" height="16" rx="3" fill="{COLORS[enemy_type]}"/>')
		parts.append(_text(x + 24, y + 12, ENEMY_LABELS[enemy_type], 12, "#4b3f36"))

	return {
		"width": panel_width,
		"height": panel_height,
		"content": "\n".join(parts),
	}


def _build_proposal_markdown(raw_waves: dict[int, dict[str, int]], scaled_waves: dict[int, dict[str, int]]) -> str:
	lines = [
		"# Proposed Scripted Wave Redesign",
		"",
		"raw composition is the authored pre-scale roster. scaled totals assume Normal difficulty wave scaling from `phase_manager.gd`.",
		"",
		"| Wave | Raw Composition | Raw Total | Runtime Total | Runtime Pressure |",
		"| --- | --- | ---: | ---: | ---: |",
	]
	for wave, counts in raw_waves.items():
		composition = ", ".join(
			f"{ENEMY_LABELS[enemy]} x{count}"
			for enemy, count in counts.items()
			if count > 0
		)
		scaled_counts = scaled_waves[wave]
		lines.append(
			f"| {wave} | {composition} | {sum(counts.values())} | {sum(scaled_counts.values())} | {_get_pressure_total(scaled_counts):.1f} |"
		)
	return "\n".join(lines) + "\n"


def _get_pressure_total(counts: dict[str, int]) -> float:
	total = 0.0
	for enemy_type, count in counts.items():
		if enemy_type.endswith("_PLUS"):
			total += count * PLUS_WEIGHT
		else:
			total += count
	return total


def _ceil_step(value: float, step: int) -> int:
	return int(((value + step - 1) // step) * step)


def _text(
	x: float,
	y: float,
	value: str,
	size: int,
	color: str,
	*,
	anchor: str = "start",
	weight: str = "500",
) -> str:
	return (
		f'<text x="{x:.2f}" y="{y:.2f}" font-family="Arial, sans-serif" font-size="{size}" '
		f'fill="{color}" text-anchor="{anchor}" font-weight="{weight}">{html.escape(value)}</text>'
	)


if __name__ == "__main__":
	main()
