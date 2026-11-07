-- Pint's Tips: hold Shift over a player to see their talent trees beside the tooltip.
-- The trees come from the same inspect Pint's Tips already does for GearScore (the game allows one inspect at a time,
-- so this shares it rather than asking again). Inspecting needs them within about 28 yards and you out of combat;
-- once read, the trees stay available for that player (also in a fight) until you log out.
local PT = _G.PintsTips
if not PT then return end

local SIZE, GAP, TIERS, COLS = 22, 4, 7, 4
local TREE_W = COLS * (SIZE + GAP) - GAP
local PAD = 10

---------------------------------------------------------------- reading the trees
-- one reader for both game clients: the modern client (WoW Forever) puts an id first in the tab info
local function TabInfo(t, inspect)
	local ok, a, b, c, d, e, f = pcall(GetTalentTabInfo, t, inspect)
	if not ok or not a then return end
	if type(a) == "number" then return b, d, e, f end      -- id, name, description, icon, points, background
	return a, b, c, d                                       -- name, icon, points, background
end
local function TalentInfo(t, i, inspect)
	local ok, a, b, c, d, e, f = pcall(GetTalentInfo, t, i, inspect)
	if not ok or not a then return end
	if type(a) == "table" then return a.name, a.icon, a.tier, a.column, a.rank, a.maxRank end
	return a, b, c, d, e, f                                -- name, icon, tier, column, rank, max rank
end
-- the three trees: { name, points, icon, talents = { { name, icon, tier, column, rank, max } } }, or nil if unreadable
function PT.ReadGrid(inspect)
	if not GetTalentTabInfo or not GetTalentInfo then return end
	local out = {}
	for t = 1, 3 do
		local name, icon, pts = TabInfo(t, inspect)
		if not name or type(pts) ~= "number" then return end
		local tree = { name = name, points = pts, icon = icon, talents = {} }
		local n = 0
		local okN, num = pcall(GetNumTalents, t, inspect)
		if okN and type(num) == "number" then n = num end
		for i = 1, n do
			local tn, ti, tier, col, rank, max = TalentInfo(t, i, inspect)
			if tn and type(tier) == "number" and type(col) == "number" then
				tree.talents[#tree.talents + 1] = { tn, ti, tier, col, PT.Known(rank) or 0, PT.Known(max) or 0 }
			end
		end
		out[t] = tree
	end
	return out
end

---------------------------------------------------------------- the window
local win
local function Build()
	win = CreateFrame("Frame", "PintsTipsTalentPeek", UIParent, "BackdropTemplate")
	win:SetFrameStrata("TOOLTIP"); win:SetClampedToScreen(true)
	win:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
	win:SetBackdropColor(0.05, 0.05, 0.08, 0.95); win:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
	win:SetSize(PAD * 2 + TREE_W * 3 + 16 * 2, PAD * 2 + 34 + TIERS * (SIZE + GAP))
	win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal"); win.title:SetPoint("TOPLEFT", PAD + 2, -PAD)
	win.msg = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); win.msg:SetPoint("CENTER", 0, -8)
	win.trees, win.icons = {}, {}
	for t = 1, 3 do
		local x = PAD + (t - 1) * (TREE_W + 16)
		local h = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); h:SetPoint("TOPLEFT", x, -PAD - 18)
		h:SetWidth(TREE_W); h:SetJustifyH("CENTER")
		win.trees[t] = { head = h, x = x }
	end
	win:Hide()
end
local function Icon(i)
	local b = win.icons[i]
	if b then return b end
	b = CreateFrame("Frame", nil, win); b:SetSize(SIZE, SIZE)
	b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.rank = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"); b.rank:SetPoint("BOTTOMRIGHT", 3, -2)
	win.icons[i] = b
	return b
end

local function ClassHex(cls)
	local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
	return c and ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
end

local function Show(tt, name, cls, grid, note)
	if not win then Build() end
	win.title:SetText(ClassHex(cls) .. (name or "?") .. "|r  |cffd4a017talents|r")
	local used = 0
	if grid then
		win.msg:SetText("")
		for t = 1, 3 do
			local tree, slot = grid[t], win.trees[t]
			slot.head:SetText(("%s |cffffffff%d|r"):format(tree.name or "?", tree.points or 0))
			for _, d in ipairs(tree.talents) do
				used = used + 1
				local b = Icon(used)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", win, "TOPLEFT", slot.x + (d[4] - 1) * (SIZE + GAP), -PAD - 36 - (d[3] - 1) * (SIZE + GAP))
				b.tex:SetTexture(d[2])
				local rank, max = d[5], d[6]
				b.tex:SetDesaturated(rank == 0); b.tex:SetAlpha(rank == 0 and 0.35 or 1)
				if rank == 0 then b.edge:SetColorTexture(0, 0, 0, 0.8); b.rank:SetText("")
				elseif rank >= max then b.edge:SetColorTexture(1, 0.82, 0, 1); b.rank:SetText("|cffffd100" .. rank .. "|r")
				else b.edge:SetColorTexture(0.2, 0.9, 0.2, 1); b.rank:SetText("|cff40ff40" .. rank .. "|r") end
				b:Show()
			end
		end
	else
		for t = 1, 3 do win.trees[t].head:SetText("") end
		win.msg:SetText(note or "")
	end
	for i = used + 1, #win.icons do win.icons[i]:Hide() end
	win:ClearAllPoints()
	-- beside the tooltip, on whichever side has room
	local right = (tt:GetRight() or 0) + win:GetWidth() < (UIParent:GetRight() or 0)
	if right then win:SetPoint("TOPLEFT", tt, "TOPRIGHT", 2, 0) else win:SetPoint("TOPRIGHT", tt, "TOPLEFT", -2, 0) end
	win:Show()
end

---------------------------------------------------------------- when to show it
local function Hide() if win then win:Hide() end end
function PT.TalentPeek(tt, unit)
	local db = PT.db
	if not db or db.talentPeek == false or tt ~= GameTooltip then return Hide() end
	if not IsShiftKeyDown() or not unit or not UnitIsPlayer(unit) then return Hide() end
	local name, cls = UnitName(unit), select(2, UnitClass(unit))
	name, cls = PT.Known(name), PT.Known(cls)
	if PT.Known(UnitIsUnit(unit, "player")) then
		return Show(tt, name, cls, PT.ReadGrid(false), "Couldn't read your talents.")
	end
	local guid = PT.SafeGUID(unit)
	local c = guid and PT.cache[guid]
	if c and c.grid then return Show(tt, name, cls, c.grid) end
	local why
	if InCombatLockdown() then why = "Can't inspect in a fight - try again after."
	elseif not CanInspect(unit) then why = "The game won't let you inspect them."
	elseif CheckInteractDistance and not PT.Secret and not CheckInteractDistance(unit, 1) then why = "Too far away - get within about 28 yards."
	else why = "Reading..."; PT.TryInspect(unit, true) end
	Show(tt, name, cls, nil, why)
end

-- pressing or letting go of Shift while the tooltip is up
local ev = CreateFrame("Frame")
ev:RegisterEvent("MODIFIER_STATE_CHANGED")
ev:SetScript("OnEvent", function(_, _, key)
	if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
	if GameTooltip:IsShown() and UnitExists("mouseover") then PT.TalentPeek(GameTooltip, "mouseover") else Hide() end
end)
GameTooltip:HookScript("OnHide", Hide)
