-- Pint's Tips - your group's quest progress on an item's tooltip ("Frostmaul Shards: Papacookie 3/10").
-- The game doesn't tell add-ons what's in someone else's quest log, so group members running Pint's Tips share their
-- item objectives over the hidden add-on channel (only to your party or raid, only quest progress). Members without it
-- still show as "on this quest" when the game can tell, without a count.
local PT = PintsTips
local PREFIX = "PintsTipsQ"
local peers = {}            -- [name] = { [questID] = { { text = "Frostmaul Shards", have = 3, need = 10 }, ... } }
local sendTimer
local Send

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
local SendMsg = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage

local function Short(name) return name and (name:match("^([^%-]+)") or name) end
local function Channel()
	if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then return "INSTANCE_CHAT" end
	if IsInRaid and IsInRaid() then return "RAID" end
	if (IsInGroup and IsInGroup()) or (GetNumPartyMembers and GetNumPartyMembers() > 0) then return "PARTY" end
end

-- your item objectives: { { qid, have, need, item text }, ... }
local function MyObjectives()
	local out = {}
	local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
	for i = 1, n do
		local qid, header
		if C_QuestLog and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(i); if info then qid, header = info.questID, info.isHeader end
		else
			local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i); qid, header = id, isHeader
		end
		if qid and qid > 0 and not header then
			local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(qid)
			if objs then
				for _, o in ipairs(objs) do
					if o.type == "item" and o.text then
						local name = o.text:match("^(.-):%s*%d+%s*/%s*%d+") or o.text:gsub("%s*%d+%s*/%s*%d+%s*", "")
						out[#out + 1] = { qid, o.numFulfilled or 0, o.numRequired or 0, name }
					end
				end
			elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
				for j = 1, GetNumQuestLeaderBoards(i) or 0 do
					local text, kind = GetQuestLogLeaderBoard(j, i)
					if kind == "item" and text then
						local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
						if name then out[#out + 1] = { qid, tonumber(have), tonumber(need), name } end
					end
				end
			end
		end
	end
	return out
end

function Send(hello)
	local ch = Channel(); if not ch then return end
	pcall(SendMsg, PREFIX, hello and "H" or "R", ch)            -- (R: forget what I sent before)
	for _, o in ipairs(MyObjectives()) do
		local msg = ("O\t%d\t%d\t%d\t%s"):format(o[1], o[2], o[3], o[4]):sub(1, 250)
		pcall(SendMsg, PREFIX, msg, ch)
	end
end
local function SendSoon(hello)
	if sendTimer then return end
	sendTimer = true
	C_Timer.After(2, function() sendTimer = nil; Send(hello) end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_ADDON", "QUEST_LOG_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e, prefix, msg, _, sender)
	if e == "CHAT_MSG_ADDON" then
		if prefix ~= PREFIX or not sender then return end
		local who = Short(sender)
		if who == UnitName("player") then return end
		if msg == "R" or msg == "H" then
			peers[who] = {}
			if msg == "H" then SendSoon(false) end                -- someone new: tell them where we are
			return
		end
		local qid, have, need, text = msg:match("^O\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
		if qid then
			peers[who] = peers[who] or {}
			local q = peers[who][tonumber(qid)] or {}; peers[who][tonumber(qid)] = q
			for _, o in ipairs(q) do if o.text == text then o.have, o.need = tonumber(have), tonumber(need); return end end
			q[#q + 1] = { text = text, have = tonumber(have), need = tonumber(need) }
		end
	elseif e == "GROUP_ROSTER_UPDATE" or e == "PLAYER_ENTERING_WORLD" then
		-- drop anyone who has left
		local here = {}
		local n = GetNumGroupMembers and GetNumGroupMembers() or 0
		local raid = IsInRaid and IsInRaid()
		for i = 1, n do local u = raid and ("raid" .. i) or ("party" .. i); local nm = UnitName(u); if nm then here[Short(nm)] = true end end
		for nm in pairs(peers) do if not here[nm] then peers[nm] = nil end end
		SendSoon(true)
	else
		SendSoon(false)
	end
end)

-- the group's lines for one quest and item, under the item's quest line in the tooltip
local GREY, WHITE, GREEN = "|cff888888", "|cffffffff", "|cff40ff40"
function PT.AddGroupProgress(tt, qid, itemName)
	if not Channel() then return end
	local units = {}
	local raid = IsInRaid and IsInRaid()
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	for i = 1, raid and n or math.max(0, n - 1) do units[#units + 1] = raid and ("raid" .. i) or ("party" .. i) end
	local shown = 0
	for _, u in ipairs(units) do
		local nm = UnitName(u)
		if nm and not UnitIsUnit(u, "player") then
			local who = Short(nm)
			local q = peers[who] and peers[who][qid]
			local line
			if q then
				local o
				for _, x in ipairs(q) do if itemName and x.text and x.text:lower() == itemName:lower() then o = x end end
				o = o or q[1]
				if o then
					local done = o.have >= o.need
					line = (done and GREEN or WHITE) .. o.have .. "/" .. o.need .. "|r"
				end
			elseif peers[who] then
				line = GREY .. "not on it|r"
			elseif C_QuestLog and C_QuestLog.IsUnitOnQuest then
				local ok, on = pcall(C_QuestLog.IsUnitOnQuest, u, qid)
				if ok and on then line = GREY .. "on this quest|r" end
			end
			if line then
				local _, cls = UnitClass(u)
				local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
				local hex = c and ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or WHITE
				tt:AddDoubleLine("        " .. hex .. who .. "|r", line)
				shown = shown + 1
			end
		end
	end
	return shown
end
