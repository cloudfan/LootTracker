local addonName, ns = ...
local API = ns.API

-- The window's other looks (Style): the Loot History window (Window.lua) is
-- "blizzard"; StyleQuest.lua, StyleRuneLite.lua and StyleFlare.lua register
-- the others here. What they share: their frame's place and size (the same
-- positions.lootTracker, width and height as the Loot History window),
-- dragging and resizing while unlocked, a scroll frame with a scroll bar,
-- text in the chosen font, and the scripts of source and item rows. Only the
-- chosen style's frame is built and shown.

local S = "lootTracker"
local Setting = ns.Setting

local styles, order = {}, {}

ns.STYLES = {
	{ value = "blizzard", label = "Loot History" },
	{ value = "quest", label = "Quest Tracker" },
	{ value = "runelite", label = "RuneLite" },
	{ value = "flare", label = "FlareUI" },
}

function ns.RegisterStyle(key, style)
	style.key = key
	styles[key] = style
	order[#order + 1] = key
end

-- The chosen style; an unknown one is the Loot History window.
function ns.CurrentStyle()
	local style = Setting("style")
	return styles[style] and style or "blizzard"
end

local function Locked()
	return Setting("locked") and true or false
end
ns.Locked = Locked

-- Folded away to the title alone (the minimize buttons): per character.
local minimizedHere = false
function ns.Minimized()
	if ns.db then
		return ns.db.minimized and true or false
	end
	return minimizedHere
end

function ns.ToggleMinimized()
	if ns.db then
		ns.db.minimized = not ns.db.minimized or nil
	else
		minimizedHere = not minimizedHere
	end
	ns.ApplyStyles()
end

-- Text in the chosen font, size and shadow, as in Window.lua; a style gives
-- its own font and shadow for "global" (the Default choice).
function ns.StyleFont(fontString, size, font, shadow)
	local chosen, chosenShadow, lineSize = Setting("font"), Setting("fontShadow"), tonumber(Setting("fontSize")) or 0
	API.ApplyFont(fontString, {
		font = chosen ~= "global" and chosen or font,
		size = lineSize > 0 and math.max(6, size + lineSize - 12) or size,
		shadow = chosenShadow ~= "global" and chosenShadow or shadow,
		color = false,
	})
end

-- A plain colored texture.
function ns.Fill(parent, layer, r, g, b, a, sublevel)
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
	texture:SetColorTexture(r, g, b, a or 1)
	return texture
end

-- A one-pixel frame line around a region (inset by `inset`).
function ns.Outline(parent, r, g, b, a, inset, layer, size)
	inset, size = inset or 0, size or 1
	local lines = {}
	local top = ns.Fill(parent, layer or "BORDER", r, g, b, a)
	top:SetPoint("TOPLEFT", inset, -inset)
	top:SetPoint("TOPRIGHT", -inset, -inset)
	top:SetHeight(size)
	local bottom = ns.Fill(parent, layer or "BORDER", r, g, b, a)
	bottom:SetPoint("BOTTOMLEFT", inset, inset)
	bottom:SetPoint("BOTTOMRIGHT", -inset, inset)
	bottom:SetHeight(size)
	local left = ns.Fill(parent, layer or "BORDER", r, g, b, a)
	left:SetPoint("TOPLEFT", inset, -inset)
	left:SetPoint("BOTTOMLEFT", inset, inset)
	left:SetWidth(size)
	local right = ns.Fill(parent, layer or "BORDER", r, g, b, a)
	right:SetPoint("TOPRIGHT", -inset, -inset)
	right:SetPoint("BOTTOMRIGHT", -inset, inset)
	right:SetWidth(size)
	lines[1], lines[2], lines[3], lines[4] = top, bottom, left, right
	function lines:SetColor(nr, ng, nb, na)
		for _, line in ipairs(self) do
			line:SetColorTexture(nr, ng, nb, na or 1)
		end
	end
	return lines
end

-- An atlas, if this client has it.
function ns.TrySetAtlas(texture, ...)
	for i = 1, select("#", ...) do
		local atlas = select(i, ...)
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
			if pcall(texture.SetAtlas, texture, atlas) then -- RETEST
				return atlas
			end
		end
	end
end

-- A horizontal fade from one color to another (the newer and older calls).
function ns.Gradient(texture, r1, g1, b1, a1, r2, g2, b2, a2)
	texture:SetColorTexture(1, 1, 1, 1)
	if CreateColor and pcall(texture.SetGradient, texture, "HORIZONTAL", CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2)) then -- RETEST
		return
	end
	if texture.SetGradientAlpha then
		texture:SetGradientAlpha("HORIZONTAL", r1, g1, b1, a1, r2, g2, b2, a2)
	else
		texture:SetColorTexture(r1, g1, b1, a1)
	end
end

-- Rows -----------------------------------------------------------------------------------

-- A pool of rows made on demand: pool:Get(i) and pool:HideFrom(n + 1).
function ns.Pool(make)
	local pool = {}
	function pool:Get(i)
		local row = self[i]
		if not row then
			row = make(i)
			self[i] = row
		end
		return row
	end
	function pool:HideFrom(first)
		for i = first, #self do
			self[i]:Hide()
		end
	end
	return pool
end

function ns.ToggleFold(entry)
	local db = ns.db
	if db and entry then
		db.folded = db.folded or {}
		db.folded[entry.key] = not db.folded[entry.key] or nil
		ns.RenderStyle()
	end
end

-- A source's right-click menu: fold it, forget it. Without menus on this
-- client, Shift+right-click forgets it.
function ns.SourceMenu(owner, entry)
	if not entry then
		return
	end
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		if IsShiftKeyDown() then
			ns.DeleteEntry(entry)
		end
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root) -- RETEST
		root:CreateTitle(entry.name or "?")
		root:CreateButton(ns.Folded(entry.key) and "Show Its Loot" or "Fold Its Loot", function()
			ns.ToggleFold(entry)
		end)
		root:CreateButton("Forget This", function()
			ns.DeleteEntry(entry)
		end)
	end)
end

function ns.SourceTooltip(owner, entry)
	if not entry then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(entry.name or "?")
	if entry.id and type(entry.id) == "number" then
		GameTooltip:AddLine("ID " .. entry.id, 0.7, 0.7, 0.7)
	end
	if (entry.money or 0) > 0 then
		GameTooltip:AddLine("Money: " .. ns.Money(entry.money), 1, 1, 1)
	end
	local value = ns.Value(entry)
	if value > 0 then
		GameTooltip:AddLine("Value: " .. ns.Money(value), 1, 1, 1)
		if (entry.count or 0) > 1 then
			GameTooltip:AddLine("Each: " .. ns.Money(value / entry.count), 1, 1, 1)
		end
	end
	GameTooltip:AddLine("Click to fold or unfold its loot.", 0.6, 0.6, 0.6)
	GameTooltip:AddLine((MenuUtil and MenuUtil.CreateContextMenu) and "Right-click to forget it." or "Shift+right-click to forget it.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

-- Source rows: a click folds, a right-click opens its menu, hovering shows
-- its tooltip; onHover(row, inside) for a style's own highlight.
function ns.SourceScripts(row, onHover)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			ns.SourceMenu(self, self.entry)
		else
			ns.ToggleFold(self.entry)
		end
	end)
	row:SetScript("OnEnter", function(self)
		ns.SourceTooltip(self, self.entry)
		if onHover then
			onHover(self, true)
		end
	end)
	row:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		if onHover then
			onHover(self, false)
		end
	end)
end

-- Item rows and icons: their tooltip (with the auction lines), a
-- shift-click links them in chat; .link and .itemCount are set by Render.
function ns.ItemScripts(button, onHover)
	button:SetScript("OnEnter", function(self)
		if self.money then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(MONEY or "Money")
			GameTooltip:AddLine(ns.Money(self.money), 1, 1, 1)
			GameTooltip:Show()
		else
			ns.ShowItemTooltip(self)
		end
		if onHover then
			onHover(self, true)
		end
	end)
	button:SetScript("OnLeave", function(self)
		self.lootTrackerItem = nil
		GameTooltip:Hide()
		if onHover then
			onHover(self, false)
		end
	end)
	button:SetScript("OnClick", function(self)
		if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
			ChatEdit_InsertLink(self.link)
		end
	end)
end

function ns.ItemName(item)
	return item.name or (item.link and item.link:match("%[(.-)%]")) or "?"
end

-- The window ---------------------------------------------------------------------------

local function SavePlace(frame)
	if frame:GetLeft() then
		API.Set("positions", "lootTracker", { "TOPLEFT", "BOTTOMLEFT", math.floor(frame:GetLeft() + 0.5), math.floor(frame:GetTop() + 0.5) })
	end
end

local function Place(frame)
	local saved = API.Get("positions", "lootTracker")
	frame:ClearAllPoints()
	if type(saved) == "table" then
		frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
	else
		frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0)
	end
end

-- A style's frame: hidden, movable, resizable, with frame.scroll (its
-- scroll frame), frame.content (the scroll child) and frame.bar (its scroll
-- bar, barWidth wide). The style places scroll and bar.
function ns.NewStyleFrame(key, barWidth)
	local frame = CreateFrame("Frame", "LootTracker_" .. key, UIParent)
	frame:Hide()
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(200, 120, 700, 1000) -- RETEST
	elseif frame.SetMinResize then
		frame:SetMinResize(200, 120)
		frame:SetMaxResize(700, 1000)
	end
	local scroll = CreateFrame("ScrollFrame", nil, frame)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(10, 10)
	scroll:SetScrollChild(content)
	local bar = API.NewScrollBar(frame, scroll, barWidth or 6, 40)
	frame.scroll, frame.content, frame.bar = scroll, content, bar
	scroll:SetScript("OnSizeChanged", function()
		ns.RenderStyle()
	end)
	return frame
end

-- The scroll bar's colors: its track and its thumb.
function ns.PaintScrollBar(bar, tr, tg, tb, ta, r, g, b, a)
	bar:SetBackdropColor(tr, tg, tb, ta)
	for _, region in ipairs({ bar.thumb:GetRegions() }) do
		if region.SetColorTexture then
			region:SetColorTexture(r, g, b, a)
		end
	end
end

-- A region that drags the frame while unlocked; a right-click on it opens
-- the window's menu.
function ns.DragHandle(frame, region)
	region:EnableMouse(true)
	region:RegisterForDrag("LeftButton")
	region:SetScript("OnDragStart", function()
		if not Locked() and not InCombatLockdown() then
			frame:StartMoving()
		end
	end)
	region:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SavePlace(frame)
	end)
	region:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and ns.ShowMenu then
			ns.ShowMenu(self)
		end
	end)
end

-- A resize grip in the bottom right corner, shown while unlocked. Without
-- art of its own: the chat window's.
function ns.ResizeGrip(frame, size)
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(size or 16, size or 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(frame:GetFrameLevel() + 20)
	grip:SetScript("OnMouseDown", function()
		if not Locked() then
			frame:StartSizing("BOTTOMRIGHT")
		end
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		local width, height = frame:GetSize()
		SavePlace(frame)
		API.Set(S, "width", math.floor(width + 0.5))
		API.Set(S, "height", math.floor(height + 0.5))
	end)
	frame.grip = grip
	return grip
end

function ns.ChatGripArt(grip)
	grip:SetNormalTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
	grip:SetHighlightTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
	grip:SetPushedTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]])
end

-- Drawing ----------------------------------------------------------------------------------

local function Render()
	local style = styles[ns.CurrentStyle()]
	local frame = style and style.frame
	if not (frame and frame:IsShown()) then
		return
	end
	if style.minimizable and ns.Minimized() then
		frame.scroll:Hide()
		frame.bar:Hide()
		if style.RenderHeader then
			style.RenderHeader(frame)
		end
		return
	end
	frame.scroll:Show()
	if style.RenderHeader then
		style.RenderHeader(frame)
	end
	local width = frame.scroll:GetWidth()
	if not width or width <= 1 then
		return
	end
	frame.content:SetWidth(width)
	local height = style.Render(frame, ns.Entries(), width) or 0
	frame.content:SetHeight(math.max(1, height))
	frame.bar:Update(height)
end
ns.RenderStyle = Render

function ns.ApplyStyles()
	local current = ns.CurrentStyle()
	for _, key in ipairs(order) do
		local style = styles[key]
		local show = key == current and not ns.standingDown and not Setting("collapsed")
		if show and not style.frame then
			style.frame = style.Build()
		end
		local frame = style.frame
		if frame then
			if show then
				frame:SetSize(tonumber(Setting("width")) or 300, tonumber(Setting("height")) or 420)
				Place(frame)
				if style.Refresh then
					style.Refresh(frame)
				end
				frame:Show()
				Render()
			else
				frame:Hide()
			end
		end
	end
end

API.OnReady(ns.ApplyStyles)

local soon = false
local function RenderSoon()
	if not soon then
		soon = true
		C_Timer.After(0.1, function()
			soon = false
			Render()
		end)
	end
end

API.Listen("SettingChanged", function(section)
	if section == S or section == "positions" or section == nil then
		ns.ApplyStyles()
	end
end)
API.Listen("LootTrackerChanged", RenderSoon)
API.Listen("LootTrackerScan", RenderSoon)
API.Listen("StandDown", function()
	for _, key in ipairs(order) do
		if styles[key].frame then
			styles[key].frame:Hide()
		end
	end
end)
