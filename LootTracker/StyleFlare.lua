local addonName, ns = ...
local API = ns.API

-- Style "flare": built as FlareUI's quest tracker window is
-- (malkkav/FlareUI, Modules/ObjectiveTracker.lua), with its art (MIT, see
-- Media/FlareUI-LICENSE.txt): the dark dialog background at 75% in FlareUI's
-- frame border (Media/FlareUI-Frames.tga, a 16 px edge, tinted its bronze
-- #A67D45); a 30 px header ("Loot" in light bronze, the number of sources,
-- the scope as a word you click through, a 14 px bronze minimize box, the
-- menu arrow) over the game's tooltip divider; each source with its icon in
-- FlareUI's bronze ring (Media/FlareUI-Ring.tga), its count in soft orange
-- brackets and its name in FlareUI's title bronze; its items in their quality's colors
-- with bronze-edged icons (or a grid of them, Icons view); the total in a
-- footer. A click on a source folds it; a right-click forgets it.

local Setting = ns.Setting
local MEDIA = [[Interface\AddOns\]] .. addonName .. [[\Media\]]

-- FlareUI's palette (Core.lua's ns.PALETTE) as its quest tracker uses it:
-- the frame border bronze3, buttons bronze2 (bronze3 while pointed at), the
-- scroll bar bronze1, the heading bronze5, quest titles bronze4; its
-- objective, dim and orange in its softer tones (ns.SoftColor).
local BACKGROUND = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]]
local OPACITY = 0.75
local EDGE = { 0.65, 0.49, 0.27 }       -- bronze3: every border
local OUTER = { 0.50, 0.38, 0.21 }      -- bronze2: buttons, icon edges, dividers
local INNER = { 0.65, 0.49, 0.27 }      -- bronze3: the same, pointed at
local SCROLL = { 0.32, 0.24, 0.13 }     -- bronze1: the scroll bar
local GOLD = { 0.85, 0.68, 0.47 }       -- bronze5: the heading, values
local SECTION = { 0.80, 0.60, 0.34 }    -- bronze4: titles
local ACCENT = { 0.85, 0.57, 0.40 }     -- orange, softened
local TEXT = { 0.85, 0.81, 0.76 }       -- the objective gray, softened
local DIM = { 0.63, 0.59, 0.54 }        -- the dim gray, softened

-- FlareUI's header: 30 px, its contents 8 px in, the divider 2 px above its foot.
local HEADER, HEADER_INSET = 30, 8
local TITLE_HEIGHT, FOOTER_HEIGHT, HEAD, ROW = HEADER - 3, 22, 26, 18

local heads, lines, icons

local function Color(fontString, color)
	fontString:SetTextColor(color[1], color[2], color[3])
end

local function Hex(color)
	return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

-- The game's tooltip divider (the line under FlareUI's tracker header), along
-- a frame's top or bottom edge.
local function Rule(parent, edge, y)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetTexture([[Interface\Common\UI-TooltipDivider-Transparent]])
	line:SetHeight(8)
	line:SetPoint("LEFT", parent, edge .. "LEFT", 0, y or 0)
	line:SetPoint("RIGHT", parent, edge .. "RIGHT", 0, y or 0)
end

-- An icon in FlareUI's bronze ring. The ring fills the middle of its
-- texture (pixels 62 to 193 of 256, a 16 px band): only that is drawn.
local RING_CROP = { 60 / 256, 196 / 256 }
local function Ring(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size, size)
	holder.icon = holder:CreateTexture(nil, "ARTWORK")
	holder.icon:SetPoint("TOPLEFT", size * 0.11, -size * 0.11)
	holder.icon:SetPoint("BOTTOMRIGHT", -size * 0.11, size * 0.11)
	holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	pcall(function()
		local mask = holder:CreateMaskTexture()
		mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") -- RETEST
		mask:SetAllPoints(holder.icon)
		holder.icon:AddMaskTexture(mask)
	end)
	holder.ring = holder:CreateTexture(nil, "OVERLAY")
	holder.ring:SetAllPoints()
	holder.ring:SetTexture(MEDIA .. "FlareUI-Ring")
	holder.ring:SetTexCoord(RING_CROP[1], RING_CROP[2], RING_CROP[1], RING_CROP[2])
	return holder
end

-- A source's picture: its kind's icon; a creature's best item (or coins).
local function SourceIcon(entry)
	if entry.kind == "creature" then
		local first = entry.items[1]
		return first and first.icon or [[Interface\Icons\INV_Misc_Coin_02]]
	end
	return ns.PORTRAIT_ICONS[entry.kind] or ns.PORTRAIT_ICONS.creature
end

local function NewHead()
	local row = CreateFrame("Button", nil, heads.content)
	row:SetHeight(HEAD)
	row.hover = ns.Fill(row, "BACKGROUND", OUTER[1], OUTER[2], OUTER[3], 0.25)
	row.hover:SetAllPoints()
	row.hover:Hide()
	row.portrait = Ring(row, HEAD - 2)
	row.portrait:SetPoint("LEFT", 2, 0)
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.name:SetPoint("LEFT", row.portrait, "RIGHT", 6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.value = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.value:SetPoint("RIGHT", -4, 0)
	row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	ns.SourceScripts(row, function(self, inside)
		self.hover:SetShown(inside)
	end)
	return row
end

-- An item's icon with a bronze edge.
local function EdgedIcon(parent)
	local edge = ns.Fill(parent, "BORDER", OUTER[1], OUTER[2], OUTER[3], 1)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return icon, edge
end

local function NewLine()
	local row = CreateFrame("Button", nil, lines.content)
	row:SetHeight(ROW)
	row.hover = ns.Fill(row, "BACKGROUND", OUTER[1], OUTER[2], OUTER[3], 0.18)
	row.hover:SetAllPoints()
	row.hover:Hide()
	row.icon, row.edge = EdgedIcon(row)
	row.edge:SetSize(ROW - 3, ROW - 3)
	row.edge:SetPoint("LEFT", 16, 0)
	row.value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.value:SetPoint("RIGHT", -4, 0)
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	ns.ItemScripts(row, function(self, inside)
		self.hover:SetShown(inside)
	end)
	return row
end

local function NewIcon()
	local button = CreateFrame("Button", nil, icons.content)
	button.icon, button.edge = EdgedIcon(button)
	button.edge:SetAllPoints()
	button.count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	button.value = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.value:SetPoint("TOPLEFT", 2, -2)
	button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
	button.highlight:SetAllPoints()
	button.highlight:SetColorTexture(INNER[1], INNER[2], INNER[3], 0.2)
	ns.ItemScripts(button, function(self, inside)
		self.edge:SetColorTexture(inside and INNER[1] or OUTER[1], inside and INNER[2] or OUTER[2], inside and INNER[3] or OUTER[3], 1)
	end)
	return button
end

-- Title bar buttons --------------------------------------------------------------------

local function Tip(button, title, text)
	button:SetScript("OnEnter", function(self)
		if self.Hover then
			self:Hover(true)
		end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(type(title) == "function" and title() or title)
		if text then
			GameTooltip:AddLine(text, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		if self.Hover then
			self:Hover(false)
		end
		GameTooltip:Hide()
	end)
end

local SCOPES = { all = "All", session = "Session", instance = "Instance" }
local NEXT_SCOPE = { all = "session", session = "instance", instance = "all" }

local function Build()
	local frame = ns.NewStyleFrame("flare", 3)
	ns.PaintScrollBar(frame.bar, 0, 0, 0, 0, SCROLL[1], SCROLL[2], SCROLL[3], 1)
	frame:EnableMouse(true)

	-- The panel: FlareUI's tracker backdrop (the dark dialog background at
	-- 75%, FlareUI's frame border in its bronze); without backdrops, a dark
	-- fill in a square bronze line.
	local panel = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
	panel:SetAllPoints()
	panel:SetFrameLevel(frame:GetFrameLevel())
	if panel.SetBackdrop then
		panel:SetBackdrop({
			bgFile = BACKGROUND,
			edgeFile = MEDIA .. "FlareUI-Frames",
			tile = false, tileSize = 0,
			edgeSize = 16,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		panel:SetBackdropColor(1, 1, 1, OPACITY)
		panel:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3], 1)
	else
		local back = ns.Fill(panel, "BACKGROUND", 0.05, 0.04, 0.03, OPACITY)
		back:SetAllPoints()
		ns.Outline(panel, EDGE[1], EDGE[2], EDGE[3], 1, 1, "BORDER")
	end

	-- The title bar.
	local title = CreateFrame("Frame", nil, frame)
	title:SetPoint("TOPLEFT", HEADER_INSET, -3)
	title:SetPoint("TOPRIGHT", -HEADER_INSET, -3)
	title:SetHeight(TITLE_HEIGHT)
	Rule(title, "BOTTOM", -2)
	title.text = title:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title.text:SetPoint("LEFT", 0, 0)
	title.count = title:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	title.count:SetPoint("LEFT", title.text, "RIGHT", 6, 0)
	ns.DragHandle(frame, title)
	frame.title = title

	-- The menu: the arrow, in gold.
	local arrow = CreateFrame("Button", nil, title)
	arrow:SetSize(16, 16)
	arrow:SetPoint("RIGHT", 2, 0)
	arrow:SetNormalTexture([[Interface\ChatFrame\ChatFrameExpandArrow]])
	local art = arrow:GetNormalTexture()
	if art then
		if art.SetRotation then
			pcall(art.SetRotation, art, -math.pi / 2)
		end
		art:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	end
	arrow:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
	arrow:SetScript("OnClick", function(self)
		if ns.ShowMenu then
			ns.ShowMenu(self)
		end
	end)
	Tip(arrow, "Loot Tracker Settings", "Scope, view, grouping, values, sorting, style, export, reset.")

	-- Minimize: FlareUI's 14 px box, a 2 px dash (a plus while minimized),
	-- all in bronze2, bronze3 while pointed at.
	local minimize = CreateFrame("Button", nil, title)
	minimize:SetSize(14, 14)
	minimize:SetPoint("RIGHT", arrow, "LEFT", -6, 0)
	minimize.box = ns.Outline(minimize, OUTER[1], OUTER[2], OUTER[3], 1, 0, "ARTWORK")
	minimize.dash = ns.Fill(minimize, "ARTWORK", OUTER[1], OUTER[2], OUTER[3], 1)
	minimize.dash:SetSize(8, 2)
	minimize.dash:SetPoint("CENTER")
	minimize.stem = ns.Fill(minimize, "ARTWORK", OUTER[1], OUTER[2], OUTER[3], 1)
	minimize.stem:SetSize(2, 8)
	minimize.stem:SetPoint("CENTER")
	minimize:SetScript("OnClick", ns.ToggleMinimized)
	function minimize:Hover(inside)
		local c = inside and INNER or OUTER
		self.box:SetColor(c[1], c[2], c[3], 1)
		self.dash:SetColorTexture(c[1], c[2], c[3], 1)
		self.stem:SetColorTexture(c[1], c[2], c[3], 1)
	end
	Tip(minimize, function()
		return ns.Minimized() and "Expand" or "Minimize"
	end)
	frame.minimize = minimize

	-- The scope, as a word: a click goes on to the next.
	local scope = CreateFrame("Button", nil, title)
	scope:SetHeight(16)
	scope:SetPoint("RIGHT", minimize, "LEFT", -8, 0)
	scope.text = scope:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	scope.text:SetPoint("RIGHT")
	scope:SetScript("OnClick", function()
		API.Set("lootTracker", "scope", NEXT_SCOPE[Setting("scope")] or "all")
	end)
	function scope:Hover(inside)
		Color(self.text, inside and TEXT or DIM)
	end
	Tip(scope, "Shows", "All time, this session or this instance: a click goes on to the next.")
	frame.scope = scope

	-- The footer: a rule, the total.
	local footer = CreateFrame("Frame", nil, frame)
	footer:SetPoint("BOTTOMLEFT", HEADER_INSET, 4)
	footer:SetPoint("BOTTOMRIGHT", -HEADER_INSET, 4)
	footer:SetHeight(FOOTER_HEIGHT)
	Rule(footer, "TOP")
	footer.label = footer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	footer.label:SetPoint("LEFT", 0, 0)
	footer.label:SetText("Total")
	footer.value = footer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	footer.value:SetPoint("RIGHT", -12, 0)
	frame.footer = footer

	-- The list 10 px under the header; the scroll bar 6 px in from the right.
	frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", HEADER_INSET, -(HEADER + 10))
	frame.scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -6, 4)
	frame.bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(HEADER + 10))
	frame.bar:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", HEADER_INSET - 6, 4)

	frame.empty = frame.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.empty:SetPoint("TOP", 0, -14)
	frame.empty:SetText("Nothing looted yet.")

	local grip = ns.ResizeGrip(frame, 14)
	grip:ClearAllPoints()
	grip:SetPoint("BOTTOMRIGHT", -5, 5)
	ns.ChatGripArt(grip)
	for _, texture in ipairs({ grip:GetNormalTexture(), grip:GetPushedTexture() }) do
		texture:SetVertexColor(INNER[1], INNER[2], INNER[3])
	end

	heads = ns.Pool(NewHead)
	heads.content = frame.content
	lines = ns.Pool(NewLine)
	lines.content = frame.content
	icons = ns.Pool(NewIcon)
	icons.content = frame.content
	return frame
end

local function Refresh(frame)
	local minimized = ns.Minimized()
	if minimized then
		frame:SetHeight(HEADER + 3)
	end
	frame.footer:SetShown(not minimized)
	frame.grip:SetShown(not minimized and not ns.Locked())
	frame.minimize.stem:SetShown(minimized)
end

local function RenderHeader(frame)
	local title = frame.title
	ns.StyleFont(title.text, 13)
	ns.StyleFont(title.count, 11)
	Color(title.text, GOLD)
	Color(title.count, DIM)
	title.text:SetText("Loot")
	title.count:SetText(#ns.Entries())
	ns.StyleFont(frame.scope.text, 11)
	frame.scope.text:SetText(SCOPES[Setting("scope")] or "All")
	Color(frame.scope.text, DIM)
	frame.scope:SetWidth(frame.scope.text:GetStringWidth() + 2)
	local footer = frame.footer
	ns.StyleFont(footer.label, 11)
	ns.StyleFont(footer.value, 11)
	Color(footer.label, SECTION)
	footer.value:SetText(ns.Money(ns.Totals and ns.Totals().value or 0))
	Color(footer.value, TEXT)
	Refresh(frame)
end

local function Render(frame, entries, width)
	local y, headCount, lineCount, iconCount = 0, 0, 0, 0
	local grouped = Setting("grouping") ~= "individual"
	local iconsView = Setting("view") == "icons"
	local withIcons = Setting("listIcons") and true or false
	local size = tonumber(Setting("iconSize")) or 24
	local showValue = Setting("itemValue") ~= "none"
	for _, entry in ipairs(entries) do
		headCount = headCount + 1
		local row = heads:Get(headCount)
		row.entry = entry
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT")
		row.portrait.icon:SetTexture(SourceIcon(entry))
		ns.StyleFont(row.name, 12)
		ns.StyleFont(row.value, 11)
		local count = grouped and (entry.count or 0) > 1 and (Hex(ACCENT) .. "[" .. entry.count .. "]|r ") or ""
		row.name:SetText(count .. (entry.name or "?"))
		Color(row.name, SECTION)
		local value = ns.Value(entry)
		row.value:SetText(value > 0 and ns.ShortMoney(value) or "")
		Color(row.value, GOLD)
		row:Show()
		y = y + HEAD + 2
		if not ns.Folded(entry.key) then
			if iconsView then
				local perRow = math.max(1, math.floor((width - 16) / (size + 4)))
				for index, item in ipairs(entry.items) do
					iconCount = iconCount + 1
					local button = icons:Get(iconCount)
					button.link, button.itemCount, button.money = item.link, item.count, nil
					local col, line = (index - 1) % perRow, math.floor((index - 1) / perRow)
					button:ClearAllPoints()
					button:SetPoint("TOPLEFT", 12 + col * (size + 4), -(y + line * (size + 4)))
					button:SetSize(size, size)
					button.icon:SetTexture(item.icon or [[Interface\Icons\INV_Misc_QuestionMark]])
					ns.StyleFont(button.count, math.max(9, math.floor(size * 0.4)), nil, "outline")
					button.count:SetText((item.count or 0) > 1 and item.count or "")
					local text, auction
					if Setting("iconValue") and showValue then
						text, auction = ns.ValueText(item.link, item.count, false)
					end
					if text then
						ns.StyleFont(button.value, math.max(8, math.floor(size * 0.32)), nil, "outline")
						button.value:SetText(text)
						Color(button.value, auction and GOLD or DIM)
					end
					button.value:SetShown(text and true or false)
					button:Show()
				end
				if #entry.items > 0 then
					y = y + math.ceil(#entry.items / perRow) * (size + 4)
				end
			else
				for _, item in ipairs(entry.items) do
					lineCount = lineCount + 1
					local line = lines:Get(lineCount)
					line.link, line.itemCount, line.money = item.link, item.count, nil
					line:ClearAllPoints()
					line:SetPoint("TOPLEFT", 0, -y)
					line:SetPoint("RIGHT")
					line.icon:SetTexture(item.icon or [[Interface\Icons\INV_Misc_QuestionMark]])
					line.edge:SetShown(withIcons)
					line.icon:SetShown(withIcons)
					line.name:SetPoint("LEFT", line, "LEFT", withIcons and ROW + 17 or 16, 0)
					ns.StyleFont(line.name, 11)
					ns.StyleFont(line.value, 10)
					local r, g, b = ns.QualityColor(item.quality)
					line.name:SetText(ns.ItemName(item) .. ((item.count or 0) > 1 and (Hex(DIM) .. "  x" .. item.count .. "|r") or ""))
					line.name:SetTextColor(r or 1, g or 1, b or 1)
					local itemValue = showValue and ns.ItemValue(item) or 0
					line.value:SetText(itemValue > 0 and ns.ShortMoney(itemValue) or "")
					Color(line.value, DIM)
					line:Show()
					y = y + ROW
				end
			end
			y = y + 6
		end
	end
	heads:HideFrom(headCount + 1)
	lines:HideFrom(lineCount + 1)
	icons:HideFrom(iconCount + 1)
	ns.StyleFont(frame.empty, 12)
	Color(frame.empty, DIM)
	frame.empty:SetShown(headCount == 0)
	return y
end

ns.RegisterStyle("flare", {
	Build = Build,
	Refresh = Refresh,
	RenderHeader = RenderHeader,
	Render = Render,
	minimizable = true,
})
