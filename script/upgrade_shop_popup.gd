class_name UpgradeShopPopup
extends Control
## Standalone Upgrade Shop Popup scene (`res://scene/upgrade_shop_popup.tscn`).
## Fully customizable visually inside the Godot editor.
## Handles upgrade purchases using Reputation as a qualification threshold
## and coins as the spent currency.

signal shop_closed
signal upgrade_purchased(upgrade_id: String, new_level: int)

const UPGRADE_CARD_CLASS := preload("res://script/upgrade_card.gd")

var front_desk: Node = null

@onready var backdrop: ColorRect = %Backdrop
@onready var board_root: Control = %ShopBoardRoot
@onready var close_btn: TextureButton = %CloseShopButton
@onready var cards_vbox: VBoxContainer = %CardsVBox
@onready var toast_label: Label = %ShopToastLabel
@onready var reputation_label: Label = %ReputationLabel
@onready var balance_label: Label = %BalanceLabel

func _ready() -> void:
	if is_instance_valid(backdrop) and not backdrop.gui_input.is_connected(_on_backdrop_gui_input):
		backdrop.gui_input.connect(_on_backdrop_gui_input)
	if is_instance_valid(close_btn) and not close_btn.pressed.is_connected(close_shop):
		close_btn.pressed.connect(close_shop)

	_connect_cards()
	refresh_ui()

func _connect_cards() -> void:
	
	if not is_instance_valid(cards_vbox):
		return
	for child in cards_vbox.get_children():
		if child is UPGRADE_CARD_CLASS or child.has_signal("buy_requested"):
			if not child.buy_requested.is_connected(_on_buy_upgrade_pressed):
				child.buy_requested.connect(_on_buy_upgrade_pressed)

func setup(desk_ref: Node) -> void:
	
	front_desk = desk_ref
	refresh_ui()

func refresh_ui() -> void:
	var cur_money: int = int(front_desk.get("money")) if is_instance_valid(front_desk) and "money" in front_desk else GameManager.money
	var cur_rep: int = int(front_desk.get("reputation")) if is_instance_valid(front_desk) and "reputation" in front_desk else GameManager.reputation

	if is_instance_valid(reputation_label):
		reputation_label.text = str(cur_rep)
	if is_instance_valid(balance_label):
		balance_label.text = str(cur_money)

	if is_instance_valid(cards_vbox):
		for child in cards_vbox.get_children():
			if child.has_method("update_display"):
				child.call("update_display", cur_money, cur_rep)

func _on_buy_upgrade_pressed(upg_id: String) -> void:
	var info: Dictionary = GameManager.UPGRADE_CATALOG.get(upg_id, {})
	if info.is_empty():
		return
	var cur_lvl: int = GameManager.get_upgrade_level(upg_id)
	var max_lvl: int = int(info.get("max_level", 1))
	var is_infinite: bool = bool(info.get("infinite", false))
	if not is_infinite and cur_lvl >= max_lvl:
		return

	var rep_arr: Array = info.get("reputation_req", [70])
	var cost_arr: Array = info.get("cost", [50])
	var req_rep: int = int(rep_arr[mini(cur_lvl, rep_arr.size() - 1)])
	var req_cost: int = int(cost_arr[mini(cur_lvl, cost_arr.size() - 1)])

	var cur_money: int = int(front_desk.get("money")) if is_instance_valid(front_desk) and "money" in front_desk else GameManager.money
	var cur_rep: int = int(front_desk.get("reputation")) if is_instance_valid(front_desk) and "reputation" in front_desk else GameManager.reputation

	# 1. Reputation threshold requirement (not consumed)
	if cur_rep < req_rep:
		_show_shop_toast("Not enough reputation!", Color(0.85, 0.22, 0.22))
		SfxManager.play_sfx("MissStep", "SFX")
		return

	# 2. Coin cost check
	if cur_money < req_cost:
		_show_shop_toast("Not enough coins!", Color(0.85, 0.22, 0.22))
		SfxManager.play_sfx("MissStep", "SFX")
		return

	# Deduct coins only
	cur_money -= req_cost
	GameManager.money = cur_money
	if is_instance_valid(front_desk):
		front_desk.set("money", cur_money)
		if front_desk.has_method("_refresh_hud"):
			front_desk.call("_refresh_hud")
			SfxManager.play_sfx("coins", "SFX")

	var new_lvl: int = cur_lvl + 1
	GameManager.upgrade_levels[upg_id] = new_lvl
	upgrade_purchased.emit(upg_id, new_lvl)

	_show_shop_toast("Purchased %s!" % info.get("name", "Upgrade"), Color(0.18, 0.55, 0.22))
	refresh_ui()

func _show_shop_toast(msg: String, col: Color) -> void:
	if not is_instance_valid(toast_label):
		return
	toast_label.text = msg
	toast_label.add_theme_color_override("font_color", col)
	

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close_shop()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_shop()
		get_viewport().set_input_as_handled()

func open_shop() -> void:
	SfxManager.play_sfx("PC_Press", "SFX")
	if is_instance_valid(toast_label):
		toast_label.text = ""
	refresh_ui()
	visible = true
	if is_instance_valid(board_root):
		board_root.pivot_offset = board_root.size * 0.5
		board_root.scale = Vector2(0.9, 0.9)
		var t := create_tween()
		t.tween_property(board_root, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close_shop() -> void:
	SfxManager.play_sfx("Button_hover", "SFX")
	visible = false
	shop_closed.emit()
