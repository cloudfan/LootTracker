local addonName, ns = ...
local API = ns.API

-- Loot Tracker's settings, in Blizzard's Options > AddOns (a canvas panel:
-- Settings.RegisterCanvasLayoutCategory, or the older Interface Options),
-- with simple controls of our own so they work on any client. /loot opens it.

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

-- The settings ---------------------------------------------------------------------

local function Off(key)
	return function()
		return not Get(key)
	end
end
local function NotList()
	return Get("view") ~= "list"
end

Header("Loot Tracker", true)
Note("What you loot and from what: creatures (a kill is a corpse you looted), their skinning and pickpocketing, chests, lockboxes, resource nodes and fishing. Gold is shown beside each source's name, with its items' value if you like. Kept per character. /loot opens this page, /loot unlock lets you drag the tracker.")

Header("Tracking")
Dropdown(1, "Grouping", "grouping", Items({
	{ value = "grouped", label = "Grouped (merged by ID)" },
	{ value = "individual", label = "Individualized (each loot)" },
}), "Grouped: every kill is kept, and creatures (or chests, nodes, ...) of the same ID share one entry. Individualized: one entry per loot, newest first (the last 300).")
Dropdown(2, "Show", "scope", Items({
	{ value = "all", label = "All Time" },
	{ value = "session", label = "This Session (since login)" },
	{ value = "instance", label = "This Instance (the current run)" },
}), "All Time: everything kept. This Session: since you logged in (a reload carries on). This Instance: since you entered the instance you are in, or were last in. Also in the menu by the tracker's title.")
EndRow()
Checkbox(1, "Creatures", "trackCreatures")
Checkbox(2, "Chests", "trackChests")
EndRow()
Checkbox(1, "Merge Skinning", "skinningMerge", "Off: skinning loot is an entry of its own. On: it goes into the creature's loot.", Off("trackCreatures"))
Checkbox(2, "Merge Pickpocketing", "pickpocketMerge", "Off: pickpocketing loot is an entry of its own. On: it goes into the creature's loot.", Off("trackCreatures"))
EndRow()
Checkbox(1, "Lockboxes", "trackLockboxes", "Lockboxes and other containers you open from your bags.")
Checkbox(2, "Resource Nodes", "trackNodes", "Mining and herbalism. Copper Vein and Poor Copper Vein share one entry, as do Peacebloom and Wilted Peacebloom.")
EndRow()
Checkbox(1, "Disenchanting", "trackDisenchant", "What disenchanting gives you, all in one entry: Disenchanted.")
Checkbox(2, "Only What You Receive", "confirmLoot", "An item counts only once the game says you received it (\"You receive loot: ...\"). In a group, what someone else takes or wins the roll for, and what you leave behind, is not counted; a roll you win counts for its source when it comes. Gold counts as your purse grows: your share in a group. Off: everything the loot window shows counts when it opens.")
EndRow()
Checkbox(1, "Fishing", "trackFishing")
Dropdown(2, "Fishing Grouping", "fishingGrouping", Items({
	{ value = "zone", label = "By Zone" },
	{ value = "separated", label = "Separated (schools by type)" },
}), "By Zone: all of a zone's fishing in one entry. Separated: open water by zone, and what came from schools by the school's type.", Off("trackFishing"))
EndRow()
Button(1, "Export", function()
	ns.Export()
end, "The entries as shown, as plain text in a box to copy.")
Button(2, "Export Name Database", function()
	ns.ExportNames()
end, "Every creature looted in an instance, and every chest, node and other world object, with the names learned on any of your characters, as lines to send to the developer.")
EndRow()
Button(1, "Reset All Loot...", function()
	StaticPopup_Show("LOOTTRACKER_RESET")
end, "Forget everything tracked on this character (it asks first).")
EndRow()

Header("View")
Dropdown(1, "Item Value", "itemValue", Items({
	{ value = "vendor", label = "Vendor Value" },
	{ value = "auction", label = "Auction Value" },
	{ value = "none", label = "None" },
}), "Beside each source's name: its gold, plus what its items are worth to a vendor, or at your realm's lowest auction buyout at the last scan (items not listed count at vendor value). None: the gold alone.")
Dropdown(2, "View", "view", Items({ { value = "list", label = "List" }, { value = "icons", label = "Icons" } }), "List: item names in their quality's color, the count on the right. Icons: a grid of item icons.")
EndRow()
Checkbox(1, "Scan when the auction house opens", "auctionAutoScan", "A full scan each time you open the auction house (when the game allows one, every 15 minutes). It can stall the game a moment. Prices are kept per realm for all your characters.")
Button(2, "Scan Now", function()
	ns.Scan()
end, "Scan the auction house now (it must be open). The chat says how it went.")
EndRow()
Checkbox(1, "Update prices while browsing", "auctionBrowse", "Every item the auction house's Buy page shows, and the listings you open, update its price, with no full scan.")
Checkbox(2, "Scan button on the Buy page", "auctionButton", "A Scan AH button by the auction house's Search button, counting down the game's 15 minutes between scans.")
EndRow()
Checkbox(1, "Stack value on item lines", "lineValue", "List view: the stack's auction value beside each item's count. Gold: an auction price; gray: a vendor price standing in (Vendor Fallback).", NotList)
Checkbox(2, "Price each on item lines", "lineValueEach", "List view: one item's auction price beside its count, in brackets after the stack value when both are on.", NotList)
EndRow()
Checkbox(1, "Stack value on item icons", "iconValue", "Icons view: the stack's auction value in each icon's top corner.", function()
	return Get("view") ~= "icons"
end)
Checkbox(2, "Short values (12g, 34s)", "valueShort", "Lines and icons: the largest coin only, instead of gold, silver and copper.")
EndRow()
Checkbox(1, "Vendor Fallback", "valueFallback", "Items with no auction price (not listed at the last scan, or soulbound) show their vendor price, in gray. Off: they show nothing.")
Checkbox(2, "Auction price in item tooltips", "tooltipAuction", "An item's tooltip: its auction price right under the game's Sell Price line, in the same style, or that it was not listed.")
EndRow()
Checkbox(1, "Stack's auction price in item tooltips", "tooltipAuctionStack", "An item's tooltip: a second line with the auction price of the whole stack looted (Auction Price (x4)), for stacks of more than one.", function()
	return not Get("tooltipAuction")
end)
Checkbox(2, "Price's age in item tooltips", "tooltipScanAge", "An item's tooltip: how long ago its auction price was seen (browsing or a full scan).")
EndRow()
Checkbox(1, "In every item tooltip", "tooltipEverywhere", "The auction price and last scan's age in every item's tooltip (bags, links, the bank, vendors ...), not only the tracker's. Outside the tracker, the price is for one item.")
EndRow()
Dropdown(1, "Item Sort", "itemSort", Items({
	{ value = "quality", label = "Quality" },
	{ value = "newest", label = "Newest" },
	{ value = "value", label = "Value" },
}), "The order of each source's items: best quality first, most recently looted first, or most valuable stack first.")
Dropdown(2, "Source Sort", "entrySort", Items({ { value = "newest", label = "Newest" }, { value = "value", label = "Value" } }), "The order of the sources: most recently looted first, or most valuable first.")
EndRow()
Checkbox(1, "Item icons in the list", "listIcons", nil, NotList)
Slider(2, "Icon Size", "iconSize", 16, 48, 1, nil, function()
	return Get("view") ~= "icons"
end)
EndRow()
Checkbox(1, "Scroll Bar", "scrollBar", "A scroll bar beside the list while it is longer than the frame. The mouse wheel scrolls either way.")
Slider(2, "Scroll Bar Width", "scrollBarWidth", 2, 16, 1, nil, Off("scrollBar"))
EndRow()
Checkbox(1, "Portraits (experimental)", "portraits", "A round portrait of the source before its name: the creature's model, or an icon for chests, nodes, lockboxes and fishing.")
EndRow()

Header("Background Bars")
local function NoLineBars()
	return NotList() or not Get("lineBars")
end
Checkbox(1, "Source Row Bars", "headerBars", "A bar behind each source's row (both views).")
Checkbox(2, "Item Line Bars", "lineBars", "A bar behind each item line (List view).", NotList)
EndRow()
Dropdown(1, "Source Row Texture", "headerBarTexture", MediaItems(API.MEDIA.STATUSBAR, "Default (Blizzard)"), nil, Off("headerBars"))
Dropdown(2, "Item Line Texture", "lineBarTexture", MediaItems(API.MEDIA.STATUSBAR, "Default (Blizzard)"), nil, NoLineBars)
EndRow()
Color(1, "Source Row Color", "headerBarColor", Off("headerBars"))
Slider(2, "Source Row Opacity", "headerBarAlpha", 0.05, 1, 0.05, Percent, Off("headerBars"))
EndRow()
Dropdown(1, "Line Bar Color", "lineBarColorMode", Items({ { value = "quality", label = "Item Quality" }, { value = "custom", label = "Custom Color" } }), nil, NoLineBars)
Color(2, "Custom Line Color", "lineBarColor", function()
	return NoLineBars() or Get("lineBarColorMode") ~= "custom"
end)
EndRow()
Dropdown(1, "Line Bar Length", "lineBarLength", Items({ { value = "full", label = "Full Width" }, { value = "count", label = "By Count" } }), "Full Width: every bar fills its line. By Count: as long as the item's count against the source's most-looted item.", NoLineBars)
Slider(2, "Line Bar Opacity", "lineBarAlpha", 0.05, 1, 0.05, Percent, NoLineBars)
EndRow()

Header("Text")
Dropdown(1, "Font", "font", MediaItems(API.MEDIA.FONT, "Default (Friz Quadrata)"))
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
end, nil, "The item lines' size; names, money and the title follow in step. All the way left: the tracker's own sizes.")
EndRow()

Header("Frame")
Checkbox(1, "Unlock (drag it)", nil, "While unlocked the tracker shows (even folded away) and can be dragged. Also /loot unlock and /loot lock.", nil, function()
	return not API.Get("loot", "locked")
end, function(on)
	API.SetUnlocked(on)
end)
Dropdown(2, "Arrow Side", "arrowSide", Items({
	{ value = "LEFT", label = "Left" },
	{ value = "RIGHT", label = "Right" },
	{ value = "TOP", label = "Top" },
	{ value = "BOTTOM", label = "Bottom" },
}), "The side of the frame the arrow that hides it sits on.")
EndRow()
Slider(1, "Width", "width", 140, 600, 1)
Slider(2, "Height", "height", 80, 900, 1)
EndRow()
Checkbox(1, "Border", "border")
EndRow()
Dropdown(1, "Background", "background", MediaItems(API.MEDIA.BACKGROUND, "Default (Solid)"))
Slider(2, "Background Opacity", "backgroundAlpha", 0, 1, 0.05, Percent)
EndRow()
Button(1, "Reset Position", function()
	API.ResetPositions()
end)
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

SLASH_LOOTTRACKER1 = "/loot"
SLASH_LOOTTRACKER2 = "/loottracker"
SlashCmdList.LOOTTRACKER = function(msg)
	local command = strlower(strtrim(msg or ""))
	if command == "unlock" or command == "lock" then
		API.SetUnlocked(command == "unlock")
		API.Print(command == "lock" and "locked." or "unlocked: drag the tracker, then /loot lock.")
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
