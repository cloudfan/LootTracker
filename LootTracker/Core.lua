local addonName, ns = ...

-- Loot Tracker's core: the few things its tracking and view need, written
-- for this addon alone (no library, no other addon): settings, events and
-- messages, printing, secret-value guards, a draggable frame, a bordered
-- panel, the game's fonts and bar textures, colors, a scroll bar and a box
-- to copy text from. ns.API holds them, under the names the code uses.

local API = {}
ns.API = API
API.name = "Loot Tracker"
API.BRONZE = { 0.8, 0.5, 0.2, 1 }

-- Settings ---------------------------------------------------------------------------
-- By section; only changed values are kept (LootTrackerSettings, account-wide).

local defaults = {}
local db
local listeners = {}

local function Copy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = Copy(v)
	end
	return copy
end

function API.RegisterDefaults(section, values)
	defaults[section] = defaults[section] or {}
	for k, v in pairs(values) do
		defaults[section][k] = v
	end
end

-- Shared looks a setting can name as "global".
API.RegisterDefaults("global", { barTexture = "Blizzard", background = "Solid", font = "friz" })
API.RegisterDefaults("positions", {})

function API.GetDefault(section, key)
	return defaults[section] and defaults[section][key]
end

function API.Get(section, key)
	local values = db and db[section]
	local value = values and values[key]
	if value == nil then
		value = API.GetDefault(section, key)
	end
	return value
end

function API.Listen(message, fn)
	listeners[message] = listeners[message] or {}
	table.insert(listeners[message], fn)
end

function API.Fire(message, ...)
	for _, fn in ipairs(listeners[message] or {}) do
		fn(...)
	end
end

function API.Set(section, key, value)
	if not db then
		return
	end
	db[section] = db[section] or {}
	db[section][key] = Copy(value)
	API.Fire("SettingChanged", section, key, value)
end

function API.ClearSection(section)
	if db then
		db[section] = nil
		API.Fire("SettingChanged", section)
	end
end

-- Events -----------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

-- With Pillars UI's own Loot Tracker module on, this addon stands down:
-- both would track every loot and show a frame.
local function PillarsModuleOn()
	if ns.standingDown then
		return true
	end
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	if loaded and loaded("PillarsUI_LootTracker") then
		ns.standingDown = true
		API.Fire("StandDown")
		API.Print("Pillars UI's Loot Tracker module is on, so this Loot Tracker stays off. Turn one of the two off.")
		return true
	end
	return false
end

function API.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		-- An event this client does not have is skipped (registering it is
		-- an error that would stop the rest of the file).
		pcall(events.RegisterEvent, events, event)
	end
	table.insert(handlers[event], fn)
end
API.OnPlayer = API.On

local ready = {}
function API.OnReady(fn)
	if db then
		fn()
	else
		ready[#ready + 1] = fn
	end
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" and (...) == addonName then
		LootTrackerSettings = type(LootTrackerSettings) == "table" and LootTrackerSettings or {}
		db = LootTrackerSettings
	end
	if event ~= "ADDON_LOADED" and PillarsModuleOn() then
		return
	end
	-- One handler's error is reported and the rest still run.
	for _, fn in ipairs(handlers[event] or {}) do
		local ok, err = pcall(fn, event, ...)
		if not ok then
			geterrorhandler()(err)
		end
	end
	if event == "ADDON_LOADED" and (...) == addonName then
		local list = ready
		ready = {}
		for _, fn in ipairs(list) do
			fn()
		end
	end
end)
events:RegisterEvent("ADDON_LOADED")

function API.Print(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cffcc8033Loot Tracker:|r " .. table.concat(parts, " "))
end

function API.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end

function API.Plain(value, fallback)
	if API.IsSecret(value) then
		return fallback
	end
	return value
end

-- What other code might ask of Pillars UI, answered for an addon on its own.
function API.IsModuleLoaded()
	return false
end
function API.RegisterAnchor() end
function API.RegisterBoxPanel() end
local probes = {}
function API.RegisterProbe(fn)
	probes[#probes + 1] = fn
end
function API.ProbeLines()
	local out = {}
	for _, fn in ipairs(probes) do
		local ok, label, text = pcall(fn)
		if ok and label then
			out[#out + 1] = label .. ": " .. tostring(text)
		end
	end
	return out
end

-- Colors -----------------------------------------------------------------------------
-- Color settings are { preset = "<key>" } or { preset = "custom", r, g, b, a }.

local PRESETS = {
	bronze = API.BRONZE, gold = { 1, 0.82, 0, 1 }, silver = { 0.75, 0.75, 0.8, 1 },
	white = { 1, 1, 1, 1 }, black = { 0, 0, 0, 1 }, red = { 0.8, 0.1, 0.1, 1 },
	green = { 0.2, 0.8, 0.2, 1 }, blue = { 0.2, 0.4, 1, 1 }, purple = { 0.6, 0.3, 0.9, 1 },
}

function API.ResolveColor(setting)
	if type(setting) ~= "table" then
		return 1, 1, 1, 1
	end
	if setting.preset == "custom" or setting.preset == nil then
		return setting.r or 1, setting.g or 1, setting.b or 1, setting.a or 1
	end
	if setting.preset == "class" then
		local _, class = UnitClass("player")
		local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if c then
			return c.r, c.g, c.b, 1
		end
	end
	local color = PRESETS[setting.preset]
	if color then
		return unpack(color)
	end
	return 1, 1, 1, 1
end

-- Media: the game's own fonts, bar textures and backgrounds ------------------------

API.MEDIA = { FONT = "font", STATUSBAR = "statusbar", BACKGROUND = "background" }

local MEDIA = {
	font = {
		{ "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
		{ "Arial Narrow", "Fonts\\ARIALN.TTF" },
		{ "Morpheus", "Fonts\\MORPHEUS.TTF" },
		{ "Skurri", "Fonts\\SKURRI.TTF" },
	},
	statusbar = {
		{ "Blizzard", "Interface\\TargetingFrame\\UI-StatusBar" },
		{ "Flat", "Interface\\Buttons\\WHITE8X8" },
		{ "Raid", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
		{ "Character Skills", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
	},
	background = {
		{ "Solid", "Interface\\Buttons\\WHITE8X8" },
		{ "Dialog", "Interface\\DialogFrame\\UI-DialogBox-Background" },
		{ "Dialog Dark", "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" },
		{ "Tooltip", "Interface\\Tooltips\\UI-Tooltip-Background" },
	},
}

-- LibSharedMedia-3.0 (bundled in Libs, and shared with every other addon that
-- has it): the game's own media above are registered into it, so their names
-- always work, and fonts, bar textures and backgrounds other addons register
-- (SharedMedia packs, UI suites) show up in the lists too.
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
API.LSM = LSM
if LSM then
	-- Only what SharedMedia lacks: it already knows most of the game's own
	-- (under its own names); ours still resolve by name (Fetch, below).
	for kind, entries in pairs(MEDIA) do
		local known = {}
		for _, path in pairs(LSM:HashTable(kind) or {}) do
			known[tostring(path):lower()] = true
		end
		for _, entry in ipairs(entries) do
			if not known[entry[2]:lower()] then
				LSM:Register(kind, entry[1], entry[2])
			end
		end
	end
	-- A list that grows while the game runs (other addons registering late).
	LSM.RegisterCallback(API, "LibSharedMedia_Registered", function(_, kind)
		API.Fire("MediaRegistered", kind)
	end)
end

function API.MediaList(kind)
	if LSM and LSM.List then
		local names = {}
		for _, name in ipairs(LSM:List(kind)) do
			names[#names + 1] = name
		end
		return names
	end
	local names = {}
	for _, entry in ipairs(MEDIA[kind] or {}) do
		names[#names + 1] = entry[1]
	end
	return names
end

function API.Fetch(kind, name)
	if LSM and name and LSM:IsValid(kind, name) then
		return LSM:Fetch(kind, name)
	end
	for _, entry in ipairs(MEDIA[kind] or {}) do
		if entry[1] == name then
			return entry[2]
		end
	end
	local first = MEDIA[kind] and MEDIA[kind][1]
	return first and first[2]
end

-- options: font (a name, nil: Friz Quadrata), size, shadow ("none", "soft",
-- "outline", "thick"; nil: soft), color (a color setting, false: leave it).
function API.ApplyFont(fontString, options)
	local file = API.Fetch("font", options.font or "Friz Quadrata")
	local shadow = options.shadow or "soft"
	local flags = shadow == "outline" and "OUTLINE" or shadow == "thick" and "THICKOUTLINE" or ""
	if not fontString:SetFont(file, options.size or 12, flags) then
		fontString:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", options.size or 12, flags)
	end
	if shadow == "soft" then
		fontString:SetShadowColor(0, 0, 0, 1)
		fontString:SetShadowOffset(1, -1)
	else
		fontString:SetShadowOffset(0, 0)
	end
	if options.color then
		fontString:SetTextColor(API.ResolveColor(options.color))
	end
end

-- A bordered panel ---------------------------------------------------------------------
-- A tooltip-style border over a background, behind the frame's content.

function API.InsetBorderReach()
	return 4
end

function API.CreateInsetBorder(parent)
	local border = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	border:SetPoint("TOPLEFT", -4, 4)
	border:SetPoint("BOTTOMRIGHT", 4, -4)
	border:SetFrameLevel(math.max(0, parent:GetFrameLevel() - 1))
	local edgeShown = true
	local bgFile, bgAlpha = API.Fetch("background", "Solid"), 0.8
	local function Dress()
		if not border.SetBackdrop then
			return
		end
		border:SetBackdrop({
			bgFile = bgFile,
			edgeFile = edgeShown and "Interface\\Tooltips\\UI-Tooltip-Border" or nil,
			tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		local solid = bgFile == API.Fetch("background", "Solid")
		border:SetBackdropColor(solid and 0 or 1, solid and 0 or 1, solid and 0 or 1, bgAlpha)
		border:SetBackdropBorderColor(API.BRONZE[1], API.BRONZE[2], API.BRONZE[3], 1)
	end
	-- Shown: the border line (the background stays).
	function border:SetShown(shown)
		edgeShown = shown and true or false
		Dress()
	end
	function border:SetBackground(key, alpha)
		if key == "global" then
			key = API.Get("global", "background")
		end
		bgFile = API.Fetch("background", key)
		bgAlpha = alpha or 1
		Dress()
	end
	Dress()
	return border
end

-- Moving the frame: while unlocked (/lt unlock), a handle over it drags it;
-- its place is kept in the positions section.

local movers = {}

function API.RegisterMover(frame, key, label, default, active)
	local mover = CreateFrame("Frame", nil, UIParent)
	mover:SetFrameStrata("DIALOG")
	mover:SetAllPoints(frame)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:Hide()
	local fill = mover:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(API.BRONZE[1], API.BRONZE[2], API.BRONZE[3], 0.25)
	local text = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("CENTER")
	text:SetText(label .. "\n|cffaaaaaadrag, then /lt lock|r")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	mover:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	mover:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local point, _, relativePoint, x, y = frame:GetPoint(1)
		API.Set("positions", key, { point, relativePoint, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) })
	end)
	mover.frame, mover.key, mover.default, mover.active = frame, key, default, active
	movers[#movers + 1] = mover
	return mover
end

function API.RefreshMover(mover)
	if not mover then
		return
	end
	local saved = API.Get("positions", mover.key)
	local frame = mover.frame
	frame:ClearAllPoints()
	if type(saved) == "table" then
		frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
	else
		local d = mover.default
		frame:SetPoint(d[1], d[2] or UIParent, d[3], d[4], d[5])
	end
	local unlocked = not API.Get("loot", "locked")
	mover:SetShown(unlocked and (not mover.active or mover.active()) and frame:IsShown() or false)
end

API.RegisterDefaults("loot", { locked = true })

function API.SetUnlocked(unlocked)
	API.Set("loot", "locked", not unlocked)
	API.Fire("MoversShown", unlocked)
	for _, mover in ipairs(movers) do
		API.RefreshMover(mover)
	end
end

function API.ResetPositions()
	if db then
		db.positions = nil
	end
	for _, mover in ipairs(movers) do
		API.RefreshMover(mover)
	end
end

-- The scroll bar (the thumb's length is the view's share of the content) ---------

local function NewScrollBar(parent, scroll, width, step, onScroll)
	local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	bar:SetWidth(width)
	bar:SetBackdrop({ bgFile = [[Interface\Buttons\WHITE8X8]] })
	bar:SetBackdropColor(0, 0, 0, 0.4)
	bar:EnableMouse(true)
	local thumb = CreateFrame("Button", nil, bar)
	thumb:SetWidth(width)
	thumb:SetHeight(16)
	local fill = thumb:CreateTexture(nil, "OVERLAY")
	fill:SetAllPoints()
	fill:SetColorTexture(API.BRONZE[1], API.BRONZE[2], API.BRONZE[3], 0.9)
	bar.thumb = thumb
	bar.value, bar.range = 0, 0

	-- How far the thumb can travel, and where it sits for the value.
	local function Travel()
		return math.max(1, bar:GetHeight() - thumb:GetHeight())
	end
	local function Place()
		local offset = bar.range > 0 and (bar.value / bar.range) * Travel() or 0
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", bar, "TOP", 0, -offset)
	end

	function bar:SetValue(value)
		self.value = math.max(0, math.min(self.range, value or 0))
		scroll:SetVerticalScroll(self.value)
		Place()
		if onScroll then
			onScroll(self.value)
		end
	end
	function bar:GetValue()
		return self.value
	end
	function bar:GetMinMaxValues()
		return 0, self.range
	end

	-- The cursor's height in the bar's own scale.
	local function CursorY()
		local _, y = GetCursorPosition()
		return y / bar:GetEffectiveScale()
	end
	thumb:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then
			return
		end
		local startY, startValue = CursorY(), bar.value
		self:SetScript("OnUpdate", function()
			local moved = startY - CursorY() -- down is positive
			bar:SetValue(startValue + moved * bar.range / Travel())
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	thumb:SetScript("OnHide", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	bar:SetScript("OnMouseDown", function(self, button)
		local top = self:GetTop()
		if button ~= "LeftButton" or not top then
			return
		end
		local offset = top - CursorY() - thumb:GetHeight() / 2
		self:SetValue(offset / Travel() * self.range)
	end)

	local function Wheel(_, delta)
		bar:SetValue(bar.value - delta * step)
	end
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", Wheel)
	bar:EnableMouseWheel(true)
	bar:SetScript("OnMouseWheel", Wheel)

	function bar:Update(contentHeight)
		self.content = contentHeight
		local view = scroll:GetHeight()
		self.range = math.max(0, (contentHeight or 0) - view)
		self:SetShown(self.range > 0)
		local track = self:GetHeight()
		if track and track > 0 then
			thumb:SetHeight(math.max(16, math.min(track, track * view / math.max(view + self.range, 1))))
		end
		self:SetValue(self.value)
	end
	-- Sizes are only known once the window is laid out: measure again then.
	bar:SetScript("OnSizeChanged", function(self)
		self:Update(self.content)
	end)
	return bar
end
-- For modules: the same scroll bar (bar:Update(contentHeight) after each
-- layout, bar:SetValue(offset)); it takes the scroll frame's mouse wheel.
API.NewScrollBar = NewScrollBar

-- A box to copy text from: Ctrl+A, Ctrl+C. Read only. -----------------------------

local copyBox

function API.ShowCopyBox(title, text)
	if not copyBox then
		copyBox = CreateFrame("Frame", "LootTrackerCopyBox", UIParent)
		copyBox:SetSize(620, 380)
		copyBox:SetPoint("CENTER")
		copyBox:SetFrameStrata("DIALOG")
		copyBox:SetToplevel(true)
		copyBox:EnableMouse(true)
		copyBox:SetMovable(true)
		copyBox:RegisterForDrag("LeftButton")
		copyBox:SetScript("OnDragStart", copyBox.StartMoving)
		copyBox:SetScript("OnDragStop", copyBox.StopMovingOrSizing)
		copyBox:SetClampedToScreen(true)
		copyBox.border = API.CreateInsetBorder(copyBox)
		copyBox.border:SetBackground("Solid", 0.92)
		copyBox.title = copyBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		copyBox.title:SetPoint("TOPLEFT", 10, -8)
		copyBox.hint = copyBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		copyBox.hint:SetPoint("TOPRIGHT", -10, -12)
		copyBox.hint:SetText("Ctrl+A, Ctrl+C to copy")
		local scroll = CreateFrame("ScrollFrame", nil, copyBox)
		scroll:SetPoint("TOPLEFT", 10, -32)
		scroll:SetPoint("BOTTOMRIGHT", -26, 40)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject("ChatFontNormal")
		edit:SetWidth(584)
		edit:SetScript("OnEscapePressed", function()
			copyBox:Hide()
		end)
		edit:SetScript("OnTextChanged", function(self, userInput)
			if userInput then
				self:SetText(copyBox.text or "")
				self:HighlightText()
			end
		end)
		scroll:SetScrollChild(edit)
		local bar = NewScrollBar(copyBox, scroll, 10, 40)
		bar:SetPoint("TOPRIGHT", -10, -32)
		bar:SetPoint("BOTTOMRIGHT", -10, 40)
		copyBox.bar = bar
		edit:SetScript("OnSizeChanged", function(self)
			bar:Update(self:GetHeight())
		end)
		scroll:SetScript("OnSizeChanged", function(self)
			edit:SetWidth(math.max(1, self:GetWidth()))
			bar:Update(edit:GetHeight())
		end)
		copyBox.edit = edit
		local close = CreateFrame("Button", nil, copyBox, "UIPanelButtonTemplate")
		close:SetSize(100, 24)
		close:SetPoint("BOTTOMRIGHT", -10, 10)
		close:SetText(CLOSE or "Close")
		close:SetScript("OnClick", function()
			copyBox:Hide()
		end)
		tinsert(UISpecialFrames, "LootTrackerCopyBox")
	end
	text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	copyBox.text = text
	copyBox.title:SetText(title or API.name)
	copyBox:Show()
	copyBox.edit:SetText(text)
	copyBox.edit:SetFocus()
	copyBox.edit:HighlightText()
	copyBox.bar:SetValue(0)
	copyBox.bar:Update(copyBox.edit:GetHeight())
	C_Timer.After(0, function()
		copyBox.bar:Update(copyBox.edit:GetHeight())
		copyBox.bar:SetValue(0)
	end)
end
