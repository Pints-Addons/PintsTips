-- Pint's Tips - item tooltips: what the item is used for (professions with skill range, quests, class spells),
-- who on your account has how many, and for recipes, which of your characters know it or can learn it.
-- Counts for your other characters come from Pint's Ledger (it remembers bags, bank, mail and worn gear).
-- Compatibility: WoW Forever runs on the modern game client, where these older functions moved or were renamed.
local GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount)
local GetSpellInfo = GetSpellInfo or function(s)
	local i = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(s)
	if i then return i.name, nil, i.iconID, i.castTime, i.minRange, i.maxRange, i.spellID, i.originalIconID end
end

local PT = PintsTips
local U = PintsTipsUse or { prof = {}, quest = {}, qinfo = {}, class = {}, recipe = {} }

local PROF = { [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering", [165] = "Leatherworking",
	[197] = "Tailoring", [185] = "Cooking", [129] = "First Aid", [356] = "Fishing", [186] = "Mining" }
local CLASSNAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest", SHAMAN = "Shaman",
	MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
local GOLD, GREY, WHITE = "|cffffd100", "|cff888888", "|cffffffff"

local function ClassHex(file)
	local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
	return c and ("|c" .. (c.colorStr or "ffffffff")) or WHITE
end
local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then local n = C_Spell.GetSpellName(id); if n then return n end end
	return GetSpellInfo and (GetSpellInfo(id)) or ("spell " .. id)
end
local function Split(s, f)
	if not s then return end
	for part in s:gmatch("[^;]+") do
		local t = {}
		for v in part:gmatch("[^,]+") do t[#t + 1] = tonumber(v) or v end
		f(t)
	end
end

---------------------------------------------------------------- your characters (from Pint's Ledger)
local ME, REALM = (GetUnitName and GetUnitName("player", false)) or UnitName("player"), GetRealmName()   -- (full "First Second" name on WoW Forever, as Pint's Alts saves it)
local function Characters()
	local db = PintsLedgerDB and PintsLedgerDB.chars and PintsLedgerDB.chars[REALM]
	return db or {}
end
local function WornCount(gear, id)
	local n = 0
	if gear then for _, l in pairs(gear) do if type(l) == "string" and tonumber(l:match("item:(%d+)")) == id then n = n + 1 end end end
	return n
end
local function Counts(id)
	local out = {}
	for name, rec in pairs(Characters()) do
		local it = rec.items or {}
		local bags = (it.bags and it.bags[id]) or 0
		local bank = (it.bank and it.bank[id]) or 0
		local mail = (it.mail and it.mail[id]) or 0
		local worn = WornCount(rec.gear, id)
		if name == ME then
			bags = GetItemCount(id) or bags
			local withBank = GetItemCount(id, true) or 0
			if withBank - bags > bank then bank = withBank - bags end
			worn = 0
			for s = 1, 19 do if GetInventoryItemID("player", s) == id then worn = worn + 1 end end
			bags = math.max(0, bags - worn)  -- the bag count can include worn items
		end
		local total = bags + bank + mail + worn
		if total > 0 then out[#out + 1] = { name = name, class = rec.classFile, total = total, bags = bags, bank = bank, mail = mail, worn = worn } end
	end
	-- this character, if Pint's Ledger isn't running
	if not PintsLedgerDB then
		local bags, all = GetItemCount(id) or 0, GetItemCount(id, true) or 0
		if all > 0 then out[1] = { name = ME, class = select(2, UnitClass("player")), total = all, bags = bags, bank = all - bags, mail = 0, worn = 0 } end
	end
	table.sort(out, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.name < b.name end)
	return out
end
local function AddCounts(tt, id)
	local list = Counts(id)
	if #list == 0 then return end
	local sum = 0
	for _, c in ipairs(list) do
		sum = sum + c.total
		local parts = {}
		if c.bags > 0 then parts[#parts + 1] = "bags " .. c.bags end
		if c.bank > 0 then parts[#parts + 1] = "bank " .. c.bank end
		if c.mail > 0 then parts[#parts + 1] = "mail " .. c.mail end
		if c.worn > 0 then parts[#parts + 1] = "worn " .. c.worn end
		tt:AddDoubleLine(ClassHex(c.class) .. c.name .. "|r", WHITE .. c.total .. "|r " .. GREY .. "(" .. table.concat(parts, ", ") .. ")|r")
	end
	if #list > 1 then tt:AddDoubleLine(GOLD .. "Total|r", WHITE .. sum .. "|r") end
end

-- profession name -> each of your characters' rank in it
local function ProfRank(rec, pname)
	for _, p in ipairs(rec.profs or {}) do if p.name == pname then return p.rank, p.max end end
	local s = rec.secondary and rec.secondary[pname]
	if s then return s.rank, s.max end
end

---------------------------------------------------------------- what it's used for
local function AddProfessions(tt, id, detail)
	local by, order = {}, {}
	local seenNames = {}
	Split(U.prof[id], function(t)
		local skill, learn, spell, count = t[1], t[2], t[3], t[4]
		if learn == 0 then learn = nil end   -- skill level not known
		local p = by[skill]
		if not p then p = { skill = skill, name = PROF[skill] or "?", list = {} }; by[skill] = p; order[#order + 1] = p end
		if learn then p.lo, p.hi = math.min(p.lo or learn, learn), math.max(p.hi or learn, learn) end
		local n = SpellName(spell)
		seenNames[n] = true
		p.list[#p.list + 1] = { name = n, learn = learn, count = count }
	end)
	-- recipes your characters know that the data above doesn't list
	for _, rec in pairs(Characters()) do
		for pname, list in pairs(rec.crafts or {}) do
			for _, craft in pairs(list) do
				for _, r in ipairs(craft.reagents or {}) do
					if r[1] == id and craft.name and not seenNames[craft.name] then
						seenNames[craft.name] = true
						local skill
						for k, v in pairs(PROF) do if v == pname then skill = k end end
						skill = skill or pname
						local p = by[skill]
						if not p then p = { skill = skill, name = pname, list = {} }; by[skill] = p; order[#order + 1] = p end
						p.list[#p.list + 1] = { name = craft.name, count = r[2] }
					end
				end
			end
		end
	end
	if #order == 0 then return false end
	table.sort(order, function(a, b) return a.name < b.name end)
	-- your best rank in each profession, across your characters
	for _, p in ipairs(order) do
		local best
		for _, rec in pairs(Characters()) do local r = ProfRank(rec, p.name); if r and (not best or r > best) then best = r end end
		p.best = best
		local range = p.lo and ((p.lo == p.hi) and tostring(p.lo) or (p.lo .. "-" .. p.hi)) or "?"
		local n = #p.list
		local yours = best and (GREY .. "  you: " .. best .. "|r") or ""
		tt:AddDoubleLine(GOLD .. "Used in " .. p.name .. "|r", WHITE .. "skill " .. range .. "|r " .. GREY .. "(" .. n .. " recipe" .. (n == 1 and "" or "s") .. ")|r" .. yours)
		if detail then
			table.sort(p.list, function(a, b) return (a.learn or 0) < (b.learn or 0) end)
			for i, r in ipairs(p.list) do
				if i > 12 then tt:AddLine(GREY .. "    ... and " .. (#p.list - 12) .. " more|r"); break end
				local col = (r.learn and best and best >= r.learn) and "|cff40ff40" or (r.learn and best and "|cffff8040") or WHITE
				tt:AddDoubleLine("    " .. r.name .. GREY .. " x" .. (r.count or 1) .. "|r", r.learn and (col .. r.learn .. "|r") or "")
			end
		end
	end
	return true
end

local function AddQuests(tt, id, detail)
	local mine = UnitFactionGroup("player") == "Horde" and 1 or 2
	local list, seen = {}, {}
	local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
	Split(U.quest[id], function(t)
		local q = U.qinfo[t[1]]
		if q and (q[3] == 0 or q[3] == mine) then
			-- the same quest can exist once per race; show it once (done if any copy is done)
			local e = seen[q[1]]
			local fin = done and done(t[1]) or false
			if e then e.finished = e.finished or fin
			else e = { id = t[1], title = q[1], level = q[2], count = t[2], finished = fin }; seen[q[1]] = e; list[#list + 1] = e end
		end
	end)
	if #list == 0 then return false end
	table.sort(list, function(a, b) return a.level < b.level end)
	local max = detail and 12 or 3
	for i, q in ipairs(list) do
		if i > max then tt:AddLine(GREY .. "    ... and " .. (#list - max) .. " more quest" .. (#list - max == 1 and "" or "s") .. (detail and "" or " (hold Shift)") .. "|r"); break end
		local finished = q.finished
		tt:AddDoubleLine((i == 1 and (GOLD .. "Quest|r ") or "      ") .. (finished and GREY or WHITE) .. q.title .. "|r" .. GREY .. " [" .. q.level .. "]|r",
			finished and (GREY .. "done|r") or (WHITE .. "x" .. q.count .. "|r"))
	end
	return true
end

local function AddClass(tt, id)
	local by, order = {}, {}
	Split(U.class[id], function(t)
		local c = t[1]
		if not by[c] then by[c] = {}; order[#order + 1] = c end
		local n = SpellName(t[2]):gsub("%s*%(.-%)$", "")
		local dup = false
		for _, x in ipairs(by[c]) do if x == n then dup = true end end
		if not dup then by[c][#by[c] + 1] = n end
	end)
	if #order == 0 then return false end
	for _, c in ipairs(order) do
		local names = by[c]
		local shown = {}
		for i = 1, math.min(3, #names) do shown[i] = names[i] end
		local more = #names > 3 and (" +" .. (#names - 3) .. " more") or ""
		tt:AddLine(ClassHex(c) .. (CLASSNAME[c] or c) .. "|r " .. GOLD .. "reagent:|r " .. WHITE .. table.concat(shown, ", ") .. "|r" .. GREY .. more .. "|r", 1, 1, 1, true)
	end
	return true
end

---------------------------------------------------------------- recipes: who knows it, who could learn it
-- Works for recipe items (scrolls, patterns, plans) and for recipe links people paste in chat (spell / enchant / trade
-- links). "Known" comes from each character's recipe book in Pint's Ledger (saved when they open that profession),
-- falling back to the items they can make.
local BOOK = { Mining = "Smelting" }
local bookIDs = {}            -- [charName] = { [prof] = { ids = {}, names = {} }, seen = time }
local function KnowsSpell(name, rec, pname, spellID, created)
	if name == ME and IsPlayerSpell and IsPlayerSpell(spellID) then return true end
	local b = rec.recipes and rec.recipes[BOOK[pname] or pname]
	if b and b.list then
		local cache = bookIDs[name] and bookIDs[name][pname]
		if not cache or cache.seen ~= b.seen then
			cache = { ids = {}, names = {}, seen = b.seen }
			for _, e in ipairs(b.list) do
				local id = e[2] and tonumber(e[2]:match("enchant:(%d+)") or e[2]:match("spell:(%d+)"))
				if id then cache.ids[id] = true end
				if e[1] then cache.names[(e[1]:gsub(" %(.*%)$", ""))] = true end
			end
			bookIDs[name] = bookIDs[name] or {}; bookIDs[name][pname] = cache
		end
		if cache.ids[spellID] then return true end
		local sn = SpellName(spellID)
		if sn and cache.names[sn] then return true end
	end
	local list = rec.crafts and rec.crafts[BOOK[pname] or pname]
	return list and created and created ~= 0 and list[created] and true or false
end
local function AddRecipeFor(tt, spellID, skill, learn, created)
	local pname = PROF[skill]
	if not pname or not learn then return false end
	local known, can, later = {}, {}, {}
	for name, rec in pairs(Characters()) do
		local rank = ProfRank(rec, pname)
		if rank then
			local col = ClassHex(rec.classFile) .. name .. "|r"
			if KnowsSpell(name, rec, pname, spellID, created) then known[#known + 1] = col
			elseif rank >= learn then can[#can + 1] = col .. GREY .. " (" .. rank .. ")|r"
			else later[#later + 1] = col .. GREY .. " (" .. rank .. "/" .. learn .. ")|r" end
		end
	end
	if #known + #can + #later == 0 then
		tt:AddLine(GREY .. pname .. " " .. learn .. " - none of your characters have " .. pname .. ".|r", 1, 1, 1, true)
		return true
	end
	if #known > 0 then tt:AddLine(GOLD .. "Known by:|r " .. table.concat(known, ", "), 1, 1, 1, true) end
	if #can > 0 then tt:AddLine("|cff40ff40Could learn now:|r " .. table.concat(can, ", "), 1, 1, 1, true) end
	if #later > 0 then tt:AddLine("|cffff8040Learnable at " .. pname .. " " .. learn .. ":|r " .. table.concat(later, ", "), 1, 1, 1, true) end
	return true
end
local function AddRecipe(tt, id)
	local r = U.recipe[id]
	if not r then return false end
	return AddRecipeFor(tt, r[1], r[2], r[3], r[4])
end

-- a recipe by its spell: Pints Recipe Sources' data covers every recipe (trainer ones too); ours covers recipe items
local spellIndex
local function RecipeBySpell(spellID)
	local D = RecipeSourcesData
	local r = D and D.recipes and D.recipes[spellID]
	if r then
		local mk = D.make and D.make[spellID]
		return r[1], r[2], mk and mk[1] or 0
	end
	if not spellIndex then
		spellIndex = {}
		for item, rr in pairs(U.recipe) do spellIndex[rr[1]] = rr end
	end
	local rr = spellIndex[spellID]
	if rr then return rr[2], rr[3], rr[4] end
end
function PT.SpellExtras(tt, spellID)
	local db = PT.db
	if not (db and db.recipeAlts and spellID) then return end
	local skill, learn, created = RecipeBySpell(spellID)
	if not skill then return end
	if tt.ptSpellDone == spellID then return end       -- some tooltips report twice
	tt.ptSpellDone = spellID
	tt:AddLine(" ")
	if AddRecipeFor(tt, spellID, skill, learn, created) then tt:Show() end
end

---------------------------------------------------------------- the tooltip
function PT.ItemExtras(tt, link)
	local db = PT.db
	if not db then return end
	local id = tonumber(link:match("item:(%d+)"))
	if not id then return end
	local detail = IsShiftKeyDown()
	local gap = false
	local function Gap() if not gap then tt:AddLine(" "); gap = true end end
	if db.usedFor then
		local hasUse = U.prof[id] or U.quest[id] or U.class[id]
		if hasUse then Gap() end
		local any = AddProfessions(tt, id, detail)
		AddQuests(tt, id, detail)
		AddClass(tt, id)
		if any and not detail then tt:AddLine(GREY .. "Hold Shift for the recipes|r") end
	end
	if db.recipeAlts and U.recipe[id] then Gap(); AddRecipe(tt, id) end
	if db.counts then
		if Counts(id)[1] then tt:AddLine(" "); AddCounts(tt, id) end
	end
	if db.itemID then tt:AddDoubleLine(GREY .. "Item ID|r", GREY .. id .. "|r") end
end

---------------------------------------------------------------- recipe links: tooltips for spells, and hovering links in chat
local function SpellTip(tt)
	if not tt.GetSpell then return end
	local _, id = tt:GetSpell()
	if id then PT.SpellExtras(tt, id) end
end
local function ClearMark(tt) tt.ptSpellDone = nil end
local hooked = CreateFrame("Frame")
hooked:RegisterEvent("PLAYER_LOGIN")
hooked:SetScript("OnEvent", function()
	for _, t in ipairs({ GameTooltip, ItemRefTooltip }) do
		if t then
			t:HookScript("OnTooltipCleared", ClearMark)
			if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
				-- added once below
			else
				pcall(t.HookScript, t, "OnTooltipSetSpell", SpellTip)
			end
		end
	end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tt, data)
			if tt == GameTooltip or tt == ItemRefTooltip then PT.SpellExtras(tt, data and data.id or select(2, tt:GetSpell())) end
		end)
	end
	-- clicked enchant / trade links (in case the spell hook doesn't fire for them)
	if ItemRefTooltip then
		hooksecurefunc(ItemRefTooltip, "SetHyperlink", function(tt, link)
			local id = type(link) == "string" and tonumber(link:match("^enchant:(%d+)") or link:match("^spell:(%d+)"))
			if id then PT.SpellExtras(tt, id) end
		end)
	end
	-- hover a recipe or item link in chat to see the tooltip (no click needed)
	local function Enter(frame, link)
		if type(link) ~= "string" then return end
		local kind = link:match("^(%a+):")
		if kind == "item" or kind == "enchant" or kind == "spell" then
			GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
			pcall(GameTooltip.SetHyperlink, GameTooltip, link)
			local id = tonumber(link:match("^enchant:(%d+)") or link:match("^spell:(%d+)"))
			if id then PT.SpellExtras(GameTooltip, id) end
			GameTooltip:Show()
		end
	end
	local function Leave() GameTooltip:Hide() end
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf then cf:HookScript("OnHyperlinkEnter", Enter); cf:HookScript("OnHyperlinkLeave", Leave) end
	end
end)
