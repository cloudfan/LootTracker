local addonName, ns = ...
local API = ns.API

-- Loot Tracker's settings, in Blizzard's Options > AddOns (a canvas panel:
-- Settings.RegisterCanvasLayoutCategory, or the older Interface Options),
-- with simple controls of our own so they work on any client. /lt opens it.

local S = "lootTracker"

local function Get(key)
	return API.Get(S, key)
end
local function Set(key, value)
	API.Set(S, key, value)
end

local function Items(list)
	return function()
		return list
	end
end

local function MediaItems(kind, globalLabel)
	return function()
		local items = { { value = "global", label = globalLabel } }
		for _, name in ipairs(API.MediaList(kind)) do
			items[#items + 1] = { value = name, label = name }
		end
		return items
	end
end

-- The panel, a scroll frame in it --------------------------------------------------

local panel = CreateFrame("Frame", "LootTrackerSettingsPanel")
panel.name = "Loot Tracker"
panel:Hide()

local scroll = CreateFrame("ScrollFrame", nil, panel)
scroll:SetPoint("TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", -26, 8)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(560, 1)
scroll:SetScrollChild(content)
local bar = API.NewScrollBar(panel, scroll, 10, 40)
bar:SetPoint("TOPRIGHT", -8, -8)
bar:SetPoint("BOTTOMRIGHT", -8, 8)

local refreshers = {}
local y, rowHeight = 0, 0
local COLUMN = 280

local function Advance(height)
	y = y + height
end
local function Slot(col, height)
	rowHeight = math.max(rowHeight, height)
	return col == 2 and COLUMN or 8
end
local function EndRow()
	Advance(rowHeight + 6)
	rowHeight = 0
end

local function Header(text, big)
	Advance(y > 0 and 14 or 0)
	local fs = content:CreateFontString(nil, "OVERLAY", big and "GameFontNormalHuge" or "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", 8, -y)
	fs:SetText(text)
	Advance(fs:GetStringHeight() + 8)
end

local function Note(text)
	local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", 8, -y)
	fs:SetWidth(540)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	Advance(fs:GetStringHeight() + 8)
end

local function Tooltip(frame, title, text)
	if not text then
		return
	end
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 0.82, 0)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- disabled(): greys the control out while true.
local function Enable(frame, disabled, labels)
	if not disabled then
		return
	end
	refreshers[#refreshers + 1] = function()
		local off = disabled() and true or false
		if frame.SetEnabled then
			frame:SetEnabled(not off)
		end
		frame:SetAlpha(off and 0.5 or 1)
		for _, label in ipairs(labels or {}) do
			label:SetAlpha(off and 0.5 or 1)
		end
	end
end

local function Checkbox(col, label, key, tooltip, disabled, getter, setter)
	local x = Slot(col, 26)
	local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("TOPLEFT", x, -y)
	local text = check.Text or check.text
	if not text then
		text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", check, "RIGHT", 2, 0)
	end
	text:SetText(label)
	check:SetScript("OnClick", function(self)
		local on = self:GetChecked() and true or false
		if setter then
			setter(on)
		else
			Set(key, on)
		end
	end)
	Tooltip(check, label, tooltip)
	refreshers[#refreshers + 1] = function()
		check:SetChecked((getter and getter() or (not getter and Get(key))) and true or false)
	end
	Enable(check, disabled, { text })
end

local function Dropdown(col, label, key, items, tooltip, disabled)
	local x = Slot(col, 44)
	local caption = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	caption:SetPoint("TOPLEFT", x + 2, -y)
	caption:SetText(label)
	local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	button:SetSize(250, 22)
	button:SetPoint("TOPLEFT", x, -(y + 16))
	local function Label()
		for _, item in ipairs(items()) do
			if item.value == Get(key) then
				return item.label
			end
		end
		return tostring(Get(key))
	end
	button:SetScript("OnClick", function(self)
		local list = items()
		if MenuUtil and MenuUtil.CreateContextMenu then
			MenuUtil.CreateContextMenu(self, function(_, root)
				root:CreateTitle(label)
				for _, item in ipairs(list) do
					root:CreateRadio(item.label, function()
						return Get(key) == item.value
					end, function()
						Set(key, item.value)
					end)
				end
			end)
		else
			-- No menus on this client: each click picks the next choice.
			local index = 1
			for i, item in ipairs(list) do
				if item.value == Get(key) then
					index = i % #list + 1
				end
			end
			Set(key, list[index].value)
		end
	end)
	Tooltip(button, label, tooltip)
	refreshers[#refreshers + 1] = function()
		button:SetText(Label())
	end
	Enable(button, disabled, { caption })
end

local function Slider(col, label, key, min, max, step, format, disabled, tooltip)
	local x = Slot(col, 44)
	local caption = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	caption:SetPoint("TOPLEFT", x + 2, -y)
	local slider = CreateFrame("Slider", nil, content)
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(220, 16)
	slider:SetPoint("TOPLEFT", x + 4, -(y + 20))
	slider:SetMinMaxValues(min, max)
	slider:SetValueStep(step)
	if slider.SetObeyStepOnDrag then
		slider:SetObeyStepOnDrag(true)
	end
	local back = slider:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("LEFT")
	back:SetPoint("RIGHT")
	back:SetHeight(6)
	back:SetColorTexture(0, 0, 0, 0.6)
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	local function Show(value)
		caption:SetText(("%s: %s"):format(label, format and format(value) or tostring(value)))
	end
	local updating = false
	slider:SetScript("OnValueChanged", function(_, value)
		value = math.floor(value / step + 0.5) * step
		value = math.floor(value * 100 + 0.5) / 100
		Show(value)
		if not updating and value ~= Get(key) then
			Set(key, value)
		end
	end)
	slider:EnableMouseWheel(true)
	slider:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(self:GetValue() + delta * step)
	end)
	Tooltip(slider, label, tooltip)
	refreshers[#refreshers + 1] = function()
		updating = true
		slider:SetValue(Get(key))
		updating = false
		Show(Get(key))
	end
	Enable(slider, disabled, { caption })
end

local function Percent(value)
	return ("%d%%"):format(value * 100 + 0.5)
end

-- A color setting ({ preset = ... } or custom) from the game's color picker.
local function Color(col, label, key, disabled)
	local x = Slot(col, 26)
	local button = CreateFrame("Button", nil, content)
	button:SetSize(22, 22)
	button:SetPoint("TOPLEFT", x + 2, -(y + 2))
	local edge = button:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(1, 1, 1, 1)
	local swatch = button:CreateTexture(nil, "ARTWORK")
	swatch:SetPoint("TOPLEFT", 2, -2)
	swatch:SetPoint("BOTTOMRIGHT", -2, 2)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", button, "RIGHT", 6, 0)
	text:SetText(label)
	button:SetScript("OnClick", function()
		local r, g, b = API.ResolveColor(Get(key))
		local function Picked()
			local nr, ng, nb = ColorPickerFrame:GetColorRGB()
			Set(key, { preset = "custom", r = nr, g = ng, b = nb, a = 1 })
		end
		local function Cancelled()
			Set(key, { preset = "custom", r = r, g = g, b = b, a = 1 })
		end
		if ColorPickerFrame.SetupColorPickerAndShow then
			ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, swatchFunc = Picked, cancelFunc = Cancelled })
		else
			ColorPickerFrame.func = Picked
			ColorPickerFrame.cancelFunc = Cancelled
			ColorPickerFrame:SetColorRGB(r, g, b)
			ColorPickerFrame:Show()
		end
	end)
	refreshers[#refreshers + 1] = function()
		swatch:SetColorTexture(API.ResolveColor(Get(key)))
	end
	Enable(button, disabled, { text })
end

local function Button(col, text, onClick, tooltip)
	local x = Slot(col, 24)
	local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	button:SetSize(220, 22)
	button:SetPoint("TOPLEFT", x, -y)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	Tooltip(button, text, tooltip)
end

if StaticPopupDialogs then
	StaticPopupDialogs.LOOTTRACKER_RESET_SETTINGS = {
		text = "Put every Loot Tracker setting back to its default? (What you looted stays.)",
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function()
			API.ClearSection(S)
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
end

-- The settings (the same as CRPGui's Loot Tracker page) -----------------------------

local function Off(key)
	return function()
		return not Get(key)
	end
end

Header("Loot Tracker", true)
Note("What you loot and from what: creatures (a kill is a corpse you looted), their skinning and pickpocketing, chests, lockboxes, resource nodes, fishing and disenchanting, with gold and item values. Kept per character. The arrow in the window's title bar holds what is changed most; /lt opens this page.")

Header("Window")
Button(1, "Show or Hide the Window", function()
	ns.ToggleWindow()
end, "Shows or hides the window. Its close button hides it; this brings it back (so does /lt show).")
Checkbox(2, "Lock the window", "locked", "The window cannot be dragged by its title or resized. The lock button in its title bar does the same.")
EndRow()
Checkbox(1, "Creature portraits", "portraits", "A small 3D model of each creature beside its name.")
Dropdown(2, "Shows", "scope", Items({
	{ value = "all", label = "All Time" },
	{ value = "session", label = "This Session" },
	{ value = "instance", label = "This Instance" },
}), "Everything this character has tracked, this login only (a reload carries on), or the current instance run only.")
EndRow()
Dropdown(1, "Grouping", "grouping", Items({
	{ value = "grouped", label = "By Source" },
	{ value = "individual", label = "Each Loot" },
}), "One entry per source with everything it has given, or one entry per loot (the last 300).")
Dropdown(2, "Sort Sources", "entrySort", Items({
	{ value = "newest", label = "Newest First" },
	{ value = "value", label = "By Value" },
}), "The order of the sources.")
EndRow()
Dropdown(1, "Sort Items", "itemSort", Items({
	{ value = "quality", label = "By Quality" },
	{ value = "newest", label = "Newest First" },
	{ value = "value", label = "By Value" },
}), "The order of a source's items.")
Button(2, "Reset Position", function()
	API.Set("positions", "lootTracker", nil)
end, "The window back to its place on the right of the screen.")
EndRow()

Header("View")
Dropdown(1, "View", "view", Items({
	{ value = "list", label = "List" },
	{ value = "icons", label = "Icons" },
}), "List: a line per item, its name in its quality's color. Icons: a grid of item icons, each with its count and tooltip.")
Checkbox(2, "Item icons in the list", "listIcons", "List view: each item's icon before its name.", function()
	return Get("view") == "icons"
end)
EndRow()
Slider(1, "Icon Size", "iconSize", 16, 48, 1, nil, function()
	return Get("view") ~= "icons"
end, "Icons view: how large the icons are.")
Checkbox(2, "Stack value on item icons", "iconValue", "Icons view: the stack's auction value in each icon's top corner (gray: a vendor price standing in).", function()
	return Get("view") ~= "icons"
end)
EndRow()

Header("Text")
Dropdown(1, "Font", "font", MediaItems(API.MEDIA.FONT, "Default (Friz Quadrata)"), "Any font the game has, or that SharedMedia packs and other addons add.")
Dropdown(2, "Text Shadow", "fontShadow", Items({
	{ value = "global", label = "Default (Soft Shadow)" },
	{ value = "none", label = "None" },
	{ value = "soft", label = "Soft Shadow" },
	{ value = "outline", label = "Outline" },
	{ value = "thick", label = "Thick Outline" },
}))
EndRow()
Slider(1, "Text Size", "fontSize", 0, 24, 1, function(value)
	return value == 0 and "Auto" or tostring(value)
end, nil, "The item lines' size; names, values and the total follow in step. All the way left: the tracker's own sizes.")
EndRow()

Header("What Is Tracked")
Checkbox(1, "Only what you receive", "confirmLoot", "An item counts once the game says you received it, and gold once your purse grows, so lost rolls and others' shares never count.")
Checkbox(2, "Creatures", "trackCreatures", "Loot from corpses.")
EndRow()
Checkbox(1, "Skinning in the creature's entry", "skinningMerge", "Skinning loot goes into the creature's own entry instead of one of its own.", Off("trackCreatures"))
Checkbox(2, "Pickpocketing in the creature's entry", "pickpocketMerge", "Pickpocketing loot goes into the creature's own entry instead of one of its own.", Off("trackCreatures"))
EndRow()
Checkbox(1, "Chests", "trackChests", "Loot from chests and other containers in the world.")
Checkbox(2, "Lockboxes", "trackLockboxes", "Loot from lockboxes and other containers opened from your bags.")
EndRow()
Checkbox(1, "Disenchanting", "trackDisenchant", "What disenchanting gives, in one Disenchanted entry.")
Checkbox(2, "Resource nodes", "trackNodes", "Mining and herbalism nodes. Each gathering of a node counts: an ore vein gives several loots.")
EndRow()
Checkbox(1, "Fishing", "trackFishing", "What you fish up.")
Dropdown(2, "Fishing Entries", "fishingGrouping", Items({
	{ value = "zone", label = "By Zone" },
	{ value = "separated", label = "Schools Separately" },
}), "One entry per zone, or schools by their type.", Off("trackFishing"))
EndRow()

Header("Value")
Dropdown(1, "Item Value", "itemValue", Items({
	{ value = "auction", label = "Auction" },
	{ value = "vendor", label = "Vendor" },
	{ value = "none", label = "None" },
}), "What an item counts for: the last auction scan's lowest buyout (vendor value where it has none), vendor value, or nothing.")
Button(2, "Scan Now", function()
	ns.Scan()
end, "At the auction house: reads every auction's lowest price. The game allows it once every 15 minutes.")
EndRow()
Checkbox(1, "Scan button at the auction house", "auctionButton", "A Scan AH button on the auction house's Buy page.")
Checkbox(2, "Scan when the auction house opens", "auctionAutoScan", "A full scan each time it opens (it can stall the game a moment).")
EndRow()
Checkbox(1, "Learn prices while browsing", "auctionBrowse", "Browsing the auction house updates the prices it shows.")
Checkbox(2, "Auction price in our item tooltips", "tooltipAuction", "Under Sell Price in the tooltip of an item in the tracker.")
EndRow()
Checkbox(1, "Auction price in every item tooltip", "tooltipEverywhere", "Those lines in bags, links and everywhere else too.")
EndRow()

Header("Data")
Button(1, "Export", function()
	ns.Export()
end, "The shown entries as plain text, in a window to copy from.")
Button(2, "Export Name Database", function()
	ns.ExportNames()
end, "The creature and object names learned, as text to send for the shipped list.")
EndRow()
Button(1, "Reset All Loot...", function()
	StaticPopup_Show("LOOTTRACKER_RESET")
end, "Forgets everything the Loot Tracker has tracked on this character. It asks first.")
Button(2, "Reset All Settings...", function()
	StaticPopup_Show("LOOTTRACKER_RESET_SETTINGS")
end, "Every Loot Tracker setting back to its default. What you looted stays.")
EndRow()

content:SetHeight(y + 20)

local function RefreshAll()
	for _, fn in ipairs(refreshers) do
		fn()
	end
	bar:Update(content:GetHeight())
end

panel:SetScript("OnShow", RefreshAll)
scroll:SetScript("OnSizeChanged", function()
	content:SetWidth(math.max(1, scroll:GetWidth()))
	if panel:IsVisible() then
		RefreshAll()
	end
end)
API.Listen("SettingChanged", function()
	if panel:IsVisible() then
		RefreshAll()
	end
end)

-- Into Blizzard's options ----------------------------------------------------------

local category
if Settings and Settings.RegisterCanvasLayoutCategory then
	category = Settings.RegisterCanvasLayoutCategory(panel, "Loot Tracker")
	Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(panel)
end

function ns.OpenSettings()
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

-- Slash command ----------------------------------------------------------------------

SLASH_LOOTTRACKER1 = "/lt"
SLASH_LOOTTRACKER2 = "/loottracker"
SlashCmdList.LOOTTRACKER = function(msg)
	local command = strlower(strtrim(msg or ""))
	if command == "unlock" or command == "lock" then
		Set("locked", command == "lock")
		API.Print(command == "lock" and "locked." or "unlocked: drag the window by its title, resize it by its corner.")
	elseif command == "show" or command == "hide" or command == "toggle" then
		local collapsed = command == "hide" or (command == "toggle" and not Get("collapsed"))
		Set("collapsed", collapsed)
	elseif command == "export" then
		ns.Export()
	elseif command == "scan" then
		ns.Scan()
	elseif command == "probe" then
		API.ShowCopyBox("Loot Tracker probe", table.concat(API.ProbeLines(), "\n"))
	else
		ns.OpenSettings()
	end
end
