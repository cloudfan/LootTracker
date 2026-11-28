local addonName, ns = ...
local API = ns.API

-- Style "quest": in the look of the game's quest tracker (the objective
-- tracker). No panel: a header ("Loot", the total, a minimize button), then
-- each source as a quest title (its kill count in brackets, like a quest's
-- level) with its loot under it as objectives ("- 4 Linen Cloth"). Titles in
-- the tracker's gold, brighter while hovered; objectives in its soft white,
-- items of Uncommon and up in their quality's color. While unlocked, a faint
-- backing shows where the window is, and its resize grip.

local Setting = ns.Setting

-- The objective tracker's own colors.
local HEADER = { 0.75, 0.61, 0 }
local HEADER_HIGHLIGHT = { 1, 0.82, 0 }
local NORMAL = { 0.8, 0.8, 0.8 }
local NORMAL_HIGHLIGHT = { 1, 1, 1 }
local DIM = { 0.55, 0.55, 0.55 }

local TITLE, LINE, GAP = 16, 15, 9

local titles, lines, icons

local function SetColor(fontString, color)
	fontString:SetTextColor(color[1], color[2], color[3])
end

-- A title's objectives light up with it, as the tracker's do.
local function HoverBlock(title, inside)
	SetColor(title.name, inside and HEADER_HIGHLIGHT or HEADER)
	for _, line in ipairs(title.block or {}) do
		if line.plain then
			SetColor(line.name, inside and NORMAL_HIGHLIGHT or NORMAL)
		end
	end
end

local function NewTitle()
	local row = CreateFrame("Button", nil, titles.content)
	row:SetHeight(TITLE)
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.value:SetPoint("RIGHT", -2, 0)
	row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	ns.SourceScripts(row, HoverBlock)
	return row
end

local function NewLine()
	local row = CreateFrame("Button", nil, lines.content)
	row:SetHeight(LINE)
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.name:SetPoint("LEFT", 14, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.value:SetPoint("RIGHT", -2, 0)
	row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	ns.ItemScripts(row, function(self, inside)
		if self.plain then
			SetColor(self.name, inside and NORMAL_HIGHLIGHT or NORMAL)
		end
		if self.title then
			HoverBlock(self.title, inside)
		end
	end)
	return row
end

local function NewIcon()
	local button = CreateFrame("Button", nil, icons.content)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.edge = button:CreateTexture(nil, "OVERLAY")
	button.edge:SetTexture([[Interface\Common\WhiteIconFrame]])
	button.edge:SetAllPoints()
	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.count:SetPoint("BOTTOMRIGHT", -1, 2)
	button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
	button.highlight:SetAllPoints()
	button.highlight:SetColorTexture(1, 1, 1, 0.15)
	ns.ItemScripts(button)
	return button
end

local function Build()
	local frame = ns.NewStyleFrame("quest", 3)
	ns.PaintScrollBar(frame.bar, 0, 0, 0, 0, HEADER[1], HEADER[2], HEADER[3], 0.5)

	-- While unlocked: a faint backing, so the window can be found and moved.
	frame.back = ns.Fill(frame, "BACKGROUND", 0, 0, 0, 0.35)
	frame.back:SetAllPoints()

	local header = CreateFrame("Button", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(26)
	header.bg = header:CreateTexture(nil, "BACKGROUND")
	if ns.TrySetAtlas(header.bg, "UI-QuestTracker-Primary-Objective-Header", "Objective-Header") then
		header.bg:SetPoint("TOPLEFT", -10, 8)
		header.bg:SetPoint("BOTTOMRIGHT", 10, -10)
	else
		-- The tracker's header bar: a dark band fading out, a gold rule under it.
		header.bg:SetPoint("TOPLEFT")
		header.bg:SetPoint("BOTTOMRIGHT")
		ns.Gradient(header.bg, 0, 0, 0, 0.6, 0, 0, 0, 0)
		local rule = header:CreateTexture(nil, "BORDER")
		rule:SetPoint("BOTTOMLEFT", 0, 1)
		rule:SetPoint("BOTTOMRIGHT", 0, 1)
		rule:SetHeight(1)
		ns.Gradient(rule, HEADER[1], HEADER[2], HEADER[3], 0.8, HEADER[1], HEADER[2], HEADER[3], 0)
	end
	header.text = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header.text:SetPoint("LEFT", 6, 0)
	header.text:SetText("Loot")
	header.value = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	header.value:SetPoint("LEFT", header.text, "RIGHT", 8, -1)
	ns.DragHandle(frame, header)
	frame.header = header

	-- Minimize: the list folds away, the header stays (the tracker's button).
	local minimize = CreateFrame("Button", nil, header)
	minimize:SetSize(16, 16)
	minimize:SetPoint("RIGHT", -4, 0)
	minimize:SetScript("OnClick", ns.ToggleMinimized)
	minimize:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(ns.Minimized() and "Expand" or "Minimize")
		GameTooltip:AddLine("Right-click the header for the Loot Tracker's menu.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	minimize:SetScript("OnLeave", GameTooltip_Hide)
	frame.minimize = minimize

	frame.scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	frame.scroll:SetPoint("BOTTOMRIGHT", -6, 4)
	frame.bar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -1, -4)
	frame.bar:SetPoint("BOTTOMRIGHT", -1, 4)

	frame.empty = frame.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.empty:SetPoint("TOPLEFT", 4, -2)
	frame.empty:SetText("Nothing looted yet.")

	ns.ChatGripArt(ns.ResizeGrip(frame))

	titles = ns.Pool(NewTitle)
	titles.content = frame.content
	lines = ns.Pool(NewLine)
	lines.content = frame.content
	icons = ns.Pool(NewIcon)
	icons.content = frame.content
	return frame
end

local function PaintMinimize(frame)
	local minimized = ns.Minimized()
	local button = frame.minimize
	local up = minimized and "UI-QuestTrackerButton-Expand-All" or "UI-QuestTrackerButton-Collapse-All"
	local normal = button:GetNormalTexture() or button:CreateTexture(nil, "ARTWORK")
	if ns.TrySetAtlas(normal, up) then
		button:SetNormalTexture(normal)
		local pushed = button:GetPushedTexture() or button:CreateTexture(nil, "ARTWORK")
		if not ns.TrySetAtlas(pushed, up .. "-Pressed") then
			ns.TrySetAtlas(pushed, up)
		end
		button:SetPushedTexture(pushed)
	else
		button:SetNormalTexture(minimized and [[Interface\Buttons\UI-PlusButton-Up]] or [[Interface\Buttons\UI-MinusButton-Up]])
		button:SetPushedTexture(minimized and [[Interface\Buttons\UI-PlusButton-Down]] or [[Interface\Buttons\UI-MinusButton-Down]])
	end
	button:SetHighlightTexture([[Interface\Buttons\UI-PlusButton-Hilight]], "ADD")
end

local function Refresh(frame)
	local unlocked = not ns.Locked()
	frame.back:SetShown(unlocked)
	frame.grip:SetShown(unlocked and not ns.Minimized())
	PaintMinimize(frame)
end

local function RenderHeader(frame)
	ns.StyleFont(frame.header.text, 14)
	ns.StyleFont(frame.header.value, 11)
	local total = ns.Totals and ns.Totals().value or 0
	frame.header.value:SetText(total > 0 and ns.Money(total) or "")
	local scope = Setting("scope")
	frame.header.text:SetText(scope == "session" and "Loot: Session" or scope == "instance" and "Loot: Instance" or "Loot")
	frame.grip:SetShown(not ns.Locked() and not ns.Minimized())
	PaintMinimize(frame)
end

local function Render(frame, entries, width)
	local y, titleCount, lineCount, iconCount = 0, 0, 0, 0
	local grouped = Setting("grouping") ~= "individual"
	local iconsView = Setting("view") == "icons"
	local size = tonumber(Setting("iconSize")) or 24
	local showValue = Setting("itemValue") ~= "none"

	local function Objective(title, text, color, plain, value)
		lineCount = lineCount + 1
		local line = lines:Get(lineCount)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", 0, -y)
		line:SetPoint("RIGHT")
		ns.StyleFont(line.name, 12)
		ns.StyleFont(line.value, 10)
		line.name:SetText(text)
		SetColor(line.name, color)
		SetColor(line.value, DIM)
		line.value:SetText(value or "")
		line.plain, line.title = plain, title
		line:Show()
		title.block[#title.block + 1] = line
		y = y + LINE
		return line
	end

	for _, entry in ipairs(entries) do
		titleCount = titleCount + 1
		local title = titles:Get(titleCount)
		title.entry, title.block = entry, {}
		title:ClearAllPoints()
		title:SetPoint("TOPLEFT", 0, -y)
		title:SetPoint("RIGHT")
		ns.StyleFont(title.name, 12)
		ns.StyleFont(title.value, 10)
		local count = grouped and (entry.count or 0) > 1 and ("[" .. entry.count .. "] ") or ""
		title.name:SetText(count .. (entry.name or "?"))
		SetColor(title.name, HEADER)
		local value = ns.Value(entry)
		title.value:SetText(value > 0 and ns.ShortMoney(value) or "")
		SetColor(title.value, DIM)
		title:Show()
		y = y + TITLE
		if not ns.Folded(entry.key) then
			if (entry.money or 0) > 0 then
				local line = Objective(title, "- " .. ns.Money(entry.money), NORMAL, true)
				line.link, line.money = nil, entry.money
			end
			if iconsView then
				local perRow = math.max(1, math.floor((width - 16) / (size + 3)))
				for index, item in ipairs(entry.items) do
					iconCount = iconCount + 1
					local button = icons:Get(iconCount)
					button.link, button.itemCount, button.money = item.link, item.count, nil
					local col, row = (index - 1) % perRow, math.floor((index - 1) / perRow)
					button:ClearAllPoints()
					button:SetPoint("TOPLEFT", 14 + col * (size + 3), -(y + 2 + row * (size + 3)))
					button:SetSize(size, size)
					button.icon:SetTexture(item.icon or [[Interface\Icons\INV_Misc_QuestionMark]])
					button.edge:SetVertexColor(ns.QualityColor(item.quality))
					ns.StyleFont(button.count, math.max(9, math.floor(size * 0.42)), nil, "outline")
					button.count:SetText((item.count or 0) > 1 and item.count or "")
					button:Show()
				end
				if #entry.items > 0 then
					y = y + 4 + math.ceil(#entry.items / perRow) * (size + 3)
				end
			else
				for _, item in ipairs(entry.items) do
					local plain = (item.quality or 1) <= 1
					local color = NORMAL
					if (item.quality or 1) == 0 or not plain then
						local r, g, b = ns.QualityColor(item.quality)
						color = { r, g, b }
					end
					local itemValue = showValue and ns.ItemValue(item) or 0
					local line = Objective(title, ("- %d %s"):format(item.count or 1, ns.ItemName(item)), color, plain and (item.quality or 1) == 1,
						itemValue > 0 and ns.ShortMoney(itemValue) or nil)
					line.link, line.itemCount, line.money = item.link, item.count, nil
				end
			end
		end
		y = y + GAP
	end
	titles:HideFrom(titleCount + 1)
	lines:HideFrom(lineCount + 1)
	icons:HideFrom(iconCount + 1)
	ns.StyleFont(frame.empty, 12)
	SetColor(frame.empty, NORMAL)
	frame.empty:SetShown(titleCount == 0)
	return y
end

ns.RegisterStyle("quest", {
	Build = Build,
	Refresh = Refresh,
	RenderHeader = RenderHeader,
	Render = Render,
	minimizable = true,
})
