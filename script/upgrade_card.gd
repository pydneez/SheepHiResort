class_name UpgradeCard
extends PanelContainer
## A single upgrade row card for the Upgrade Shop.
## Visual layout configured in `scene/upgrade_card.tscn` so it can be customized
## directly in the Godot inspector/editor.

signal buy_requested(upgrade_id: String)

@export var upgrade_id: String = ""

@onready var title_label: Label = %TitleLabel
@onready var desc_label: RichTextLabel = %DescLabel
@onready var rep_group: Control = %ReputationGroup
@onready var rep_label: Label = %ReputationLabel
@onready var cost_group: Control = %CostGroup
@onready var cost_label: Label = %CostLabel
@onready var buy_button: TextureButton = %BuyButton
@onready var icon_rect: TextureRect = %IconTextureRect

func _ready() -> void:
	if is_instance_valid(buy_button) and not buy_button.pressed.is_connected(_on_buy_pressed):
		buy_button.pressed.connect(_on_buy_pressed)
	if not upgrade_id.is_empty():
		update_display()

func _on_buy_pressed() -> void:
	buy_requested.emit(upgrade_id)

func set_upgrade_id(id: String) -> void:
	upgrade_id = id
	update_display()

## Refreshes titles, descriptions, reputation requirement, coin cost,
## and button interactivity based on current levels and player resources.
func update_display(cur_money: int = -1, cur_rep: int = -1) -> void:
	if upgrade_id.is_empty():
		return
	var info: Dictionary = GameManager.UPGRADE_CATALOG.get(upgrade_id, {})
	if info.is_empty():
		return

	if cur_money < 0:
		cur_money = GameManager.money
	if cur_rep < 0:
		cur_rep = GameManager.reputation

	var cur_lvl: int = GameManager.get_upgrade_level(upgrade_id)
	var max_lvl: int = int(info.get("max_level", 1))
	var is_infinite: bool = bool(info.get("infinite", false))
	var base_name: String = info.get("name", "Upgrade")

	# Set thumbnail icon if available
	if is_instance_valid(icon_rect):
		var icon_key: String = info.get("icon", "house")
		icon_rect.texture = UIPack.make_standalone_icon_atlas(icon_key)

	if not is_instance_valid(title_label) or not is_instance_valid(buy_button):
		return

	if not is_infinite and cur_lvl >= max_lvl:
		title_label.text = "%s (MAX)" % base_name if max_lvl == 1 else "%s Lv.%d (MAX)" % [base_name, cur_lvl]
		if is_instance_valid(desc_label):
			desc_label.text = info.get("desc_maxed", "")
		if is_instance_valid(rep_group):
			rep_group.visible = false
		if is_instance_valid(cost_group):
			cost_group.visible = false
		buy_button.disabled = true
		buy_button.modulate = Color(0.55, 0.55, 0.55, 0.6)
		buy_button.tooltip_text = "Maximum level reached"
	else:
		var next_lvl: int = cur_lvl + 1
		if is_infinite:
			title_label.text = "%s (Owned: %d)" % [base_name, cur_lvl] if cur_lvl > 0 else base_name
		else:
			title_label.text = base_name if max_lvl == 1 else "%s Lv.%d" % [base_name, next_lvl]

		var vals: Array = info.get("values", [0, 1])
		var tmpl: String = info.get("desc_template", "")
		if is_instance_valid(desc_label):
			if not is_infinite and max_lvl > 1 and vals.size() > next_lvl:
				desc_label.text = tmpl % [vals[cur_lvl], vals[next_lvl]]
			else:
				desc_label.text = tmpl

		var rep_arr: Array = info.get("reputation_req", [70])
		var cost_arr: Array = info.get("cost", [50])
		var req_rep: int = int(rep_arr[mini(cur_lvl, rep_arr.size() - 1)])
		var req_cost: int = int(cost_arr[mini(cur_lvl, cost_arr.size() - 1)])

		if is_instance_valid(rep_group):
			rep_group.visible = true
		if is_instance_valid(cost_group):
			cost_group.visible = true
		if is_instance_valid(rep_label):
			rep_label.text = "%d reputation" % req_rep
		if is_instance_valid(cost_label):
			cost_label.text = "%d" % req_cost

		var has_rep: bool = cur_rep >= req_rep
		var has_money: bool = cur_money >= req_cost

		if is_instance_valid(rep_label):
			rep_label.add_theme_color_override(
				"font_color",
				Color(0.24, 0.16, 0.10, 1.0) if has_rep else Color(0.85, 0.22, 0.22, 1.0)
			)
		if is_instance_valid(cost_label):
			cost_label.add_theme_color_override(
				"font_color",
				Color(0.24, 0.16, 0.10, 1.0) if has_money else Color(0.85, 0.22, 0.22, 1.0)
			)

		buy_button.disabled = false
		if has_rep and has_money:
			buy_button.modulate = Color.WHITE
			buy_button.tooltip_text = "Purchase %s (-$%d)" % [title_label.text, req_cost]
		else:
			buy_button.modulate = Color(0.65, 0.62, 0.60, 0.78)
			if not has_rep:
				buy_button.tooltip_text = "Not enough reputation"
			else:
				buy_button.tooltip_text = "Not enough coins"

