-- Pint's Tips: your history with units, and your own notes.
--   Enemies: how many of that creature you've killed (this character).   Players: your duel record and time grouped.
--   Notes (account-wide) on players, creatures, items and quests, with a behaviour and a skill rating for players;
--   a preview shows in their tooltips.   /tips note  (your target, or what's under the mouse; or a name / item link)
--   /tips notes  opens the list.   "Added in WoW Forever" on items and creatures new there.
local PT = _G.PintsTips
if not PT then return end
local SECRET = type(issecretvalue) == "function"
local function S(v) return SECRET and issecretvalue(v) end
local function Print(m) print("|cffd4a017Pint's Tips:|r " .. m) end

local function DB() return PT.db end
local function CK() return (GetRealmName() or "") .. "." .. ((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "") end
local function Hist()
	local db = DB(); if not db then return nil end
	db.hist = db.hist or {}
	local ck = CK()
	db.hist[ck] = db.hist[ck] or { kills = {}, duels = {}, grouped = {} }
	return db.hist[ck]
end
local function Notes() local db = DB(); if not db then return {} end; db.notes = db.notes or {}; return db.notes end
PT.Notes = Notes

---------------------------------------------------------------- kills
-- Classic Era: the combat log's "party kill" (yours or your group's, grey mobs too). WoW Forever keeps the combat log
-- from add-ons, so there the "X dies, you gain N experience" line counts it (mobs that give experience).
local function Kill(name)
	if type(name) ~= "string" or S(name) or name == "" then return end
	local h = Hist(); if not h then return end
	h.kills[name] = (h.kills[name] or 0) + 1
	if PT.OnKill then PT.OnKill(name, h.kills[name]) end
end
local MAGIC = "([%^%$%(%)%%%.%[%]%*%+%-%?])"
local function Pattern(fmt)
	if type(fmt) ~= "string" then return nil end
	local p = fmt:gsub("%%s", "\001"):gsub("%%d", "\002"):gsub(MAGIC, "%%%1"):gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
	return "^" .. p
end
local XP_KILL = Pattern(COMBATLOG_XPGAIN_FIRSTPERSON)                -- "%s dies, you gain %d experience."
local XP_KILL_GROUP = Pattern(COMBATLOG_XPGAIN_FIRSTPERSON_GROUP)    -- (with group bonus)
local XP_KILL_RAID = Pattern(COMBATLOG_XPGAIN_FIRSTPERSON_RAID)

---------------------------------------------------------------- duels
local function DuelPattern(fmt)
	if type(fmt) ~= "string" then return nil end
	local order = {}
	local p = fmt:gsub("%%(%d)%$s", function(n) order[#order + 1] = tonumber(n); return "\001" end)
	p = p:gsub("%%s", "\001"):gsub(MAGIC, "%%%1"):gsub("\001", "(.+)")
	if #order == 0 then order = { 1, 2 } end
	return "^" .. p .. "$", order
end
local KO, KO_ORDER = DuelPattern(DUEL_WINNER_KNOCKOUT)      -- "%1$s has defeated %2$s in a duel"
local FLED, FLED_ORDER = DuelPattern(DUEL_WINNER_RETREAT)   -- "%2$s has fled from %1$s in a duel"
local function Duel(msg)
	if type(msg) ~= "string" or S(msg) then return end
	local me = UnitName("player")
	for _, d in ipairs({ { KO, KO_ORDER }, { FLED, FLED_ORDER } }) do
		if d[1] then
			local a, b = msg:match(d[1])
			if a then
				local cap = { a, b }
				local winner, loser = a, b
				if d[2][1] == 2 then winner, loser = cap[2], cap[1] end   -- (the format names them the other way round)
				local h = Hist(); if not h then return end
				if winner == me and loser then
					local r = h.duels[loser] or { 0, 0 }; r[1] = r[1] + 1; h.duels[loser] = r
				elseif loser == me and winner then
					local r = h.duels[winner] or { 0, 0 }; r[2] = r[2] + 1; h.duels[winner] = r
				end
				return
			end
		end
	end
end

---------------------------------------------------------------- time grouped (counted every 30 seconds)
local function GroupTick()
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	if n == 0 then return end
	local h = Hist(); if not h then return end
	local raid = IsInRaid and IsInRaid()
	for i = 1, (raid and n or n - 1) do
		local u = raid and ("raid" .. i) or ("party" .. i)
		if UnitExists(u) and not UnitIsUnit(u, "player") then
			local name, realm = UnitName(u)
			if type(name) == "string" and not S(name) then
				local key = (realm and realm ~= "" and not S(realm)) and (name .. "-" .. realm) or name
				h.grouped[key] = (h.grouped[key] or 0) + 30
			end
		end
	end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_SYSTEM", "PLAYER_LOGIN" }) do pcall(ev.RegisterEvent, ev, e) end
if not SECRET then pcall(ev.RegisterEvent, ev, "COMBAT_LOG_EVENT_UNFILTERED") end
ev:SetScript("OnEvent", function(_, e, msg)
	if e == "COMBAT_LOG_EVENT_UNFILTERED" then
		local _, sub, _, src, _, _, _, _, dname = CombatLogGetCurrentEventInfo()
		if sub == "PARTY_KILL" and src == UnitGUID("player") then Kill(dname) end
	elseif e == "CHAT_MSG_COMBAT_XP_GAIN" then
		if not SECRET or type(msg) ~= "string" or S(msg) then return end
		local name = (XP_KILL and msg:match(XP_KILL)) or (XP_KILL_GROUP and msg:match(XP_KILL_GROUP)) or (XP_KILL_RAID and msg:match(XP_KILL_RAID))
		if name then Kill(name) end
	elseif e == "CHAT_MSG_SYSTEM" then
		Duel(msg)
	elseif e == "PLAYER_LOGIN" then
		C_Timer.NewTicker(30, GroupTick)
	end
end)

---------------------------------------------------------------- "Added in WoW Forever"
-- Classic's items and creatures all have low numbers; the ones the game added for Forever have very high ones
local function NewItem(id) return SECRET and id and id > 190000 end
local function NewCreature(guid)
	if not SECRET or type(guid) ~= "string" or S(guid) then return false end
	local kind, _, _, _, _, npc = strsplit("-", guid)
	npc = tonumber(npc)
	return (kind == "Creature" or kind == "Vehicle") and npc and npc > 100000 or false
end

---------------------------------------------------------------- notes
-- key: "player:Name", "npc:Name", "item:12345", "quest:123", "general:Title"
-- note = { text = "...", b = behaviour (-2..2), s = skill (-2..2), t = time saved, label = shown name }
local RATE = { [-2] = "|cffff2020--|r", [-1] = "|cffff8040-|r", [0] = "|cff909090n/a|r", [1] = "|cff80ff40+|r", [2] = "|cff20ff20++|r" }
local RATE_NAME = { [-2] = "Very bad", [-1] = "Bad", [0] = "N/A", [1] = "Good", [2] = "Very good" }
local function Preview(t, n) t = (t or ""):gsub("\n", " "); if #t > (n or 60) then t = t:sub(1, (n or 60) - 3) .. "..." end; return t end
local function AddNoteLines(tt, note)
	if not note then return end
	if (note.b and note.b ~= 0) or (note.s and note.s ~= 0) then
		tt:AddLine("|cffd4a017Your rating:|r behaviour " .. RATE[note.b or 0] .. "   skill " .. RATE[note.s or 0], 1, 1, 1)
	end
	if note.text and note.text ~= "" then tt:AddLine("|cffd4a017Note:|r " .. Preview(note.text), 0.9, 0.9, 0.9, true) end
end

-- called by the unit tooltip (PintsTips.lua)
function PT.UnitExtras(tt, unit, isPlayer)
	local db = DB(); if not db then return end
	local name, realm = UnitName(unit)
	if type(name) ~= "string" or S(name) then return end
	local h = Hist()
	if isPlayer then
		if db.unitHistory ~= false and h and not UnitIsUnit(unit, "player") then
			local key = (realm and realm ~= "" and not S(realm)) and (name .. "-" .. realm) or name
			local d = h.duels[key] or h.duels[name]
			local g = h.grouped[key] or h.grouped[name]
			if d then tt:AddLine(("|cffd4a017Duels:|r |cff40ff40%d won|r, |cffff5050%d lost|r"):format(d[1], d[2]), 1, 1, 1) end
			if g and g >= 60 then tt:AddLine("|cffd4a017Grouped with you:|r " .. (SecondsToTime and SecondsToTime(g, true) or (math.floor(g / 60) .. " min")), 1, 1, 1) end
		end
		if db.notesTips ~= false then AddNoteLines(tt, Notes()["player:" .. name]) end
	else
		if db.unitHistory ~= false and h and UnitCanAttack("player", unit) then
			local k = h.kills[name]
			if k then tt:AddLine("|cffd4a017Killed:|r " .. k, 1, 1, 1) end
		end
		if db.notesTips ~= false then AddNoteLines(tt, Notes()["npc:" .. name]) end
		if db.foreverTag ~= false and NewCreature(UnitGUID(unit)) then tt:AddLine("Added in WoW Forever", 0.4, 0.8, 1) end
	end
end

-- item tooltips: chained after the "used for" lines (ItemUse.lua)
local baseItem = PT.ItemExtras
function PT.ItemExtras(tt, link)
	if baseItem then baseItem(tt, link) end
	local db = DB(); if not db then return end
	local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
	if not id then return end
	if db.notesTips ~= false then AddNoteLines(tt, Notes()["item:" .. id]) end
	if db.foreverTag ~= false and NewItem(id) then tt:AddLine("Added in WoW Forever", 0.4, 0.8, 1) end
end

---------------------------------------------------------------- the note editor
local ed
local function Editor()
	if ed then return ed end
	ed = CreateFrame("Frame", "PintsTipsNoteEditor", UIParent, "BasicFrameTemplateWithInset")
	ed:SetSize(340, 300); ed:SetPoint("CENTER", 0, 80); ed:SetFrameStrata("DIALOG")
	ed:SetMovable(true); ed:EnableMouse(true); ed:RegisterForDrag("LeftButton")
	ed:SetScript("OnDragStart", ed.StartMoving); ed:SetScript("OnDragStop", ed.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PintsTipsNoteEditor")
	ed.title = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); ed.title:SetPoint("TOP", 0, -5)
	ed.what = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal"); ed.what:SetPoint("TOPLEFT", 14, -32); ed.what:SetWidth(310); ed.what:SetJustifyH("LEFT")
	local box = CreateFrame("Frame", nil, ed, "BackdropTemplate")
	box:SetPoint("TOPLEFT", 12, -52); box:SetPoint("TOPRIGHT", -12, -52); box:SetHeight(120)
	box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	box:SetBackdropColor(0, 0, 0, 0.5); box:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
	local sf = CreateFrame("ScrollFrame", "PintsTipsNoteScroll", box, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 6, -6); sf:SetPoint("BOTTOMRIGHT", -26, 6)
	local eb = CreateFrame("EditBox", nil, sf)
	eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject("ChatFontNormal"); eb:SetWidth(270); eb:SetMaxLetters(1000)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	sf:SetScrollChild(eb)
	box:EnableMouse(true); box:SetScript("OnMouseDown", function() eb:SetFocus() end)
	ed.eb = eb
	-- ratings (players only)
	local function RateRow(y, label, field)
		local l = ed:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); l:SetPoint("TOPLEFT", 14, y); l:SetText(label)
		local btns = {}
		for i, v in ipairs({ -2, -1, 0, 1, 2 }) do
			local b = CreateFrame("Button", nil, ed, "UIPanelButtonTemplate"); b:SetSize(44, 20); b:SetPoint("TOPLEFT", 90 + (i - 1) * 46, y + 4)
			b:SetText(RATE[v]); b.v = v
			b:SetScript("OnClick", function() ed[field] = v; ed.Paint() end)
			b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(RATE_NAME[v]); GameTooltip:Show() end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			btns[#btns + 1] = b
		end
		return l, btns
	end
	ed.bl, ed.bb = RateRow(-184, "Behaviour", "b")
	ed.sl, ed.sb = RateRow(-210, "Skill", "s")
	function ed.Paint()
		local player = ed.key and ed.key:find("^player:")
		for _, set in ipairs({ { ed.bl, ed.bb, "b" }, { ed.sl, ed.sb, "s" } }) do
			set[1]:SetShown(player)
			for _, b in ipairs(set[2]) do
				b:SetShown(player)
				local on = (ed[set[3]] or 0) == b.v
				b:SetAlpha(on and 1 or 0.5)
				if b.LockHighlight then if on then b:LockHighlight() else b:UnlockHighlight() end end
			end
		end
	end
	local save = CreateFrame("Button", nil, ed, "UIPanelButtonTemplate"); save:SetSize(90, 22); save:SetPoint("BOTTOMLEFT", 12, 12); save:SetText("Save")
	save:SetScript("OnClick", function()
		local text = ed.eb:GetText() or ""
		if text == "" and (ed.b or 0) == 0 and (ed.s or 0) == 0 then Notes()[ed.key] = nil
		else Notes()[ed.key] = { text = text, b = ed.b or 0, s = ed.s or 0, t = time(), label = ed.label } end
		ed:Hide()
		if PT.RefreshNoteList then PT.RefreshNoteList() end
	end)
	local del = CreateFrame("Button", nil, ed, "UIPanelButtonTemplate"); del:SetSize(90, 22); del:SetPoint("LEFT", save, "RIGHT", 6, 0); del:SetText("Delete")
	del:SetScript("OnClick", function() Notes()[ed.key] = nil; ed:Hide(); if PT.RefreshNoteList then PT.RefreshNoteList() end end)
	local cancel = CreateFrame("Button", nil, ed, "UIPanelButtonTemplate"); cancel:SetSize(90, 22); cancel:SetPoint("BOTTOMRIGHT", -12, 12); cancel:SetText("Cancel")
	cancel:SetScript("OnClick", function() ed:Hide() end)
	ed:Hide()
	return ed
end
local KIND = { player = "Player", npc = "Creature", item = "Item", quest = "Quest", general = "Note" }
function PT.EditNote(key, label)
	local e = Editor()
	local n = Notes()[key]
	e.key, e.label = key, label or (n and n.label) or key:gsub("^%a+:", "")
	e.b, e.s = n and n.b or 0, n and n.s or 0
	e.title:SetText("|cffd4a017Pint's|r note")
	e.what:SetText((KIND[key:match("^(%a+):")] or "Note") .. ":  |cffffffff" .. e.label .. "|r")
	e.eb:SetText(n and n.text or "")
	e.Paint()
	e:Show(); e.eb:SetFocus()
end

-- /tips note [name | item link | quest]
function PT.NoteCmd(arg)
	arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local id, iname = arg:match("|Hitem:(%d+)[^|]*|h%[(.-)%]|h")
	if id then return PT.EditNote("item:" .. id, iname) end
	if arg:lower() == "quest" then
		local qid, title
		if C_QuestLog and C_QuestLog.GetSelectedQuest then qid = C_QuestLog.GetSelectedQuest() end
		if GetQuestLogSelection and GetQuestLogTitle then local i = GetQuestLogSelection(); if i and i > 0 then local t, _, _, _, _, _, _, q = GetQuestLogTitle(i); title, qid = t, qid or q end end
		if qid and qid > 0 then
			title = title or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid)) or ("Quest " .. qid)
			return PT.EditNote("quest:" .. qid, title)
		end
		Print("pick a quest in your quest log first, then /tips note quest.")
		return
	end
	if arg ~= "" then return PT.EditNote("general:" .. arg, arg) end
	for _, u in ipairs({ "target", "mouseover" }) do
		if UnitExists(u) then
			local name = UnitName(u)
			if type(name) == "string" and not S(name) then
				return PT.EditNote((UnitIsPlayer(u) and "player:" or "npc:") .. name, name)
			end
		end
	end
	Print("target someone (or a creature) first - or /tips note <a title>, /tips note [item link], /tips note quest.")
end

---------------------------------------------------------------- the list of notes
local list
function PT.RefreshNoteList()
	if not (list and list:IsShown()) then return end
	local q = (list.search:GetText() or ""):lower()
	local rows = {}
	for key, n in pairs(Notes()) do
		local label = n.label or key:gsub("^%a+:", "")
		local hay = (label .. " " .. (n.text or "") .. " " .. key):lower()
		if q == "" or hay:find(q, 1, true) then rows[#rows + 1] = { key = key, n = n, label = label } end
	end
	table.sort(rows, function(a, b) return (a.n.t or 0) > (b.n.t or 0) end)
	for i, r in ipairs(rows) do
		local b = list.rows[i]
		if not b then
			b = CreateFrame("Button", nil, list.child)
			b:SetSize(380, 32); b:SetPoint("TOPLEFT", 0, -(i - 1) * 34)
			local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.12)
			b.a = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.a:SetPoint("TOPLEFT", 4, -2); b.a:SetWidth(370); b.a:SetJustifyH("LEFT")
			b.b = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.b:SetPoint("TOPLEFT", 4, -17); b.b:SetWidth(370); b.b:SetJustifyH("LEFT"); b.b:SetWordWrap(false)
			b:SetScript("OnClick", function(self) PT.EditNote(self.key, self.label) end)
			list.rows[i] = b
		end
		local kind = KIND[r.key:match("^(%a+):")] or "Note"
		local rate = ((r.n.b or 0) ~= 0 or (r.n.s or 0) ~= 0) and ("   " .. RATE[r.n.b or 0] .. " / " .. RATE[r.n.s or 0]) or ""
		b.a:SetText(r.label .. "  |cff909090" .. kind .. "|r" .. rate)
		b.b:SetText(Preview(r.n.text, 80))
		b.key, b.label = r.key, r.label
		b:Show()
	end
	for i = #rows + 1, #list.rows do list.rows[i]:Hide() end
	list.child:SetHeight(math.max(1, #rows * 34))
	list.empty:SetShown(#rows == 0)
end
function PT.ToggleNoteList()
	if not list then
		list = CreateFrame("Frame", "PintsTipsNoteList", UIParent, "BasicFrameTemplateWithInset")
		list:SetSize(420, 420); list:SetPoint("CENTER"); list:SetFrameStrata("DIALOG")
		list:SetMovable(true); list:EnableMouse(true); list:RegisterForDrag("LeftButton")
		list:SetScript("OnDragStart", list.StartMoving); list:SetScript("OnDragStop", list.StopMovingOrSizing)
		tinsert(UISpecialFrames, "PintsTipsNoteList")
		local t = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); t:SetPoint("TOP", 0, -5); t:SetText("|cffd4a017Pint's|r notes")
		list.search = CreateFrame("EditBox", nil, list, "InputBoxTemplate"); list.search:SetSize(240, 20); list.search:SetPoint("TOPLEFT", 18, -32)
		list.search:SetAutoFocus(false); list.search:SetScript("OnTextChanged", PT.RefreshNoteList)
		local nb = CreateFrame("Button", nil, list, "UIPanelButtonTemplate"); nb:SetSize(120, 22); nb:SetPoint("TOPRIGHT", -14, -30); nb:SetText("New note...")
		nb:SetScript("OnClick", function() PT.NoteCmd("") end)
		nb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("New note")
			GameTooltip:AddLine("For your target, or: /tips note <title>, /tips note [item link], /tips note quest", 1, 1, 1, true); GameTooltip:Show()
		end)
		nb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		local sf = CreateFrame("ScrollFrame", "PintsTipsNoteListScroll", list, "UIPanelScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 12, -60); sf:SetPoint("BOTTOMRIGHT", -32, 12)
		list.child = CreateFrame("Frame", nil, sf); list.child:SetSize(380, 1); sf:SetScrollChild(list.child)
		list.rows = {}
		list.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable"); list.empty:SetPoint("CENTER")
		list.empty:SetText("No notes yet.\nTarget someone and type /tips note")
		list:SetScript("OnShow", PT.RefreshNoteList)
		list:Hide()
	end
	list:SetShown(not list:IsShown())
end
