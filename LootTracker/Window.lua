local addonName, ns = ...
local API = ns.API

-- The Loot Tracker's window (the owner's design): Blizzard's group loot
-- history window as the model: the same flat panel (DefaultPanelFlatTemplate),
-- a scrolling list, a close button, a resize grip. In its title bar, beside
-- the close button: a lock button like Move UI's (locked: the window cannot
-- be dragged or resized) and an arrow that opens a menu of the settings
-- used most (scope, grouping, values, sorting, export, reset).
--
-- Dragged by its title bar while unlocked; its place is kept in the
-- positions section (lootTracker). The list: a
-- row for each source (its portrait or icon, name, count, value; a click
-- folds its loot, the X deletes it) and a row for each item under it.

local S = "lootTracker"
local Setting = ns.Setting

local ROW, HEAD = 18, 26
local frame, scroll, content
local heads, lines = {}, {}

local function Render() end -- below

-- Rows ------------------------------------------------------------------------------

local function Head(i)
	local row = heads[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, content)
	row:SetHeight(HEAD)
	row.bar = row:CreateTexture(nil, "BACKGROUND")
	row.bar:SetAllPoints()
	row.bar:SetColorTexture(1, 0.82, 0, 0.12)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(HEAD - 4, HEAD - 4)
	row.icon:SetPoint("LEFT", 2, 0)
	row.model = CreateFrame("PlayerModel", nil, row)
	row.model:SetAllPoints(row.icon)
	row.model:Hide()
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.value:SetPoint("RIGHT", -22, 0)
	row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	row.delete = CreateFrame("Button", nil, row, "UIPanelCloseButton")
	row.delete:SetSize(18, 18)
	row.delete:SetPoint("RIGHT", 0, 0)
	row.delete:SetScript("OnClick", function()
		if row.entry then
			ns.DeleteEntry(row.entry)
		end
	end)
	row.delete:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Forget this")
		GameTooltip:AddLine(Setting("grouping") == "individual" and "Takes this one loot out of the tracker." or "Takes everything tracked from this source out of the tracker.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row.delete:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	-- A click on the source folds its loot away.
	row:SetScript("OnClick", function()
		local db = ns.db
		if db and row.entry then
			db.folded = db.folded or {}
			db.folded[row.entry.key] = not db.folded[row.entry.key] or nil
			Render()
		end
	end)
	row:SetScript("OnEnter", function(self)
		local entry = self.entry
		if not entry then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(entry.name or "?")
		if entry.id and type(entry.id) == "number" then
			GameTooltip:AddLine("ID " .. entry.id, 0.7, 0.7, 0.7)
		end
		if (entry.money or 0) > 0 then
			GameTooltip:AddLine("Money: " .. ns.Money(entry.money), 1, 1, 1)
		end
		GameTooltip:AddLine("Click to fold or unfold its loot.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	heads[i] = row
	return row
end

local function Line(i)
	local row = lines[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, content)
	row:SetHeight(ROW)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW - 2, ROW - 2)
	row.icon:SetPoint("LEFT", 14, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.value:SetPoint("RIGHT", -4, 0)
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
	row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row:SetScript("OnEnter", ns.ShowItemTooltip)
	row:SetScript("OnLeave", function(self)
		self.lootTrackerItem = nil
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
			ChatEdit_InsertLink(self.link)
		end
	end)
	lines[i] = row
	return row
end

-- A creature's portrait: its model, held on its first frame. Models are
-- not cut off by the list's edge, so one shows only while its row is
-- wholly inside it.
local function Portrait(row, entry)
	local creature = Setting("portraits") and type(entry.id) == "number"
		and (entry.kind == "creature" or entry.kind == "skinning" or entry.kind == "pickpocket")
	row.wantsModel = false
	if creature then
		local ok = pcall(function()
			if row.model.creature ~= entry.id then
				row.model.creature = entry.id
				row.model:ClearModel()
				row.model:SetCreature(entry.id) -- RETEST
				row.model:SetPortraitZoom(1)
				ns.Freeze(row.model)
			end
		end)
		row.wantsModel = ok
	end
	row.icon:SetTexture(ns.PORTRAIT_ICONS[entry.kind] or ns.PORTRAIT_ICONS.creature)
end

local function ClipModels()
	if not scroll then
		return
	end
	local top, bottom = scroll:GetTop(), scroll:GetBottom()
	for _, row in ipairs(heads) do
		local inside = row:IsShown() and row.wantsModel and top and row:GetTop() and row:GetTop() <= top + 1 and row:GetBottom() >= bottom - 1
		row.model:SetShown(inside and true or false)
		row.icon:SetShown(not inside)
	end
end

-- Totals --------------------------------------------------------------------------------

local totals = { money = 0, value = 0, items = 0, dirty = true }

function ns.Totals()
	if totals.dirty then
		totals.dirty = false
		totals.money, totals.value, totals.items = 0, 0, 0
		for _, entry in ipairs(ns.Entries()) do
			totals.money = totals.money + (entry.money or 0)
			totals.value = totals.value + ns.Value(entry)
			for _, item in ipairs(entry.items) do
				totals.items = totals.items + (item.count or 0)
			end
		end
	end
	return totals
end

-- Drawing ------------------------------------------------------------------------------

Render = function()
	totals.dirty = true
	if not (frame and frame:IsShown()) then
		return
	end
	local width = scroll:GetWidth()
	content:SetWidth(width)
	local y, headCount, lineCount = 0, 0, 0
	local grouped = Setting("grouping") ~= "individual"
	for _, entry in ipairs(ns.Entries()) do
		headCount = headCount + 1
		local row = Head(headCount)
		row.entry = entry
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
		row.name:SetText((entry.name or "?") .. ((grouped and (entry.count or 0) > 1) and ("  x" .. entry.count) or ""))
		row.value:SetText(ns.ShortMoney(ns.Value(entry)))
		Portrait(row, entry)
		row:Show()
		y = y + HEAD + 2
		if not ns.Folded(entry.key) then
			for _, item in ipairs(entry.items) do
				lineCount = lineCount + 1
				local line = Line(lineCount)
				line.link = item.link
				line:ClearAllPoints()
				line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				line:SetPoint("RIGHT", content, "RIGHT", 0, 0)
				line.icon:SetTexture(item.icon or [[Interface\Icons\INV_Misc_QuestionMark]])
				local r, g, b = ns.QualityColor(item.quality)
				line.name:SetText((item.name or (item.link and item.link:match("%[(.-)%]")) or "?") .. ((item.count or 0) > 1 and ("  x" .. item.count) or ""))
				line.name:SetTextColor(r or 1, g or 1, b or 1)
				local value = ns.ItemValue(item)
				line.value:SetText(Setting("itemValue") ~= "none" and value > 0 and ns.ShortMoney(value) or "")
				line:Show()
				y = y + ROW
			end
			y = y + 4
		end
	end
	for i = headCount + 1, #heads do
		heads[i]:Hide()
	end
	for i = lineCount + 1, #lines do
		lines[i]:Hide()
	end
	content:SetHeight(math.max(1, y))
	local sum = ns.Totals()
	frame.total:SetText(headCount == 0 and "Nothing tracked yet." or ("Total: " .. ns.Money(sum.value)))
	local scope = Setting("scope")
	local title = "Loot Tracker" .. (scope == "session" and ": Session" or scope == "instance" and ": Instance" or "")
	if frame.SetTitle then
		frame:SetTitle(title)
	elseif frame.TitleText then
		frame.TitleText:SetText(title)
	end
	ClipModels()
end

-- The window ---------------------------------------------------------------------------

local function Locked()
	return Setting("locked") and true or false
end

local function PaintLock()
	local locked = Locked()
	frame.lock:SetNormalTexture(locked and [[Interface\Buttons\LockButton-Locked-Up]] or [[Interface\Buttons\LockButton-Unlocked-Up]])
	frame.lock:SetPushedTexture(locked and [[Interface\Buttons\LockButton-Unlocked-Down]] or [[Interface\Buttons\LockButton-Locked-Down]])
	-- The art is small in the middle of its texture: only that middle is shown.
	for _, texture in ipairs({ frame.lock:GetNormalTexture(), frame.lock:GetPushedTexture() }) do
		texture:SetTexCoord(0.2, 0.8, 0.2, 0.8) -- RETEST
	end
	frame.grip:SetShown(not locked)
end

local function Radio(root, label, key, value)
	root:CreateRadio(label, function() -- RETEST
		return Setting(key) == value
	end, function()
		API.Set(S, key, value)
	end)
end

local function Menu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		ns.OpenSettings()
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root) -- RETEST
		root:CreateTitle("Loot Tracker")
		root:CreateCheckbox("This Session Only", function()
			return Setting("scope") == "session"
		end, function()
			ns.SetScope("session")
		end)
		root:CreateCheckbox("This Instance Only", function()
			return Setting("scope") == "instance"
		end, function()
			ns.SetScope("instance")
		end)
		root:CreateDivider()
		local grouping = root:CreateButton("Grouping")
		Radio(grouping, "By Source", "grouping", "grouped")
		Radio(grouping, "Each Loot", "grouping", "individual")
		local value = root:CreateButton("Item Value")
		Radio(value, "Auction", "itemValue", "auction")
		Radio(value, "Vendor", "itemValue", "vendor")
		Radio(value, "None", "itemValue", "none")
		local sort = root:CreateButton("Sort Sources")
		Radio(sort, "Newest First", "entrySort", "newest")
		Radio(sort, "By Value", "entrySort", "value")
		local items = root:CreateButton("Sort Items")
		Radio(items, "By Quality", "itemSort", "quality")
		Radio(items, "Newest First", "itemSort", "newest")
		Radio(items, "By Value", "itemSort", "value")
		root:CreateCheckbox("Creature Portraits", function()
			return Setting("portraits") and true or false
		end, function()
			API.Set(S, "portraits", not Setting("portraits"))
		end)
		root:CreateDivider()
		root:CreateButton("Scan the Auction House", function()
			ns.Scan()
		end)
		root:CreateButton("Export...", function()
			ns.Export()
		end)
		root:CreateButton("Export Name Database...", function()
			ns.ExportNames()
		end)
		root:CreateButton("All Settings...", function()
			ns.OpenSettings()
		end)
		root:CreateButton("|cffff5040Reset All...|r", function()
			StaticPopup_Show("LOOTTRACKER_RESET")
		end)
	end)
end

-- Its place: the top left corner from the screen's bottom left.
local function SavePlace()
	API.Set("positions", "lootTracker", { "TOPLEFT", "BOTTOMLEFT", math.floor(frame:GetLeft() + 0.5), math.floor(frame:GetTop() + 0.5) })
end

local function Place()
	local saved = API.Get("positions", "lootTracker")
	frame:ClearAllPoints()
	if type(saved) == "table" then
		frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
	else
		frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0)
	end
end

local function Build()
	for _, template in ipairs({ "DefaultPanelFlatTemplate", "BasicFrameTemplateWithInset", "BackdropTemplate" }) do -- RETEST
		local ok, made = pcall(CreateFrame, "Frame", "LootTracker", UIParent, template)
		if ok and made then
			frame = made
			break
		end
	end
	frame = frame or CreateFrame("Frame", "LootTracker", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetSize(tonumber(Setting("width")) or 300, tonumber(Setting("height")) or 420)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(220, 160, 700, 1000) -- RETEST
	end

	-- The title bar's buttons, right to left: close, lock, settings arrow.
	local close = frame.CloseButton or frame.ClosePanelButton
	if not close then
		for _, template in ipairs({ "UIPanelCloseButtonDefaultAnchors", "UIPanelCloseButton" }) do
			local ok, made = pcall(CreateFrame, "Button", nil, frame, template)
			if ok and made then
				close = made
				break
			end
		end
		if close and close:GetNumPoints() == 0 then
			close:SetPoint("TOPRIGHT", 0, 0)
		end
	end
	if close then
		close:SetScript("OnClick", function()
			API.Set(S, "collapsed", true)
		end)
	end
	-- The panel's own title bar art is drawn on frames above the panel:
	-- our buttons go above those, or they sit behind the title bar.
	-- (Blizzard's panel templates give those frames fixed, high levels: 500
	-- and up. So: above the highest child the panel has.)
	local above = frame:GetFrameLevel()
	for _, child in ipairs({ frame:GetChildren() }) do
		above = math.max(above, child:GetFrameLevel())
	end
	above = above + 10
	if close then
		close:SetFrameLevel(above)
	end
	local size = close and math.max(18, close:GetWidth()) or 22
	local lock = CreateFrame("Button", nil, frame)
	lock:SetSize(size, size)
	if close then
		lock:SetPoint("RIGHT", close, "LEFT", 0, 0)
	else
		lock:SetPoint("TOPRIGHT", -4, -2)
	end
	lock:SetFrameLevel(above)
	lock:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
	lock:SetScript("OnClick", function()
		API.Set(S, "locked", not Locked())
	end)
	lock:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(Locked() and "Locked" or "Unlocked")
		GameTooltip:AddLine(Locked() and "Click to let the window be dragged by its title and resized." or "Click to keep the window where it is.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	lock:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	frame.lock = lock
	local arrow = CreateFrame("Button", "LootTrackerMenu", frame)
	arrow:SetSize(size, size)
	arrow:SetPoint("RIGHT", lock, "LEFT", -2, 0)
	arrow:SetFrameLevel(above)
	-- The owner's choice of art: Blizzard's red arrow button, as atlases.
	local hasArt = pcall(function()
		arrow:SetNormalAtlas("128-RedButton-ArrowDown") -- RETEST
		arrow:SetPushedAtlas("128-RedButton-ArrowDown-Pressed")
	end) and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("128-RedButton-ArrowDown")
	if not hasArt then
		-- Not on this client: the yellow triangle, pointing down.
		arrow:SetNormalTexture([[Interface\ChatFrame\ChatFrameExpandArrow]])
		local art = arrow:GetNormalTexture()
		if art and art.SetRotation then
			art:SetRotation(-math.pi / 2)
		end
	end
	arrow:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
	arrow:SetScript("OnClick", Menu)
	arrow:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Loot Tracker Settings")
		GameTooltip:AddLine("This session or this instance only, grouping, values, sorting, export, reset.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	arrow:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Dragged by its title bar while unlocked: kept as the mover's place.
	local title = CreateFrame("Frame", nil, frame)
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetPoint("RIGHT", arrow, "LEFT", -2, 0)
	title:SetHeight(24)
	title:SetFrameLevel(above - 1)
	title:EnableMouse(true)
	title:RegisterForDrag("LeftButton")
	frame:SetMovable(true)
	title:SetScript("OnDragStart", function()
		if not Locked() and not InCombatLockdown() then
			frame:StartMoving()
		end
	end)
	title:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		if frame:GetLeft() then
			SavePlace()
		end
	end)

	scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -28)
	scroll:SetPoint("BOTTOMRIGHT", -28, 26)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(10, 10)
	scroll:SetScrollChild(content)
	scroll:HookScript("OnVerticalScroll", ClipModels)
	scroll:HookScript("OnSizeChanged", function()
		Render()
	end)

	frame.total = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.total:SetPoint("BOTTOMLEFT", 10, 9)

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
	grip:SetHighlightTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
	grip:SetPushedTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]])
	grip:SetScript("OnMouseDown", function()
		if not Locked() then
			frame:StartSizing("BOTTOMRIGHT")
		end
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		local width, height = frame:GetSize()
		API.Set(S, "width", math.floor(width + 0.5))
		API.Set(S, "height", math.floor(height + 0.5))
		if frame:GetLeft() then
			SavePlace()
		end
	end)
	frame.grip = grip
end

local function Apply()
	if not frame then
		Build()
	end
	if ns.standingDown then
		frame:Hide()
		return
	end
	frame:SetSize(tonumber(Setting("width")) or 300, tonumber(Setting("height")) or 420)
	Place()
	frame:SetShown(not Setting("collapsed"))
	PaintLock()
	Render()
end

function ns.ToggleWindow()
	API.Set(S, "collapsed", not Setting("collapsed"))
end

API.OnReady(Apply)

local soon = false
local function RenderSoon()
	totals.dirty = true
	if not soon then
		soon = true
		C_Timer.After(0.1, function()
			soon = false
			Render()
		end)
	end
end

API.Listen("SettingChanged", function(section)
	if section == S or section == "positions" then
		Apply()
	end
end)
API.Listen("LootTrackerChanged", RenderSoon)
API.Listen("LootTrackerScan", RenderSoon)
API.Listen("StandDown", function()
	if frame then
		frame:Hide()
	end
end)
