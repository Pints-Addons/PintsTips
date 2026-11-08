-- Pint's Tips: hold Shift over a player to see their talent trees beside the tooltip.
-- The trees come from the same inspect Pint's Tips already does for GearScore (the game allows one inspect at a time,
-- so this shares it rather than asking again). Inspecting needs them within about 28 yards and you out of combat;
-- once read, the trees stay available for that player (also in a fight) until you log out.
local PT = _G.PintsTips
if not PT then return end

local SIZE, GAP, TIERS, COLS = 40, 9, 7, 4
local TREE_W = COLS * (SIZE + GAP) - GAP
local PAD = 10

---------------------------------------------------------------- reading the trees
-- one reader for both game clients. Classic Era: GetTalentTabInfo / GetTalentInfo. WoW Forever (modern client): those
-- are gone; the same trees come from C_SpecializationInfo (as the game's own talent window reads them).
local SI = C_SpecializationInfo
local function TabInfo(t, inspect, unit)
	if GetTalentTabInfo then
		local ok, a, b, c, d, e, f = pcall(GetTalentTabInfo, t, inspect)
		if not ok or not a then return end
		if type(a) == "number" then return b, d, e, f end      -- id, name, description, icon, points, background
		return a, b, c, d                                       -- name, icon, points, background
	end
	if SI and SI.GetSpecializationInfo then
		-- specId, name, description, icon, role, primaryStat, pointsSpent, background
		local ok, _, name, _, icon, _, _, pts, bg = pcall(SI.GetSpecializationInfo, t, inspect or false, false, inspect and unit or nil)
		if ok and name then return name, icon, pts, bg end
	end
end
local function TalentInfo(t, i, inspect, unit)
	if GetTalentInfo then
		local ok, a, b, c, d, e, f = pcall(GetTalentInfo, t, i, inspect)
		if not ok or not a then return end
		if type(a) == "table" then return a.name, a.icon, a.tier, a.column, a.rank, a.maxRank end
		return a, b, c, d, e, f                                -- name, icon, tier, column, rank, max rank
	end
	if SI and SI.GetTalentInfo then
		local q = { specializationIndex = t, talentIndex = i, target = inspect and unit or "player", isInspect = inspect or false }
		local ok, a = pcall(SI.GetTalentInfo, q)
		if ok and type(a) == "table" and a.name then return a.name, a.icon, a.tier, a.column, a.rank, a.maxRank end
	end
end
-- (WoW Forever's C_SpecializationInfo.GetTalentInfo is the row-of-three kind, not the classic trees: traits are used there)
local function CanRead() return GetTalentInfo end
-- the three trees: { name, points, icon, talents = { { name, icon, tier, column, rank, max } } }, or nil if unreadable
function PT.ReadGrid(inspect, unit)
	if not CanRead() then return PT.ReadTraits and PT.ReadTraits(inspect, unit) end
	local out, any = {}, false
	for t = 1, 3 do
		local name, icon, pts = TabInfo(t, inspect, unit)
		local tree = { name = name or ("Tree " .. t), points = (type(pts) == "number" and PT.Known(pts)) or nil, icon = icon, talents = {} }
		local n
		if GetNumTalents then local okN, num = pcall(GetNumTalents, t, inspect); if okN and type(num) == "number" then n = num end end
		local sum = 0
		for i = 1, n or 40 do
			local tn, ti, tier, col, rank, max = TalentInfo(t, i, inspect, unit)
			if not tn then if not n then break end
			elseif type(tier) == "number" and type(col) == "number" then
				rank, max = PT.Known(rank) or 0, PT.Known(max) or 0
				tree.talents[#tree.talents + 1] = { tn, ti, tier, col, rank, max }
				sum = sum + rank
			end
		end
		-- (an inspect may not fill in the tree totals: count them up instead)
		if not tree.points or (tree.points == 0 and sum > 0) then tree.points = sum end
		if #tree.talents > 0 then any = true end
		out[t] = tree
	end
	if not any then return PT.ReadTraits and PT.ReadTraits(inspect, unit) end
	local best = 1
	for t = 2, 3 do if out[t].points > out[best].points then best = t end end
	out.summary = ("%s (%d/%d/%d)"):format(out[best].name, out[1].points, out[2].points, out[3].points)
	return out
end

-- WoW Forever: the modern client has no classic talent functions; talents are "traits" (C_Traits). Read every node of
-- the character's trait trees and lay them out by their position in the game's own talent window.
local function SpellNI(id)
	if not id then return end
	if C_Spell and C_Spell.GetSpellInfo then local i = C_Spell.GetSpellInfo(id); if i then return i.name, i.iconID end end
	if GetSpellInfo then local n, _, ic = GetSpellInfo(id); return n, ic end
end
local function TraitConfig(inspect)
	if not (C_Traits and C_Traits.GetConfigInfo) then return end
	if inspect then return (Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID) or -1 end
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return end
	local ok, id = pcall(C_ClassTalents.GetActiveConfigID)
	return ok and id or nil
end
PT.TREE_NAMES = {
	WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
	HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
	PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
	MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
	DRUID = { "Balance", "Feral Combat", "Restoration" },
}
function PT.ReadTraits(inspect, unit)
	local cid = TraitConfig(inspect)
	if not cid then return end
	local okC, cfg = pcall(C_Traits.GetConfigInfo, cid)
	if not okC or not cfg or not cfg.treeIDs then return end
	local nodes, total = {}, 0
	local st = { all = 0, info = 0, pos = 0, named = 0 }
	PT.traitStats = st
	for _, tree in ipairs(cfg.treeIDs) do
		local okT, ids = pcall(C_Traits.GetTreeNodes, tree)
		for _, nid in ipairs(okT and ids or {}) do
			local okN, n = pcall(C_Traits.GetNodeInfo, cid, nid)
			st.all = st.all + 1
			if okN and n and n.ID and n.ID ~= 0 then st.info = st.info + 1 end
			if okN and n and n.ID and n.ID ~= 0 and n.isVisible ~= false and type(n.posX) == "number" and type(n.posY) == "number" then
				st.pos = st.pos + 1
				local rank = PT.Known(n.activeRank) or PT.Known(n.currentRank) or PT.Known(n.ranksPurchased) or 0
				local max = PT.Known(n.maxRanks) or 1
				local eid = (n.activeEntry and n.activeEntry.entryID) or (n.entryIDs and n.entryIDs[1])
				local name, icon
				if eid then
					local okE, e = pcall(C_Traits.GetEntryInfo, cid, eid)
					local okD, d = false, nil
					if okE and e and e.definitionID then okD, d = pcall(C_Traits.GetDefinitionInfo, e.definitionID) end
					if okD and d then
						name, icon = SpellNI(d.overriddenSpellID or d.spellID)
						name, icon = d.overrideName or name, d.overrideIcon or icon
					end
				end
				if name or icon then
					st.named = st.named + 1
					nodes[#nodes + 1] = { name or "?", icon, n.posX, n.posY, rank, max, n.subTreeID }
					total = total + rank
				end
			end
		end
	end
	if #nodes == 0 then return end
	-- positions -> grid cells: the smallest step between distinct positions is one cell
	-- the grid step is the usual distance between neighbours; small nudges in the game's layout (a node set a little
	-- off its column) are ignored, so they land in the nearest cell instead of making the grid huge
	local function Cells(k)
		local vals, seen = {}, {}
		for _, d in ipairs(nodes) do local v = math.floor(d[k] + 0.5); if not seen[v] then seen[v] = true; vals[#vals + 1] = v end end
		table.sort(vals)
		local span = (vals[#vals] or 0) - (vals[1] or 0)
		if span <= 0 then return vals[1] or 0, 1 end
		local minGap, bin = span / 40, math.max(1, span / 200)
		local count, best, bestN = {}, nil, 0
		for i = 2, #vals do
			local g = vals[i] - vals[i - 1]
			if g >= minGap then
				local key = math.floor(g / bin + 0.5)
				count[key] = (count[key] or 0) + 1
				if count[key] > bestN or (count[key] == bestN and key < best) then best, bestN = key, count[key] end
			end
		end
		if not best then return vals[1], span end
		-- the exact step: the average of the gaps in the winning group
		local sum, n = 0, 0
		for i = 2, #vals do
			local g = vals[i] - vals[i - 1]
			if g >= minGap and math.floor(g / bin + 0.5) == best then sum, n = sum + g, n + 1 end
		end
		return vals[1], sum / n
	end
	-- (for fixing layouts: the raw positions of the last tree read for each class, kept in the saved settings)
	if PT.db then
		local cls0 = unit and PT.Known(select(2, UnitClass(unit))) or "?"
		local raw = {}
		for _, d in ipairs(nodes) do raw[#raw + 1] = ("%s,%s,%d/%d"):format(tostring(d[3]), tostring(d[4]), d[5], d[6]) end
		PT.db.talentDebug = PT.db.talentDebug or {}
		PT.db.talentDebug.pos = PT.db.talentDebug.pos or {}
		PT.db.talentDebug.pos[cls0] = table.concat(raw, " ")
	end
	local x0, sx = Cells(3)
	local y0, sy = Cells(4)
	local cols, rows = 1, 1
	for _, d in ipairs(nodes) do
		d.col = math.floor((d[3] - x0) / sx + 0.5) + 1; d.row = math.floor((d[4] - y0) / sy + 0.5) + 1
		cols, rows = math.max(cols, d.col), math.max(rows, d.row)
	end
	local spec
	if inspect and unit and GetInspectSpecialization then
		local okS, sid = pcall(GetInspectSpecialization, unit)
		if okS and sid and sid > 0 and GetSpecializationInfoByID then spec = select(2, GetSpecializationInfoByID(sid)) end
	elseif not inspect and GetSpecialization and GetSpecializationInfo then
		local okS, si = pcall(GetSpecialization); if okS and si then spec = select(2, GetSpecializationInfo(si)) end
	end
	-- the class's three trees sit side by side with empty columns between: split at the two widest gaps
	local used, list = {}, {}
	for _, d in ipairs(nodes) do if not used[d.col] then used[d.col] = true; list[#list + 1] = d.col end end
	table.sort(list)
	local gaps = {}
	for k = 2, #list do gaps[#gaps + 1] = { list[k] - list[k - 1], list[k - 1] } end
	table.sort(gaps, function(a, b) return a[1] > b[1] end)
	local cuts = {}
	for k = 1, 2 do if gaps[k] and gaps[k][1] > 1 then cuts[#cuts + 1] = gaps[k][2] end end
	table.sort(cuts)
	local trees = {}
	for t = 1, #cuts + 1 do trees[t] = { points = 0, first = math.huge, last = 0 } end
	for _, d in ipairs(nodes) do
		local t = 1
		for k, c in ipairs(cuts) do if d.col > c then t = k + 1 end end
		d.tree = t
		local tr = trees[t]
		tr.points = tr.points + d[5]; tr.first = math.min(tr.first, d.col); tr.last = math.max(tr.last, d.col)
	end
	-- close up the wide space between trees to one empty column
	local shift, prevLast = {}, nil
	for t, tr in ipairs(trees) do
		shift[t] = prevLast and (tr.first - (prevLast + 2)) or 0
		if shift[t] < 0 then shift[t] = 0 end
		prevLast = tr.last - shift[t]
	end
	cols = 1
	for _, d in ipairs(nodes) do d.col = d.col - shift[d.tree]; cols = math.max(cols, d.col) end
	for t, tr in ipairs(trees) do tr.first, tr.last = tr.first - shift[t], tr.last - shift[t] end
	local cls = unit and select(2, UnitClass(unit))
	local names = #trees == 3 and PT.TREE_NAMES[PT.Known(cls) or ""] or nil
	local best = 1
	for t, tr in ipairs(trees) do tr.name = names and names[t] or ("Tree " .. t); if tr.points > trees[best].points then best = t end end
	local summary
	if #trees == 3 then summary = ("%s (%d/%d/%d)"):format(trees[best].name, trees[1].points, trees[2].points, trees[3].points)
	else summary = (spec and (spec .. " ") or "") .. "(" .. total .. " points)" end
	return { canvas = nodes, cols = cols, rows = rows, total = total, spec = spec, trees = trees, summary = summary }
end

-- /tips talents: what the game hands back for your target's talents (for bug reports)
local function Raw(...)
	local t = {}
	for i = 1, select("#", ...) do local v = select(i, ...); t[i] = (PT.Secret and issecretvalue(v)) and "<secret>" or tostring(v) end
	return table.concat(t, ", ")
end
function PT.TalentDumpNow(unit, quiet)
	-- the lines also go into the saved settings (PintsTipsDB.talentDebug), so they can be read after a /reload
	local lines = {}
	local P = function(m) lines[#lines + 1] = m; if not quiet then print("|cffd4a017Pint's Tips talents:|r " .. m) end end
	-- saved straight away, so whatever is read before something goes wrong is kept
	if PT.db then PT.db.talentDebug = PT.db.talentDebug or {}; PT.db.talentDebug[(unit ~= "player") and "inspect" or "player"] = lines end
	local inspect = unit ~= "player"
	P(("%s  inspect=%s  build=%s"):format(UnitName(unit) or "?", tostring(inspect), tostring((select(4, GetBuildInfo())))))
	P("APIs: GetTalentTabInfo=" .. type(GetTalentTabInfo) .. " GetNumTalents=" .. type(GetNumTalents) .. " GetTalentInfo=" .. type(GetTalentInfo)
		.. " C_SpecializationInfo=" .. type(C_SpecializationInfo) .. " C_ClassTalents=" .. type(C_ClassTalents))
	-- every talent-ish function this client has
	local function Keys(tbl)
		local k = {}
		for name, v in pairs(tbl or {}) do if type(v) == "function" then k[#k + 1] = name end end
		table.sort(k); return table.concat(k, " ")
	end
	P("C_SpecializationInfo keys: " .. Keys(C_SpecializationInfo))
	P("C_ClassTalents keys: " .. Keys(C_ClassTalents))
	local g = {}
	for name, v in pairs(_G) do
		if type(v) == "function" and type(name) == "string" and (name:find("Talent") or name:find("Inspect")) then g[#g + 1] = name end
		if type(v) == "table" and type(name) == "string" and name:find("^C_") and (name:find("Talent") or name:find("Trait") or name:find("Spec") or name:find("Inspect")) then g[#g + 1] = name .. "{}" end
	end
	table.sort(g)
	P("globals: " .. table.concat(g, " "))
	if SI then
		P("C_SpecializationInfo: GetSpecializationInfo=" .. type(SI.GetSpecializationInfo) .. " GetTalentInfo=" .. type(SI.GetTalentInfo))
		for t = 1, 3 do
			if SI.GetSpecializationInfo then P(("spec %d: %s"):format(t, Raw(pcall(SI.GetSpecializationInfo, t, inspect, false, inspect and unit or nil)))) end
			if SI.GetTalentInfo then
				local ok, a = pcall(SI.GetTalentInfo, { specializationIndex = t, talentIndex = 1, target = inspect and unit or "player", isInspect = inspect })
				P(("  talent 1: %s"):format(ok and type(a) == "table" and Raw(a.name, a.tier, a.column, a.rank, a.maxRank) or Raw(ok, a)))
			end
		end
	end
	for t = 1, 3 do
		if GetTalentTabInfo then P(("tab %d: %s"):format(t, Raw(pcall(GetTalentTabInfo, t, inspect)))) end
		if GetNumTalents then P(("  count: %s"):format(Raw(pcall(GetNumTalents, t, inspect)))) end
		if GetTalentInfo then P(("  talent 1: %s"):format(Raw(pcall(GetTalentInfo, t, 1, inspect)))) end
	end
	if C_Traits and C_Traits.GetConfigInfo then
		local cid = TraitConfig(inspect)
		P("trait config: " .. tostring(cid))
		local okC, cfg = pcall(C_Traits.GetConfigInfo, cid or 0)
		if okC and cfg then
			P(("  type=%s name=%s trees=%s"):format(tostring(cfg.type), tostring(cfg.name), table.concat(cfg.treeIDs or {}, ",")))
			local t = cfg.treeIDs and cfg.treeIDs[1]
			local okT, ids = pcall(C_Traits.GetTreeNodes, t or 0)
			P("  nodes in tree 1: " .. (okT and ids and #ids or "error"))
			for k = 1, math.min(3, okT and ids and #ids or 0) do
				local okN, n = pcall(C_Traits.GetNodeInfo, cid, ids[k])
				if okN and n then
					P("  node ID,posX,posY,activeRank,currentRank,ranksPurchased,maxRanks,isVisible,entries,subTree,type: " .. Raw(n.ID, n.posX, n.posY, n.activeRank, n.currentRank, n.ranksPurchased, n.maxRanks, n.isVisible, n.entryIDs and #n.entryIDs, n.subTreeID, n.type))
					local eid = (n.activeEntry and n.activeEntry.entryID) or (n.entryIDs and n.entryIDs[1])
					local okE, e = pcall(C_Traits.GetEntryInfo, cid, eid or 0)
					P("    entry " .. tostring(eid) .. ": " .. (okE and e and Raw(e.definitionID, e.type, e.maxRanks) or Raw(okE, e)))
					if okE and e and e.definitionID then
						local okD, d = pcall(C_Traits.GetDefinitionInfo, e.definitionID)
						P("    definition spellID,overriddenSpellID,overrideName,overrideIcon: " .. (okD and d and Raw(d.spellID, d.overriddenSpellID, d.overrideName, d.overrideIcon) or Raw(okD, d)))
					end
				end
			end
		else P("  config info: " .. Raw(okC, cfg)) end
	end
	local g = PT.ReadGrid(inspect, unit)
	local st = PT.traitStats
	if st then P(("trait nodes: %d, with info %d, with position %d, with a name %d"):format(st.all, st.info, st.pos, st.named)) end
	P(not g and "read FAILED" or g.canvas and ("read OK (traits): %d nodes, %dx%d, %s"):format(#g.canvas, g.cols, g.rows, g.summary)
		or ("read OK: %d/%d/%d"):format(g[1].points, g[2].points, g[3].points))
	if PT.db then PT.db.talentDebug = PT.db.talentDebug or {}; PT.db.talentDebug[inspect and "inspect" or "player"] = lines end
end
-- recorded automatically: your own talents once at login, and the first inspect that comes back without talents
local function SafeDump(unit)
	local ok, err = pcall(PT.TalentDumpNow, unit, true)
	if not ok and PT.db and PT.db.talentDebug then
		local l = PT.db.talentDebug[(unit ~= "player") and "inspect" or "player"]
		if l then l[#l + 1] = "ERROR: " .. tostring(err) end
	end
end
local rec = CreateFrame("Frame")
-- (login recording off now that WoW Forever reads; /tips talents still shows it)
rec:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); C_Timer.After(3, function() SafeDump("player") end) end)
function PT.TalentFailed(unit)
	if PT.failRecorded then return end
	PT.failRecorded = true
	SafeDump(unit)
end
function PT.TalentDump()
	local u = UnitExists("target") and UnitIsPlayer("target") and "target" or "player"
	if u == "player" or PT.Known(UnitIsUnit(u, "player")) then return PT.TalentDumpNow("player") end
	if InCombatLockdown() or not CanInspect(u) then print("|cffd4a017Pint's Tips:|r can't inspect your target right now.") return end
	PT.dumpGUID = PT.SafeGUID(u)
	print("|cffd4a017Pint's Tips:|r inspecting " .. (UnitName(u) or "?") .. "...")
	NotifyInspect(u)
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
	-- points in it: "2/5" on a dark tag in the bottom-right corner
	b.tag = b:CreateTexture(nil, "OVERLAY"); b.tag:SetColorTexture(0, 0, 0, 0.75)
	b.rank = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge"); b.rank:SetPoint("BOTTOMRIGHT", 4, -3)
	b.rank:SetDrawLayer("OVERLAY", 7)
	b.tag:SetPoint("TOPLEFT", b.rank, "TOPLEFT", -2, 1); b.tag:SetPoint("BOTTOMRIGHT", b.rank, "BOTTOMRIGHT", 2, -1)
	win.icons[i] = b
	return b
end

-- how a talent looks: gold edge when full, green when part-way, faded when untaken; always shows its points
function PT.RankLook(b, rank, max)
	max = math.max(max or 1, 1)
	if rank == 0 then b.edge:SetColorTexture(0, 0, 0, 0.8); b.rank:SetText("|cff808080" .. rank .. "/" .. max .. "|r")
	elseif rank >= max then b.edge:SetColorTexture(1, 0.82, 0, 1); b.rank:SetText("|cffffd100" .. rank .. "/" .. max .. "|r")
	else b.edge:SetColorTexture(0.2, 0.9, 0.2, 1); b.rank:SetText("|cff40ff40" .. rank .. "/" .. max .. "|r") end
end
local function ClassHex(cls)
	local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
	return c and ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
end

local function Show(tt, name, cls, grid, note)
	if not win then Build() end
	win.title:SetText(ClassHex(cls) .. (name or "?") .. "|r  |cffd4a017talents|r")
	local used = 0
	local CLASSIC_W, CLASSIC_H = PAD * 2 + TREE_W * 3 + 16 * 2, PAD * 2 + 34 + TIERS * (SIZE + GAP)
	if grid and grid.canvas then
		-- WoW Forever trait tree: drawn where the game's talent window has each one
		win.msg:SetText("")
		for t = 1, 3 do win.trees[t].head:SetText("") end
		local cell = math.min(SIZE + GAP, math.floor(1100 / math.max(1, grid.cols)), math.floor(640 / math.max(1, grid.rows)))
		if grid.trees and #grid.trees <= 3 then
			-- each tree's name and points, centred over its columns
			for t, tr in ipairs(grid.trees) do
				local h = win.trees[t].head
				h:ClearAllPoints()
				h:SetWidth(math.max(90, (tr.last - tr.first + 1) * cell + 20))
				h:SetPoint("TOP", win, "TOPLEFT", PAD + (tr.first - 1 + (tr.last - tr.first + 1) / 2) * cell - GAP / 2, -PAD - 18)
				h:SetText(("%s |cffffffff%d|r"):format(tr.name, tr.points))
			end
		else
			win.trees[1].head:SetText(("%s |cffffffff%d points|r"):format(grid.spec or "", grid.total or 0))
		end
		local sz = math.max(12, cell - GAP)
		win:SetSize(math.max(220, PAD * 2 + grid.cols * cell), PAD * 2 + 36 + grid.rows * cell)
		for _, d in ipairs(grid.canvas) do
			used = used + 1
			local b = Icon(used)
			b:SetSize(sz, sz)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + (d.col - 1) * cell, -PAD - 36 - (d.row - 1) * cell)
			b.tex:SetTexture(d[2] or "Interface\\Icons\\INV_Misc_QuestionMark")
			local rank, max = d[5], d[6]
			b.tex:SetDesaturated(rank == 0); b.tex:SetAlpha(rank == 0 and 0.35 or 1)
			PT.RankLook(b, rank, max)
			b:Show()
		end
	elseif grid then
		win:SetSize(CLASSIC_W, CLASSIC_H)
		for t = 1, 3 do local h = win.trees[t].head; h:ClearAllPoints(); h:SetWidth(TREE_W); h:SetPoint("TOPLEFT", win.trees[t].x, -PAD - 18) end
		win.msg:SetText("")
		for t = 1, 3 do
			local tree, slot = grid[t], win.trees[t]
			slot.head:SetText(("%s |cffffffff%d|r"):format(tree.name or "?", tree.points or 0))
			for _, d in ipairs(tree.talents) do
				used = used + 1
				local b = Icon(used)
				b:SetSize(SIZE, SIZE)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", win, "TOPLEFT", slot.x + (d[4] - 1) * (SIZE + GAP), -PAD - 36 - (d[3] - 1) * (SIZE + GAP))
				b.tex:SetTexture(d[2])
				local rank, max = d[5], d[6]
				b.tex:SetDesaturated(rank == 0); b.tex:SetAlpha(rank == 0 and 0.35 or 1)
				PT.RankLook(b, rank, max)
				b:Show()
			end
		end
	else
		win:SetSize(CLASSIC_W, 120)
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
	if InCombatLockdown() then return Hide() end   -- (never in a fight: Shift is busy there)
	if not IsShiftKeyDown() or not unit or not UnitIsPlayer(unit) then return Hide() end
	local name, cls = UnitName(unit), select(2, UnitClass(unit))
	name, cls = PT.Known(name), PT.Known(cls)
	if PT.Known(UnitIsUnit(unit, "player")) then
		return Show(tt, name, cls, PT.ReadGrid(false, "player"), "Couldn't read your talents.")
	end
	local guid = PT.SafeGUID(unit)
	local c = guid and PT.cache[guid]
	if c and c.grid then return Show(tt, name, cls, c.grid) end
	local why
	if c and c.gridTried then why = "The game didn't send their talents.\n|cff909090(/tips talents with them targeted shows what it sent)|r"
	elseif InCombatLockdown() then why = "Can't inspect in a fight - try again after."
	elseif not CanInspect(unit) then why = "The game won't let you inspect them."
	elseif CheckInteractDistance and not PT.Secret and not CheckInteractDistance(unit, 1) then why = "Too far away - get within about 28 yards."
	else why = "Reading..."; PT.TryInspect(unit, true) end
	Show(tt, name, cls, nil, why)
end

-- pressing or letting go of Shift while the tooltip is up
local ev = CreateFrame("Frame")
ev:RegisterEvent("MODIFIER_STATE_CHANGED"); ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function(_, e, key)
	if e == "PLAYER_REGEN_DISABLED" then Hide(); return end   -- (a fight starts: put it away)
	if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
	if GameTooltip:IsShown() and UnitExists("mouseover") then PT.TalentPeek(GameTooltip, "mouseover") else Hide() end
end)
GameTooltip:HookScript("OnHide", Hide)
