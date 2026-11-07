-- Pint's Tips: better tooltips.
--   Players: class-coloured name, title, guild and rank, talents, GearScore and average item level, what they target.
--   Items: item level and the item's GearScore.   Character (and inspect) window: your GearScore and item level.
--   Tooltip position: Blizzard's corner, at the cursor, or a spot you choose.
-- Also provides TT_GS (GetScore / GetQuality / GetItemScore) so add-ons that read TacoTip's GearScore - Pint's Ledger,
-- GearScore Log - keep working without TacoTip. Same GearScore maths as TacoTip / GearScoreLite, Classic scale.
local ADDON = ...
-- the modern game client (WoW Forever) keeps some answers "secret" from add-ons
local Secret = type(issecretvalue) == "function"
local function Known(v) if Secret and issecretvalue(v) then return nil end return v end
-- Compatibility: WoW Forever runs on the modern game client, where these older functions moved or were renamed.
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local IsAddOnLoaded = IsAddOnLoaded or (C_AddOns and C_AddOns.IsAddOnLoaded)
local GetMouseFocus = GetMouseFocus or function() local t = GetMouseFoci and GetMouseFoci(); return t and t[1] end

local PT = {}
_G.PintsTips = PT

local DEFAULTS = {
	classColor = true, title = true, guild = true, talents = true, talentPeek = true, gearscore = true, ilvl = true, target = true,
	itemLevel = true, itemScore = true, charFrame = true, usedFor = true, counts = true, recipeAlts = true, itemID = false, anchor = "default", ax = -40, ay = 120, inCombat = true, minimap = {},
}
local db
local function Print(m) print("|cffd4a017Pint's Tips:|r " .. m) end

---------------------------------------------------------------- GearScore (Classic brackets of 200)
local BRACKET = 200
local MAX_SCORE = BRACKET * 6 - 1
local SLOT_MOD = {
	INVTYPE_RELIC = 0.3164, INVTYPE_TRINKET = 0.5625, INVTYPE_2HWEAPON = 2.0, INVTYPE_WEAPONMAINHAND = 1.0, INVTYPE_WEAPONOFFHAND = 1.0,
	INVTYPE_RANGED = 0.3164, INVTYPE_THROWN = 0.3164, INVTYPE_RANGEDRIGHT = 0.3164, INVTYPE_SHIELD = 1.0, INVTYPE_WEAPON = 1.0,
	INVTYPE_HOLDABLE = 1.0, INVTYPE_HEAD = 1.0, INVTYPE_NECK = 0.5625, INVTYPE_SHOULDER = 0.75, INVTYPE_CHEST = 1.0, INVTYPE_ROBE = 1.0,
	INVTYPE_WAIST = 0.75, INVTYPE_LEGS = 1.0, INVTYPE_FEET = 0.75, INVTYPE_WRIST = 0.5625, INVTYPE_HAND = 0.75, INVTYPE_FINGER = 0.5625,
	INVTYPE_CLOAK = 0.5625, INVTYPE_BODY = 0,
}
local FORMULA = {
	A = { [4] = { 91.45, 0.65 }, [3] = { 81.375, 0.8125 }, [2] = { 73, 1 } },
	B = { [4] = { 26, 1.2 }, [3] = { 0.75, 1.8 }, [2] = { 8, 2 }, [1] = { 0, 2.25 } },
	C = { [4] = { 0.25, 1.6275 } },
}
-- colour bands: { r = {A, B, C, D}, g = ..., b = ..., name }  value = A + (score - B) * C * D
local BANDS = {
	[6] = { { 0.94, 5, 0.00006, 1 }, { 0, 0, 0, 0 }, { 0.47, 5, 0.00047, -1 }, "Legendary" },
	[5] = { { 0.69, 4, 0.00025, 1 }, { 0.97, 4, 0.00096, -1 }, { 0.28, 4, 0.00019, 1 }, "Epic" },
	[4] = { { 0.0, 3, 0.00069, 1 }, { 1, 3, 0.00003, -1 }, { 0.5, 3, 0.00022, -1 }, "Superior" },
	[3] = { { 0.12, 2, 0.00012, -1 }, { 0, 2, 0.001, 1 }, { 1, 2, 0.0005, -1 }, "Uncommon" },
	[2] = { { 1, 1, 0.00088, -1 }, { 1, 1, 0.001, -1 }, { 1, 0, 0, 0 }, "Common" },
	[1] = { { 0.55, 0, 0.00045, 1 }, { 0.55, 0, 0.00045, 1 }, { 0.55, 0, 0.00045, 1 }, "Trash" },
}
local function Band(c, score) return c[1] + (score - c[2] * BRACKET) * c[3] * c[4] end
-- the r, g, b columns above are the order TacoTip's numbers come out in, so colours match it exactly
local function Quality(score)
	score = tonumber(score)
	if not score then return 0, 0, 0, "Trash" end
	if score > MAX_SCORE then score = MAX_SCORE end
	for i = 0, 5 do
		if score > i * BRACKET and score <= (i + 1) * BRACKET then
			local q = BANDS[i + 1]
			return Band(q[1], score), Band(q[3], score), Band(q[2], score), q[4]
		end
	end
	return 0.1, 0.1, 0.1, "Trash"
end
local function ItemScore(link)
	if not link then return 0, 0 end
	local _, _, rarity, level, _, _, _, _, loc = GetItemInfo(link)
	if not (rarity and level and loc and SLOT_MOD[loc]) then return 0, 0 end
	local qs = 1
	if rarity == 5 then qs = 1.3; rarity = 4
	elseif rarity == 1 or rarity == 0 then qs = 0.005; rarity = 2
	elseif rarity == 7 then rarity = 3; level = 187.05 end
	local t
	if level < 100 and rarity == 4 then t = FORMULA.C
	elseif (level < 168 and rarity == 4) or (level < 148 and rarity == 3) or (level < 138 and rarity == 2) or level <= 120 then t = FORMULA.B
	else t = FORMULA.A end
	if rarity < 2 or rarity > 4 or not t[rarity] then return 0, level end
	local base = math.floor(((level - t[rarity][1]) / t[rarity][2]) * 1.8618)    -- slot-free value, used for the colour
	local score = math.floor(((level - t[rarity][1]) / t[rarity][2]) * SLOT_MOD[loc] * 1.8618 * qs)
	if level == 187.05 then level = 0 end
	if score < 0 then score = 0; base = 0 end
	return score, level, loc, base
end

---------------------------------------------------------------- inspection cache (other players)
-- a unit's GUID, or nil when WoW Forever keeps it hidden
local function SafeGUID(u)
	local g = UnitGUID(u)
	if type(issecretvalue) == "function" and issecretvalue(g) then return nil end
	return g
end
local cache = {}       -- guid -> { t = time, links = { [slot] = link }, talents = { {name, points}, ... }, class = token }
local queue, inspecting = nil, nil
local function LinksFor(guid)
	if guid == UnitGUID("player") then
		local l = {}
		for s = 1, 19 do l[s] = GetInventoryItemLink("player", s) end
		return l, select(2, UnitClass("player"))
	end
	local c = cache[guid]
	if c then return c.links, c.class end
end
-- GearScore and average item level for a unit or GUID, or 0, 0 while unknown
local function Score(unitOrGuid)
	local guid = unitOrGuid
	if type(unitOrGuid) == "string" and not unitOrGuid:find("^Player%-") then guid = SafeGUID(unitOrGuid) end
	if not guid then return 0, 0 end
	local links, class = LinksFor(guid)
	if not links then return 0, 0 end
	local total, count, levels, ready = 0, 0, 0, true
	local titan = 1
	local mh, oh = links[16], links[17]
	if mh and oh then local loc = select(9, GetItemInfo(mh)); if loc == "INVTYPE_2HWEAPON" then titan = 0.5 end end
	for s = 1, 18 do
		local link = links[s]
		if link and s ~= 4 then
			if not GetItemInfo(link) then
				ready = false
				local id = tonumber(link:match("item:(%d+)"))
				if id and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
			else
				local sc, lv = ItemScore(link)
				if class == "HUNTER" then
					if s == 16 or s == 17 then sc = sc * 0.3164 elseif s == 18 then sc = sc * 5.3224 end
				end
				if s == 16 or s == 17 then sc = sc * titan end
				total = total + sc; count = count + 1; levels = levels + lv
			end
		end
	end
	if ready and total > 0 and count > 0 then return math.floor(total), math.floor(levels / count), true end
	-- everything read, but low-level or plain gear adds up to nothing: that's an answer too, not "still reading"
	if ready and count > 0 then return 0, math.floor(levels / count), true end
	return 0, 0, false
end

-- TacoTip's API, for add-ons that read GearScore from it
if not _G.TT_GS then
	_G.TT_GS = {
		GetScore = function(_, u) return Score(u) end,
		GetQuality = function(_, s) return Quality(s) end,
		GetItemScore = function(_, link)
			local sc, lv, loc, base = ItemScore(link)
			local r, g, b = Quality(base and base > 0 and base * 11.25 or 1)
			return sc, lv, r, g, b, loc
		end,
	}
end
PT.Score, PT.Quality, PT.ItemScore = Score, Quality, ItemScore
PT.cache, PT.SafeGUID, PT.Known, PT.Secret = cache, SafeGUID, Known, Secret

local function InspectTalents()
	local out = {}
	for t = 1, 3 do
		local ok, a, b, c, d, e = pcall(GetTalentTabInfo, t, true)
		if not ok or not a then return nil end
		local name, pts
		if type(a) == "number" then name, pts = b, e else name, pts = a, c end
		if type(pts) ~= "number" then return nil end
		out[t] = { name, pts }
	end
	return out
end
local function TryInspect(unit)
	if not db or not (db.gearscore or db.ilvl or db.talents) then return end
	if not UnitIsPlayer(unit) or Known(UnitIsUnit(unit, "player")) ~= false then return end   -- (hidden: skip)
	if InCombatLockdown() or (InspectFrame and InspectFrame:IsShown()) then return end
	if not CanInspect(unit) or not CheckInteractDistance(unit, 1) then return end
	local guid = SafeGUID(unit)
	if not guid then return end
	local c = cache[guid]
	if c and time() - c.t < 120 and c.links and next(c.links) and (c.grid or c.gridTried or not db.talentPeek) then return end   -- fresh and complete: no need
	if inspecting and GetTime() - inspecting.at < 2 then return end
	inspecting = { guid = guid, unit = unit, at = GetTime() }
	-- reading someone's gear for the tooltip is a quiet background request: if they've just stepped out of range,
	-- don't flash "Out of range." on your screen for something you didn't click
	local quiet = UIErrorsFrame and UIErrorsFrame:IsEventRegistered("UI_ERROR_MESSAGE")
	if quiet then UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE") end
	NotifyInspect(unit)
	if quiet then C_Timer.After(0.3, function() UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE") end) end
end
PT.TryInspect = TryInspect

---------------------------------------------------------------- player tooltips
local function Hex(r, g, b) return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255) end
local function ClassHex(unit)
	local _, cls = UnitClass(unit)
	if type(issecretvalue) == "function" and issecretvalue(cls) then return "|cffffffff" end
	local c = cls and RAID_CLASS_COLORS[cls]
	return c and Hex(c.r, c.g, c.b) or "|cffffffff"
end
local function UnitTip(tt)
	if not db then return end
	local _, unit = tt:GetUnit()
	if not unit then local f = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus()); unit = f and f.unit end
	-- Shift held: the talent trees beside the tooltip (Talents.lua)
	if PT.TalentPeek then PT.TalentPeek(tt, (unit and not (type(issecretvalue) == "function" and issecretvalue(unit))) and unit or nil) end
	-- (WoW Forever can hand over a hidden "secret" unit, which add-ons may not look up: leave that tooltip alone)
	if not unit or (type(issecretvalue) == "function" and issecretvalue(unit)) or not UnitExists(unit) then return end
	if not db.inCombat and InCombatLockdown() then return end
	local isPlayer = UnitIsPlayer(unit)
	if isPlayer then
		-- name line: class colour and title
		local left1 = _G[tt:GetName() .. "TextLeft1"]
		if left1 then
			local name = (db.title and UnitPVPName and UnitPVPName(unit)) or UnitName(unit)
			if db.classColor then left1:SetText(ClassHex(unit) .. (name or "") .. "|r") else left1:SetText(name or "") end
		end
		-- guild and rank: Blizzard puts the guild on line 2; recolour it and add the rank
		local gname, grank = GetGuildInfo(unit)
		if gname and db.guild then
			local left2 = _G[tt:GetName() .. "TextLeft2"]
			if left2 and left2:GetText() and left2:GetText():find(gname, 1, true) then
				local mine = IsInGuild() and GetGuildInfo("player") == gname
				left2:SetText((mine and "|cff40ff40" or "|cff60c0ff") .. "<" .. gname .. ">|r |cffa0a0a0" .. (grank or "") .. "|r")
			end
		end
		local guid = SafeGUID(unit)
		local c = guid and cache[guid]
		-- talents
		if db.talents then
			local tal = (Known(UnitIsUnit(unit, "player")) and (function()
				local o = {}
				for t = 1, 3 do local ok, a, b, cc, d, e = pcall(GetTalentTabInfo, t); if ok and a then if type(a) == "number" then o[t] = { b, e } else o[t] = { a, cc } end end end
				return #o == 3 and o or nil end)()) or (c and c.talents)
			if tal then
				local best = 1
				for t = 2, 3 do if (tal[t][2] or 0) > (tal[best][2] or 0) then best = t end end
				tt:AddDoubleLine("Talents:", ("|cffffffff%s|r (%d/%d/%d)"):format(tal[best][1] or "?", tal[1][2] or 0, tal[2][2] or 0, tal[3][2] or 0), 1, 0.82, 0, 1, 1, 1)
			elseif c and c.grid and c.grid.summary then
				tt:AddDoubleLine("Talents:", "|cffffffff" .. c.grid.summary .. "|r", 1, 0.82, 0, 1, 1, 1)
			end
		end
		-- GearScore and item level
		if db.gearscore or db.ilvl then
			local gs, il, known = Score(guid)
			if known then
				local r, g, b = Quality(gs)
				if db.gearscore and db.ilvl then tt:AddDoubleLine("GearScore: " .. Hex(r, g, b) .. gs .. "|r", "iLvl: |cffffffff" .. il .. "|r", 1, 0.82, 0, 1, 0.82, 0)
				elseif db.gearscore then tt:AddLine("GearScore: " .. Hex(r, g, b) .. gs .. "|r", 1, 0.82, 0)
				else tt:AddLine("Item level: |cffffffff" .. il .. "|r", 1, 0.82, 0) end
			elseif not Known(UnitIsUnit(unit, "player")) then
				-- (the modern client won't let add-ons check distance: CanInspect alone there)
				if (Secret or not CheckInteractDistance or CheckInteractDistance(unit, 1)) and CanInspect(unit) then tt:AddLine("GearScore: |cff888888reading...|r", 1, 0.82, 0) end
				TryInspect(unit)
			end
		end
	end
	-- what they're targeting
	if db.target then
		local tu = unit .. "target"
		if UnitExists(tu) then
			local txt
			if Known(UnitIsUnit(tu, "player")) then txt = "|cffff4040> YOU <|r"
			elseif UnitIsPlayer(tu) then txt = ClassHex(tu) .. UnitName(tu) .. "|r"
			else txt = "|cffffffff" .. (UnitName(tu) or "?") .. "|r" end
			tt:AddDoubleLine("Target:", txt, 1, 0.82, 0)
		end
	end
	tt:Show()
end

---------------------------------------------------------------- item tooltips
-- recipe tooltips report their item twice (the recipe, then again with the item it makes): add our lines once
local tipDone = setmetatable({}, { __mode = "k" })
local function ClearDone(tt) tipDone[tt] = nil end
local cleared = {}
local function ItemTip(tt)
	if not db then return end
	local _, link
	if tt.GetItem then _, link = tt:GetItem()
	elseif TooltipUtil and TooltipUtil.GetDisplayedItem then _, link = TooltipUtil.GetDisplayedItem(tt) end
	if not link then return end
	if not cleared[tt] and tt.HookScript then cleared[tt] = true; tt:HookScript("OnTooltipCleared", ClearDone) end
	if tipDone[tt] == link then return end
	tipDone[tt] = link
	local _, _, rarity, level, _, _, _, _, loc = GetItemInfo(link)
	local isGear = level and loc and loc ~= "" and SLOT_MOD[loc]
	if isGear and db.itemLevel then tt:AddLine("Item Level " .. level, 1, 0.82, 0) end
	if isGear and db.itemScore then
		local sc, _, _, base = ItemScore(link)
		if sc > 0 then
			local r, g, b = Quality((base or 0) * 11.25)
			tt:AddLine("GearScore " .. sc, r, g, b)
		end
	end
	if PT.ItemExtras then PT.ItemExtras(tt, link) end
	tt:Show()
end

---------------------------------------------------------------- hooks
local function HookTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) if tt == GameTooltip then UnitTip(tt) end end)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt) if tt == GameTooltip or tt == ItemRefTooltip or tt == ShoppingTooltip1 or tt == ShoppingTooltip2 then ItemTip(tt) end end)
	else
		GameTooltip:HookScript("OnTooltipSetUnit", UnitTip)
		for _, t in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do if t then t:HookScript("OnTooltipSetItem", ItemTip) end end
	end
	-- where the tooltip appears
	hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tt, parent)
		if not db or tt ~= GameTooltip then return end
		if db.anchor == "cursor" then
			tt:SetOwner(parent, "ANCHOR_CURSOR")
		elseif db.anchor == "fixed" then
			tt:ClearAllPoints()
			tt:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", db.ax, db.ay)
		end
	end)
end

---------------------------------------------------------------- character / inspect window
local charText, inspText
local function CharLine(parent, existing)
	if existing then return existing end
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetJustifyH("LEFT")
	return fs
end
function PT.UpdateChar()
	if not db or not CharacterModelFrame and not PaperDollFrame then return end
	local parent = PaperDollFrame or CharacterFrame
	charText = CharLine(parent, charText)
	charText:ClearAllPoints()
	charText:SetPoint("BOTTOMLEFT", CharacterModelFrame or parent, "BOTTOMLEFT", 6, 22)
	if not db.charFrame then charText:Hide(); return end
	local gs, il = Score("player")
	if gs > 0 then
		local r, g, b = Quality(gs)
		charText:SetText("GearScore " .. Hex(r, g, b) .. gs .. "|r\n|cffffd100iLvl|r |cffffffff" .. il .. "|r")
	else charText:SetText("") end
	charText:Show()
end
local function UpdateInspect(guid)
	if not (db and db.charFrame and InspectPaperDollFrame) then return end
	inspText = CharLine(InspectPaperDollFrame, inspText)
	inspText:ClearAllPoints()
	inspText:SetPoint("BOTTOMLEFT", InspectModelFrame or InspectPaperDollFrame, "BOTTOMLEFT", 6, 22)
	local gs, il = Score(guid)
	if gs > 0 then local r, g, b = Quality(gs); inspText:SetText("GearScore " .. Hex(r, g, b) .. gs .. "|r\n|cffffd100iLvl|r |cffffffff" .. il .. "|r") else inspText:SetText("") end
end

---------------------------------------------------------------- options
local opt
local function Check(x, y, label, key)
	local c = CreateFrame("CheckButton", nil, opt, "UICheckButtonTemplate"); c:SetSize(22, 22); c:SetPoint("TOPLEFT", x, y)
	local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("LEFT", c, "RIGHT", 2, 0); t:SetText(label)
	c:SetScript("OnShow", function(self) self:SetChecked(db[key] and true or false) end)
	c:SetScript("OnClick", function(self) db[key] = self:GetChecked() and true or false; PT.UpdateChar() end)
end
local mover
local function Mover(on)
	if not mover then
		mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		mover:SetSize(220, 80); mover:SetFrameStrata("DIALOG"); mover:SetMovable(true); mover:EnableMouse(true); mover:RegisterForDrag("LeftButton")
		mover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); mover:SetBackdropColor(0.2, 0.6, 1, 0.4)
		local t = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("CENTER"); t:SetText("Tooltip spot - drag me")
		mover:SetScript("OnDragStart", mover.StartMoving)
		mover:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			db.ax = math.floor(self:GetRight() - UIParent:GetRight() + 0.5); db.ay = math.floor(self:GetBottom() + 0.5)
		end)
	end
	mover:ClearAllPoints(); mover:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", db.ax, db.ay)
	mover:SetShown(on)
end
function PT.ToggleOptions()
	if not opt then
		opt = CreateFrame("Frame", "PintsTipsOptions", UIParent, "BasicFrameTemplateWithInset")
		opt:SetSize(320, 466); opt:SetPoint("CENTER"); opt:SetFrameStrata("DIALOG")
		opt:SetMovable(true); opt:EnableMouse(true); opt:RegisterForDrag("LeftButton")
		opt:SetScript("OnDragStart", opt.StartMoving); opt:SetScript("OnDragStop", opt.StopMovingOrSizing)
		tinsert(UISpecialFrames, "PintsTipsOptions")
		local title = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); title:SetPoint("TOP", 0, -5); title:SetText("|cffd4a017Pint's|r Tips")
		local function head(y, s) local h = opt:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h:SetPoint("TOPLEFT", 16, y); h:SetText(s) end
		head(-32, "Players")
		Check(16, -50, "Class-coloured names", "classColor"); Check(170, -50, "Titles", "title")
		Check(16, -72, "Guild and rank", "guild"); Check(170, -72, "Talents", "talents")
		Check(16, -94, "GearScore", "gearscore"); Check(170, -94, "Average item level", "ilvl")
		Check(16, -116, "What they're targeting", "target"); Check(170, -116, "Shift: talent trees", "talentPeek")
		Check(16, -138, "Show in combat", "inCombat")
		head(-170, "Items")
		Check(16, -188, "Item level", "itemLevel"); Check(170, -188, "Item GearScore", "itemScore")
		Check(16, -210, "What it's used for", "usedFor"); Check(170, -210, "Count on each character", "counts")
		Check(16, -232, "Recipes: who knows / can learn", "recipeAlts"); Check(170, -232, "Item ID", "itemID")
		head(-286, "Character window")
		Check(16, -304, "GearScore and item level", "charFrame")
		head(-336, "Where tooltips appear")
		local modes = { { "default", "Blizzard's corner" }, { "cursor", "At the cursor" }, { "fixed", "A spot I choose" } }
		local b = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate"); b:SetSize(150, 22); b:SetPoint("TOPLEFT", 16, -356)
		local mv = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate"); mv:SetSize(110, 22); mv:SetPoint("LEFT", b, "RIGHT", 6, 0); mv:SetText("Move spot")
		local function show() for _, m in ipairs(modes) do if m[1] == db.anchor then b:SetText(m[2]) end end; mv:SetShown(db.anchor == "fixed") end
		b:SetScript("OnClick", function()
			local i = 1; for k, m in ipairs(modes) do if m[1] == db.anchor then i = k end end
			db.anchor = modes[i % #modes + 1][1]; show(); if db.anchor ~= "fixed" then Mover(false) end
		end)
		mv:SetScript("OnClick", function() Mover(not (mover and mover:IsShown())) end)
		opt:HookScript("OnShow", show)
		opt:HookScript("OnHide", function() Mover(false) end)
		opt.taco = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate"); opt.taco:SetSize(200, 22); opt.taco:SetPoint("TOPLEFT", 16, -396)
		opt.taco:SetText("Switch TacoTip off"); opt.taco:SetScript("OnClick", function() PT.TacoOff() end)
		opt:HookScript("OnShow", function() opt.taco:SetShown(PT.TacoLoaded()) end)
		opt:Hide()
	end
	opt:SetShown(not opt:IsShown())
end
local function Loaded(a) if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(a) end return IsAddOnLoaded and IsAddOnLoaded(a) end
function PT.TacoLoaded() return Loaded("TacoTip") end
function PT.TacoOff()
	local off = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
	pcall(off, "TacoTip")
	Print("TacoTip switched off - /reload to finish.")
end

SLASH_PINTSTIPS1 = "/tips"
SLASH_PINTSTIPS2 = "/pintstips"
SlashCmdList.PINTSTIPS = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "talents" then if PT.TalentDump then PT.TalentDump() end
	elseif msg == "off-tacotip" then PT.TacoOff()
	elseif msg == "minimap" then if PT.ToggleMinimap then PT.ToggleMinimap() end
	else PT.ToggleOptions() end
end

---------------------------------------------------------------- minimap button
do
	local NAME, ICON, ANGLE = "PintsTips", "Interface\\AddOns\\PintsTips\\Icon", 160
	local btn
	local function Tip(tt) tt:AddLine("Pint's Tips"); tt:AddLine("Click: options", 1, 1, 1); tt:AddLine("/tips minimap to hide", 0.5, 0.5, 0.5) end
	function PT.BuildMinimap()
		local store = db.minimap
		local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
		local Icon = LibStub and LibStub("LibDBIcon-1.0", true)
		if LDB and Icon then
			local obj = LDB:NewDataObject(NAME, { type = "launcher", text = "Pint's Tips", icon = ICON, OnClick = function() PT.ToggleOptions() end, OnTooltipShow = Tip })
			Icon:Register(NAME, obj, store); btn = { lib = Icon }; return
		end
		local b = CreateFrame("Button", NAME .. "MinimapButton", Minimap)
		b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
		b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
		local ic = b:CreateTexture(nil, "BACKGROUND"); ic:SetTexture(ICON); ic:SetSize(20, 20); ic:SetPoint("CENTER", 0, 1); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local border = b:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(53, 53); border:SetPoint("TOPLEFT")
		local function Place() local a = math.rad(store.angle or ANGLE); b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a)) end
		Place()
		b:RegisterForDrag("LeftButton")
		b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter(); local px, py = GetCursorPosition(); local s = Minimap:GetEffectiveScale()
			store.angle = math.deg(math.atan2(py / s - my, px / s - mx)); Place() end) end)
		b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
		b:SetScript("OnClick", function() PT.ToggleOptions() end)
		b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); Tip(GameTooltip); GameTooltip:Show() end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetShown(not store.hide); btn = b
	end
	function PT.ToggleMinimap()
		local store = db.minimap; store.hide = not store.hide
		if btn and btn.lib then if store.hide then btn.lib:Hide(NAME) else btn.lib:Show(NAME) end elseif btn then btn:SetShown(not store.hide) end
	end
end

-- (WoW Forever can hide a unit's GUID: then it counts as not the same unit)
local function SameGUID(u, g)
	local x = UnitGUID(u)
	if type(issecretvalue) == "function" and (issecretvalue(x) or issecretvalue(g)) then return false end
	return x ~= nil and x == g
end
---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "INSPECT_READY", "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED", "UNIT_INVENTORY_CHANGED" }) do ev:RegisterEvent(e) end
local charPending, tipPending
ev:SetScript("OnEvent", function(_, e, a1)
	if e == "ADDON_LOADED" and a1 == ADDON then
		PintsTipsDB = PintsTipsDB or {}
		db = PintsTipsDB
		for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = (type(v) == "table") and {} or v end end
		PT.db = db
	elseif e == "PLAYER_LOGIN" then
		HookTooltips()
		PT.BuildMinimap()
		if PaperDollFrame then PaperDollFrame:HookScript("OnShow", PT.UpdateChar) end
		if PT.TacoLoaded() then Print("TacoTip is on too - /tips off-tacotip to switch it off, then /reload.") end
	elseif e == "INSPECT_READY" then
		if type(issecretvalue) == "function" and issecretvalue(a1) then return end
		local guid = a1
		local unit = inspecting and inspecting.guid == guid and inspecting.unit
		if not unit then
			for _, u in ipairs({ "mouseover", "target", "focus" }) do if SameGUID(u, guid) then unit = u end end
		end
		if unit and SameGUID(unit, guid) then
			local links = {}
			for s = 1, 19 do links[s] = GetInventoryItemLink(unit, s) end
			cache[guid] = { t = time(), links = links, talents = InspectTalents(), grid = PT.ReadGrid and PT.ReadGrid(true, unit), class = select(2, UnitClass(unit)) }
			-- the gear links sometimes come in a moment after INSPECT_READY: read them again shortly
			local u = unit
			for _, delay in ipairs({ 0.5, 1.5 }) do
				C_Timer.After(delay, function()
					local cc = cache[guid]
					if not cc or not SameGUID(u, guid) then return end
					local more = false
					for s = 1, 19 do local l = GetInventoryItemLink(u, s); if l and l ~= cc.links[s] then cc.links[s] = l; more = true end end
					-- talents can come in late too
					if not cc.talents then cc.talents = InspectTalents(); more = more or cc.talents ~= nil end
					if not cc.grid and PT.ReadGrid then cc.grid = PT.ReadGrid(true, u); more = more or cc.grid ~= nil end
					if delay == 1.5 then cc.gridTried = true; more = true; if not cc.grid and PT.TalentFailed then PT.TalentFailed(u) end end
					if more and GameTooltip:IsShown() and SameGUID("mouseover", guid) then GameTooltip:SetUnit("mouseover") end
				end)
			end
			if InspectFrame and InspectFrame:IsShown() then UpdateInspect(guid) end
			if PT.dumpGUID == guid and PT.TalentDumpNow then PT.dumpGUID = nil; local du = unit; C_Timer.After(0.5, function() PT.TalentDumpNow(du) end) end
			if GameTooltip:IsShown() and SameGUID("mouseover", guid) then GameTooltip:SetUnit("mouseover") end
		end
		if inspecting and inspecting.guid == guid then
			inspecting = nil
			-- keep the inspect data a couple of seconds so the late gear links can still be read
			C_Timer.After(2, function()
				if not inspecting and not (InspectFrame and InspectFrame:IsShown()) and ClearInspectPlayer then ClearInspectPlayer() end
			end)
		end
	elseif e == "PLAYER_EQUIPMENT_CHANGED" or e == "GET_ITEM_INFO_RECEIVED" or (e == "UNIT_INVENTORY_CHANGED" and a1 == "player") then
		-- item data arriving can finish a "GearScore: reading..." line on the tooltip you're looking at
		if e == "GET_ITEM_INFO_RECEIVED" and not tipPending and GameTooltip:IsShown() and UnitIsPlayer("mouseover") and cache[SafeGUID("mouseover") or ""] then
			tipPending = true
			C_Timer.After(0.2, function() tipPending = nil; if GameTooltip:IsShown() and UnitExists("mouseover") then GameTooltip:SetUnit("mouseover") end end)
		end
		if not charPending then charPending = true; C_Timer.After(0.5, function() charPending = nil; if PaperDollFrame and PaperDollFrame:IsShown() then PT.UpdateChar() end end) end
	end
end)
