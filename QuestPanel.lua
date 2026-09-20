-- A panel that opens beside the group finder and lists the selected dungeon's quests.
-- Click a quest to see where it starts and what has to be done first; finished quests grey out.
-- Data comes from QuestData.lua (generated); nothing here talks to the network.
local _, ns = ...

local PANEL_WIDTH = 690
local ROW_WIDTH = PANEL_WIDTH - 46
-- Column widths, left to right: quest name, where you pick it up, pick-up level, sharing, status.
-- They are laid out from ROW_WIDTH so the last column cannot fall off the edge of the scroll area.
local GAP = 6
local COL_STATUS, COL_SHARE, COL_XP, COL_LEVEL, COL_WHERE = 48, 66, 60, 56, 146
local COL_QUEST = ROW_WIDTH - COL_WHERE - COL_LEVEL - COL_XP - COL_SHARE - COL_STATUS - GAP * 6
local COL_X = {
  quest = GAP,
  where = GAP * 2 + COL_QUEST,
  level = GAP * 3 + COL_QUEST + COL_WHERE,
  xp = GAP * 4 + COL_QUEST + COL_WHERE + COL_LEVEL,
  share = GAP * 5 + COL_QUEST + COL_WHERE + COL_LEVEL + COL_XP,
  status = GAP * 6 + COL_QUEST + COL_WHERE + COL_LEVEL + COL_XP + COL_SHARE,
}

--- 12,450 rather than 12450.
local function groupDigits(value)
  local text = tostring(value or 0)
  local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

local FACTION = UnitFactionGroup and UnitFactionGroup("player") or nil
local MY_SIDE = FACTION == "Horde" and "horde" or FACTION == "Alliance" and "alliance" or nil

local GREY, WHITE, GOLD, GREEN = "|cff8a8a8a", "|cffffffff", "|cffffd100", "|cff40d040"
local ALLIANCE_BLUE, HORDE_RED = "|cff6aa9ff", "|cffe06060"
local ORANGE = "|cffff8000"
local SIDE_TAG = { alliance = ALLIANCE_BLUE .. "A|r", horde = HORDE_RED .. "H|r", both = GREY .. "A/H|r" }
-- Marker in front of a quest name: whose quest it is.
local QUEST_SIDE_MARK = {
  alliance = ALLIANCE_BLUE .. "[A]|r ",
  horde = HORDE_RED .. "[H]|r ",
  both = GREY .. "[A/H]|r ",
}
-- Which step of a quest happens inside the dungeon.
local INSIDE_TAG = {
  given = GREEN .. "[given inside]|r",
  drop = GREEN .. "[drops inside]|r",
  turnin = GREEN .. "[hand in inside]|r",
  do_ = GREEN .. "[do inside]|r",
  entrance = GOLD .. "[at the entrance]|r",
}

local panel, rows, dropdown
local selectedSlug, expandedId

local function dungeonBySlug(slug)
  for _, dungeon in ipairs(ns.dungeons) do
    if dungeon.slug == slug then return dungeon end
  end
end

local function canTake(quest)
  return quest.side == "both" or MY_SIDE == nil or quest.side == MY_SIDE
end

--- Every quest of this dungeon, chain members kept together; the caller splits them by faction.
local function questsFor(dungeon)
  local list = {}
  for _, quest in ipairs(dungeon) do list[#list + 1] = quest end
  -- A chain sorts by the level of its first step, so step 2 follows step 1 instead of jumping the list.
  local groupLevel = {}
  for _, quest in ipairs(list) do
    local key = quest.id
    local level = quest.level
    for _, other in ipairs(list) do
      if quest.needs and other.title == quest.needs then
        key = other.id
        level = other.level
      end
    end
    groupLevel[quest.id] = { key = key, level = level }
  end
  table.sort(list, function(a, b)
    local ga, gb = groupLevel[a.id], groupLevel[b.id]
    if ga.level ~= gb.level then return ga.level < gb.level end
    if ga.key ~= gb.key then return ga.key < gb.key end
    local sa, sb = a.step or 0, b.step or 0
    if sa ~= sb then return sa < sb end
    if a.level ~= b.level then return a.level < b.level end
    return a.title < b.title
  end)
  return list
end

local function isCompleted(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) end
  if type(IsQuestFlaggedCompleted) == "function" then return IsQuestFlaggedCompleted(id) end
  return false
end

local function inLog(id)
  if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(id) ~= nil end
  if type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function" then
    for i = 1, GetNumQuestLogEntries() do
      local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
      if not isHeader and questID == id then return true end
    end
  end
  return false
end

local function readyForTurnIn(id)
  if C_QuestLog and C_QuestLog.ReadyForTurnIn then
    local ok, ready = pcall(C_QuestLog.ReadyForTurnIn, id)
    if ok then return ready end
  end
  return false
end

--- Quest ids we learned by name from the quest log, kept between sessions.
local function learnedIds()
  WoWForeverBuildsDB = WoWForeverBuildsDB or {}
  WoWForeverBuildsDB.questIdsByName = WoWForeverBuildsDB.questIdsByName or {}
  return WoWForeverBuildsDB.questIdsByName
end

--- The quest log entry with this name, if you are on it. Written preludes have no id of their own,
--- so this is how they get one.
local function questLogEntryByName(name)
  if not name then return nil end
  local lower = name:lower()
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(index)
      if info and not info.isHeader and info.title and info.title:lower() == lower then return info.questID end
    end
  elseif type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function" then
    for index = 1, GetNumQuestLogEntries() do
      local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
      if not isHeader and title and title:lower() == lower then return questID end
    end
  end
  return nil
end

--- "done", "active" or nil for a quest we only know by name.
local function statusByName(name)
  local ids = learnedIds()
  local inLogId = questLogEntryByName(name)
  if inLogId then
    ids[name] = inLogId
    return readyForTurnIn(inLogId) and "turnin" or "active"
  end
  local known = ids[name]
  if known and isCompleted(known) then return "done" end
  return nil
end

--- A prelude line reads "Quest name (where it starts)"; split it for the name and place columns.
local function preludeRow(line, index, total)
  local name, where = line:match("^(.-)%s*%((.+)%)$")
  return {
    title = name or line,
    spot = where,
    prelude = true,
    step = index,
    of = total,
  }
end

--- A quest that begins inside the dungeon, or follows on from another, is indented under it.
local function indentOf(quest)
  if quest.step and quest.step > 1 then return 18, "|cff8a8a8a> |r" end
  if quest.inside == "given" or quest.inside == "drop" then return 18, "|cff40d040> |r" end
  return 0, ""
end

--- status, title colour, badge text.
local function statusOf(quest)
  if isCompleted(quest.id) then return "done", GREY, GREY .. "done|r" end
  if readyForTurnIn(quest.id) then return "turnin", GREEN, GREEN .. "turn in|r" end
  if inLog(quest.id) then return "active", GOLD, GOLD .. "in log|r" end
  return "todo", WHITE, nil
end

local function whereFor(quest)
  if MY_SIDE == "horde" then return quest.whereH or quest.whereA end
  return quest.whereA or quest.whereH
end

--- Every quest we carry, by id, so a chain can be followed across dungeons.
local byId
local function questById(id)
  if not byId then
    byId = {}
    for _, dungeon in ipairs(ns.dungeons) do
      for _, quest in ipairs(dungeon) do byId[quest.id] = { quest = quest, dungeon = dungeon } end
    end
  end
  return byId[id]
end

--- The whole chain a quest belongs to, walked back to the first step and forward to the last.
-- Steps we have data for carry the quest; the rest are name-only links from the client's chain data.
local function chainOf(quest)
  if not quest.needs and not quest.next then return nil end
  local steps = { { quest = quest } }
  local guard = 0
  local current = quest
  while current and current.needsId and guard < 12 do
    guard = guard + 1
    local found = questById(current.needsId)
    table.insert(steps, 1, found and { quest = found.quest, dungeon = found.dungeon } or { name = current.needs })
    current = found and found.quest or nil
  end
  if not current and quest.needs and not quest.needsId then table.insert(steps, 1, { name = quest.needs }) end
  current, guard = quest, 0
  while current and current.nextId and guard < 12 do
    guard = guard + 1
    local found = questById(current.nextId)
    steps[#steps + 1] = found and { quest = found.quest, dungeon = found.dungeon } or { name = current.next }
    current = found and found.quest or nil
  end
  if current == quest and quest.next and not quest.nextId then steps[#steps + 1] = { name = quest.next } end
  return #steps > 1 and steps or nil
end

--- "kill these", "collect these" or "deliver this", read from the objective lines.
local function objectiveLines(quest)
  if not quest.obj or #quest.obj == 0 then return nil end
  local lines = {}
  for _, entry in ipairs(quest.obj) do
    lines[#lines + 1] = "  - " .. entry
  end
  return table.concat(lines, "\n")
end

--- The lines shown under a quest when it is expanded: pick up, do, hand in, then the chain.
local function detailLines(quest)
  local lines = {}
  local where = whereFor(quest)
  if where then
    lines[#lines + 1] = GOLD .. "Pick up:|r " .. where
  elseif quest.from then
    lines[#lines + 1] = GOLD .. "Pick up:|r from " .. quest.from
  end
  if quest.item then lines[#lines + 1] = GOLD .. "Pick up:|r loot " .. quest.item .. " (cannot be shared)" end
  if quest.note then lines[#lines + 1] = GREEN .. "In the dungeon:|r " .. quest.note end
  if quest.goal then lines[#lines + 1] = GOLD .. "Do:|r " .. quest.goal end
  local objectives = objectiveLines(quest)
  if objectives then lines[#lines + 1] = objectives end
  if quest.turnIn then lines[#lines + 1] = GOLD .. "Hand in:|r " .. quest.turnIn end
  lines[#lines + 1] = GREY .. ("Pick up from level %d · quest level %d"):format(quest.req or quest.level, quest.level) .. "|r"
  if quest.xp then lines[#lines + 1] = GREY .. "Reward: " .. groupDigits(quest.xp) .. " XP (estimate from earlier game data)|r" end

  local chain = chainOf(quest)
  if chain or quest.pre then
    lines[#lines + 1] = GOLD .. "Chain:|r"
    -- Steps before this one that are not dungeon quests, so the beta data does not carry them.
    if quest.pre then
      for _, name in ipairs(quest.pre) do
        lines[#lines + 1] = "  " .. GREY .. "- " .. name .. "  (before, outside this dungeon)|r"
      end
    end
  end
  if chain then
    for index, step in ipairs(chain) do
      local mark, name, suffix = "  ", step.name or "?", ""
      if step.quest then
        name = step.quest.title
        if isCompleted(step.quest.id) then
          mark = GREY .. "[x]|r "
        elseif inLog(step.quest.id) then
          mark = GOLD .. "[~]|r "
        else
          mark = "[ ] "
        end
        if step.quest.id == quest.id then suffix = GOLD .. "  <- this one|r" end
        if step.dungeon and step.dungeon.slug ~= selectedSlug then suffix = suffix .. GREY .. "  (" .. step.dungeon.name .. ")|r" end
      else
        mark = "[ ] "
        suffix = GREY .. "  (outside this dungeon)|r"
      end
      lines[#lines + 1] = ("  %d. %s%s%s"):format(index, mark, name, suffix)
    end
  end
  if #lines == 0 then lines[#lines + 1] = "Picked up at the dungeon." end
  return table.concat(lines, "\n")
end

--- The dungeon you are standing in, when it is one we have quests for.
local function currentInstance()
  if type(GetInstanceInfo) ~= "function" then return nil end
  local ok, name, kind = pcall(GetInstanceInfo)
  if ok and type(name) == "string" and (kind == "party" or kind == "raid") then return name end
  return nil
end

--- The dungeon you are queued for, when the queue holds exactly one.
local function queuedDungeon()
  local queued = _G.LFGQueuedForList
  if type(queued) ~= "table" or type(GetLFGDungeonInfo) ~= "function" then return nil end
  local found, count = nil, 0
  for _, dungeons in pairs(queued) do
    if type(dungeons) == "table" then
      for id, on in pairs(dungeons) do
        if on then
          count = count + 1
          found = id
        end
      end
    end
  end
  if count ~= 1 then return nil end
  local ok, name = pcall(GetLFGDungeonInfo, found)
  return ok and type(name) == "string" and name or nil
end

--- The dungeon the group finder has selected, when exactly one is ticked.
local function selectedInFinder()
  local queued = queuedDungeon()
  if queued then return queued end
  local enabled = _G.LFGEnabledList
  local isHeader = _G.LFGIsIDHeader
  if type(enabled) == "table" and type(GetLFGDungeonInfo) == "function" then
    local found, count = nil, 0
    for id, on in pairs(enabled) do
      local header = type(isHeader) == "function" and isHeader(id)
      if on and not header then
        count = count + 1
        found = id
      end
    end
    if count == 1 then
      local ok, name = pcall(GetLFGDungeonInfo, found)
      if ok and type(name) == "string" then return name end
    end
  end
  local frame = _G.LFDQueueFrame
  if frame and type(frame.type) == "number" and type(GetLFGDungeonInfo) == "function" then
    local ok, name = pcall(GetLFGDungeonInfo, frame.type)
    if ok and type(name) == "string" then return name end
  end
  return nil
end

local function matchDungeon(name)
  if type(name) ~= "string" then return nil end
  local lower = name:lower()
  for _, dungeon in ipairs(ns.dungeons) do
    local dname = dungeon.name:lower()
    if lower == dname or lower:find(dname, 1, true) or dname:find(lower, 1, true) then return dungeon.slug end
  end
  return nil
end

--- Finder selection first, then whatever fits the player's level, then the first dungeon we have.
local function defaultSlug()
  local here = matchDungeon(currentInstance())
  if here then return here end
  local fromFinder = matchDungeon(selectedInFinder())
  if fromFinder then return fromFinder end
  local level = UnitLevel and UnitLevel("player") or 1
  for _, dungeon in ipairs(ns.dungeons) do
    if level >= dungeon.min and level <= dungeon.max then return dungeon.slug end
  end
  return ns.dungeons[1] and ns.dungeons[1].slug
end

local refresh

local function buildRow(index)
  local row = CreateFrame("Button", nil, panel.content)
  row:SetWidth(ROW_WIDTH)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetPoint("TOPLEFT", 0, 0)
  row.stripe:SetPoint("BOTTOMLEFT", 0, 0)
  row.stripe:SetWidth(3)

  -- One font string per column, all anchored to the top of the row so they line up as a table.
  local function column(x, width, font, justify)
    local text = row:CreateFontString(nil, "ARTWORK", font)
    text:SetPoint("TOPLEFT", x, -3)
    text:SetWidth(width)
    text:SetJustifyH(justify or "LEFT")
    return text
  end

  row.title = column(COL_X.quest, COL_QUEST, "GameFontNormalSmall")
  row.where = column(COL_X.where, COL_WHERE, "GameFontDisableSmall")
  row.level = column(COL_X.level, COL_LEVEL, "GameFontDisableSmall", "CENTER")
  row.xp = column(COL_X.xp, COL_XP, "GameFontDisableSmall", "RIGHT")
  row.share = column(COL_X.share, COL_SHARE, "GameFontDisableSmall", "CENTER")
  row.badge = column(COL_X.status, COL_STATUS, "GameFontNormalSmall", "RIGHT")

  row.tags = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  row.tags:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
  row.tags:SetJustifyH("LEFT")
  row.tags:SetWidth(COL_QUEST)

  row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  row.detail:SetPoint("TOPLEFT", row.tags, "BOTTOMLEFT", 6, -4)
  row.detail:SetJustifyH("LEFT")
  row.detail:SetWidth(ROW_WIDTH - 26)
  row.detail:SetSpacing(2)

  row:SetScript("OnClick", function(self)
    if not self.questID then return end
    expandedId = expandedId ~= self.questID and self.questID or nil
    refresh()
  end)
  return row
end

refresh = function()
  if not panel or not panel:IsShown() then return end
  local dungeon = dungeonBySlug(selectedSlug)
  if not dungeon then return end
  if dropdown and UIDropDownMenu_SetText then UIDropDownMenu_SetText(dropdown, dungeon.name) end

  local list = questsFor(dungeon)
  local done, mine, totalXp, inLogXp, leftXp, inLogCount = 0, 0, 0, 0, 0, 0
  for _, quest in ipairs(list) do
    if canTake(quest) then
      mine = mine + 1
      local xp = quest.xp or 0
      totalXp = totalXp + xp
      if isCompleted(quest.id) then
        done = done + 1
      else
        leftXp = leftXp + xp
        if inLog(quest.id) then
          inLogCount = inLogCount + 1
          inLogXp = inLogXp + xp
        end
      end
    end
  end

  local place = dungeon.zone and (GOLD .. dungeon.zone .. "|r") or ""
  if dungeon.side == "alliance" then
    place = place .. "  " .. ALLIANCE_BLUE .. "Mostly Alliance|r"
  elseif dungeon.side == "horde" then
    place = place .. "  " .. HORDE_RED .. "Mostly Horde|r"
  elseif dungeon.side == "both" then
    place = place .. "  " .. GREY .. "Both factions|r"
  end
  panel.place:SetText(place)
  local facts = { ("Players %d-%d"):format(dungeon.min, dungeon.max) }
  if dungeon.mobs then facts[#facts + 1] = "Mobs " .. dungeon.mobs end
  if dungeon.boss then facts[#facts + 1] = "Top boss " .. dungeon.boss end
  -- Dungeons the beta has not shown yet fall back to the Classic quest list, which may differ.
  if dungeon.classic then facts[#facts + 1] = ORANGE .. "Classic list, not seen on the beta yet|r" end
  panel.facts:SetText(table.concat(facts, "  ·  "))
  panel.progress:SetText(("%d of %d quests done  ·  %s%s XP in your log (%d)|r  ·  %s XP still to earn  ·  %s XP in total"):format(
    done, mine, GOLD, groupDigits(inLogXp), inLogCount, groupDigits(leftXp), groupDigits(totalXp)))

  -- Only worth saying "both factions" when the dungeon also has faction-only quests.
  local factionSplit = false
  for _, quest in ipairs(list) do
    if quest.side ~= "both" then factionSplit = true end
  end

  -- Three blocks: what you still have to do, what you have finished, then the other faction's quests.
  local todo, finished, other = {}, {}, {}
  for _, quest in ipairs(list) do
    if not canTake(quest) then
      other[#other + 1] = quest
    elseif isCompleted(quest.id) then
      finished[#finished + 1] = quest
    else
      todo[#todo + 1] = quest
    end
  end
  local ordered = {}
  for _, quest in ipairs(todo) do
    -- The questline that opens this one is not in the beta data, so it is written in: list it first.
    if quest.pre then
      local steps = {}
      for index, line in ipairs(quest.pre) do
        steps[index] = preludeRow(line, index, #quest.pre)
        steps[index].status = statusByName(steps[index].title)
      end
      -- Being on step 3 means steps 1 and 2 are behind you, so mark them done even though the
      -- quest log no longer mentions them.
      local reached = 0
      for index, step in ipairs(steps) do
        if step.status then reached = index end
      end
      if quest.needsId and isCompleted(quest.needsId) then reached = #steps end
      for index, step in ipairs(steps) do
        if index < reached and step.status ~= "active" and step.status ~= "turnin" then step.status = "done" end
        ordered[#ordered + 1] = step
      end
    end
    ordered[#ordered + 1] = quest
  end
  -- Counted after the prelude rows are in, so the dividers land in the right place.
  local firstDone = #ordered + 1
  for _, quest in ipairs(finished) do ordered[#ordered + 1] = quest end
  local firstOther = #ordered + 1
  for _, quest in ipairs(other) do ordered[#ordered + 1] = quest end

  local y = 0
  for i, quest in ipairs(ordered) do
    rows[i] = rows[i] or buildRow(i)
    local row = rows[i]
    row.questID = quest.id
    if quest.prelude then
      row.title:ClearAllPoints()
      row.title:SetPoint("TOPLEFT", COL_X.quest + 18, -3)
      row.title:SetWidth(COL_QUEST - 18)
      row.tags:SetWidth(COL_QUEST - 18)
      local preStatus = quest.status
      local preColour = preStatus == "done" and GREY or preStatus == "turnin" and GREEN or preStatus == "active" and GOLD or GREY
      row.title:SetText(ORANGE .. "> |r" .. preColour .. quest.title .. "|r")
      row.where:SetText(quest.spot and (GREY .. quest.spot .. "|r") or "")
      row.level:SetText("")
      row.xp:SetText("")
      row.share:SetText("")
      row.badge:SetText(preStatus == "done" and (GREY .. "done|r") or preStatus == "turnin" and (GREEN .. "turn in|r") or preStatus == "active" and (GOLD .. "in log|r") or "")
      local preLabel = preStatus == "done" and (GREY .. "pre-quest done|r") or (ORANGE .. "pre-quest|r")
      row.tags:SetText(("%s  %s%d/%d|r"):format(preLabel, GREY, quest.step, quest.of))
      row.tags:Show()
      row.detail:SetText("")
      row.detail:Hide()
      if preStatus == "done" then
        row.stripe:SetColorTexture(0.45, 0.45, 0.45, 0.6)
      elseif preStatus == "active" or preStatus == "turnin" then
        row.stripe:SetColorTexture(1, 0.82, 0, 0.9)
      else
        row.stripe:SetColorTexture(1, 0.5, 0, 0.5)
      end
      row.stripe:Show()
      local height = math.max(row.title:GetStringHeight() + row.tags:GetStringHeight() + 12, 30)
      row:SetHeight(height)
      row:SetAlpha(0.85)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
      row:Show()
      y = y + height + 3
    else
    local status, colour, badge = statusOf(quest)

    local indent, arrow = indentOf(quest)
    row.title:ClearAllPoints()
    row.title:SetPoint("TOPLEFT", COL_X.quest + indent, -3)
    row.title:SetWidth(COL_QUEST - indent)
    row.tags:SetWidth(COL_QUEST - indent)
    row.title:SetText((QUEST_SIDE_MARK[quest.side] or "") .. arrow .. colour .. quest.title .. "|r")
    local spotColour = (quest.spot == "Inside" or quest.spot == "Drops inside") and GREEN or (quest.spot == "At the entrance") and GOLD or ""
    row.where:SetText(quest.spot and (spotColour ~= "" and spotColour .. quest.spot .. "|r" or quest.spot) or GREY .. "—|r")
    row.level:SetText(GOLD .. (quest.req or quest.level) .. "+|r")
    row.xp:SetText(quest.xp and (GREY .. groupDigits(quest.xp) .. "|r") or "")
    if quest.item then
      row.share:SetText(HORDE_RED .. "item only|r")
    elseif quest.needs then
      row.share:SetText(HORDE_RED .. "follow-up|r")
    else
      row.share:SetText(GREEN .. "shareable|r")
    end
    row.badge:SetText(badge or "")

    -- Tags live on their own line so a long quest name cannot push them off the panel.
    local tags = {}
    -- What opens this quest, and whether you have done it: the most useful thing to see at a glance.
    local opener = quest.needs or (quest.pre and quest.pre[#quest.pre])
    if opener then
      local openerDone = quest.needsId and isCompleted(quest.needsId)
      tags[#tags + 1] = openerDone and (GREEN .. "unlocked by " .. opener .. "|r") or (ORANGE .. "needs first: " .. opener .. "|r")
    elseif quest.of and quest.of > 1 then
      tags[#tags + 1] = GREEN .. "starts the chain|r"
    end
    if quest.step and quest.of and quest.of > 1 then tags[#tags + 1] = ("%sstep %d/%d|r"):format(GREY, quest.step, quest.of) end
    if quest.inside then tags[#tags + 1] = INSIDE_TAG[quest.inside == "do" and "do_" or quest.inside] or "" end
    if quest.only then tags[#tags + 1] = GREY .. quest.only .. " only|r" end
    -- A quest filled in from the Classic list inside an otherwise beta-backed dungeon.
    if quest.classic and not dungeon.classic then tags[#tags + 1] = GREY .. "from the Classic list|r" end
    row.tags:SetText(table.concat(tags, GREY .. "  ·  |r"))
    if #tags > 0 then
      row.tags:Show()
    else
      row.tags:Hide()
    end
    if status == "active" then
      row.stripe:SetColorTexture(1, 0.82, 0, 0.9)
      row.stripe:Show()
    elseif status == "turnin" then
      row.stripe:SetColorTexture(0.25, 0.82, 0.25, 0.9)
      row.stripe:Show()
    elseif status == "done" then
      row.stripe:SetColorTexture(0.45, 0.45, 0.45, 0.6)
      row.stripe:Show()
    elseif quest.needs or quest.pre then
      row.stripe:SetColorTexture(1, 0.5, 0, 0.75)
      row.stripe:Show()
    else
      row.stripe:Hide()
    end

    if expandedId == quest.id then
      row.detail:SetText(detailLines(quest))
      row.detail:Show()
    else
      row.detail:SetText("")
      row.detail:Hide()
    end

    local height = row.title:GetStringHeight() + 8
    if row.tags:IsShown() then height = height + row.tags:GetStringHeight() + 4 end
    height = math.max(height, 34)
    if row.detail:IsShown() then height = height + row.detail:GetStringHeight() + 8 end
    row:SetHeight(height)
    if i == firstDone and #finished > 0 then
      panel.doneLine:ClearAllPoints()
      panel.doneLine:SetPoint("TOPLEFT", panel.content, "TOPLEFT", COL_X.quest, -y - 8)
      panel.doneLine:SetPoint("RIGHT", panel.content, "RIGHT", -4, 0)
      panel.doneLabel:ClearAllPoints()
      panel.doneLabel:SetPoint("TOPLEFT", panel.content, "TOPLEFT", COL_X.quest, -y - 14)
      panel.doneLabel:SetText(("%sDone  (%d)|r"):format(GREY, #finished))
      panel.doneLine:Show()
      panel.doneLabel:Show()
      y = y + 30
    end
    if i == firstOther and #other > 0 then
      local otherName = MY_SIDE == "horde" and "Alliance only" or "Horde only"
      panel.otherLine:ClearAllPoints()
      panel.otherLine:SetPoint("TOPLEFT", panel.content, "TOPLEFT", COL_X.quest, -y - 8)
      panel.otherLine:SetPoint("RIGHT", panel.content, "RIGHT", -4, 0)
      panel.otherLabel:ClearAllPoints()
      panel.otherLabel:SetPoint("TOPLEFT", panel.content, "TOPLEFT", COL_X.quest, -y - 14)
      panel.otherLabel:SetText(("%s%s  (%d) — you cannot take these|r"):format(GREY, otherName, #other))
      panel.otherLine:Show()
      panel.otherLabel:Show()
      y = y + 30
    end
    row:SetAlpha(not canTake(quest) and 0.4 or isCompleted(quest.id) and 0.45 or 1)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
    row:Show()
    y = y + height + 3
    end
  end
  if #finished == 0 then
    panel.doneLine:Hide()
    panel.doneLabel:Hide()
  end
  if #other == 0 then
    panel.otherLine:Hide()
    panel.otherLabel:Hide()
  end
  for i = #ordered + 1, #rows do rows[i]:Hide() end
  panel.content:SetHeight(math.max(y, 1))
end

local function buildDropdown()
  if not UIDropDownMenu_Initialize then return end
  local ok, frame = pcall(CreateFrame, "Frame", "WoWForeverBuildsQuestDropdown", panel, "UIDropDownMenuTemplate")
  if not ok or not frame then return end
  dropdown = frame
  dropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", -6, -28)
  UIDropDownMenu_SetWidth(dropdown, PANEL_WIDTH - 70)
  UIDropDownMenu_Initialize(dropdown, function()
    for _, dungeon in ipairs(ns.dungeons) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = ("%s (%d-%d) %s"):format(dungeon.name, dungeon.min, dungeon.max, SIDE_TAG[dungeon.side or "both"] or "")
      info.checked = dungeon.slug == selectedSlug
      info.func = function()
        selectedSlug = dungeon.slug
        expandedId = nil
        CloseDropDownMenus()
        refresh()
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
end

local function build()
  if panel then return panel end
  local ok, frame = pcall(CreateFrame, "Frame", "WoWForeverBuildsQuestPanel", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not frame then
    frame = CreateFrame("Frame", "WoWForeverBuildsQuestPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if frame.SetBackdrop then
      frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end
  panel = frame
  panel:SetSize(PANEL_WIDTH, 470)
  panel:SetPoint("CENTER")
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetFrameStrata("HIGH")
  panel:Hide()
  if panel.TitleText then panel.TitleText:SetText("wowforeverbuilds - Dungeon Quest helper") end

  -- Header: zone, then the fight facts, then your progress. Fixed rows, so nothing can overlap.
  panel.place = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  panel.place:SetPoint("TOPLEFT", 16, -62)
  panel.place:SetWidth(PANEL_WIDTH - 32)
  panel.place:SetJustifyH("LEFT")

  panel.facts = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  panel.facts:SetPoint("TOPLEFT", 16, -78)
  panel.facts:SetWidth(PANEL_WIDTH - 32)
  panel.facts:SetJustifyH("LEFT")

  panel.progress = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  panel.progress:SetPoint("TOPLEFT", 16, -94)
  panel.progress:SetJustifyH("LEFT")

  local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 16, -110)
  hint:SetText("Click a quest for the full chain")

  local xpNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  xpNote:SetPoint("TOPLEFT", 16, -124)
  xpNote:SetWidth(PANEL_WIDTH - 32)
  xpNote:SetJustifyH("LEFT")
  xpNote:SetText(ORANGE .. "*XP is inaccurate:|r it comes from earlier versions of the game. Real WoW Forever values are being collected and will replace it.")

  local function heading(x, width, label, justify)
    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 14 + x, -146)
    text:SetWidth(width)
    text:SetJustifyH(justify or "LEFT")
    text:SetText(GREY .. label .. "|r")
    return text
  end
  heading(COL_X.quest, COL_QUEST, "Quest")
  heading(COL_X.where, COL_WHERE, "Pick up at")
  heading(COL_X.level, COL_LEVEL, "Pick-up lvl", "CENTER")
  heading(COL_X.xp, COL_XP, "XP*", "RIGHT")
  heading(COL_X.share, COL_SHARE, "Sharing", "CENTER")
  heading(COL_X.status, COL_STATUS, "Status", "RIGHT")

  local rule = panel:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(1, 1, 1, 0.08)
  rule:SetPoint("TOPLEFT", 14, -160)
  rule:SetPoint("TOPRIGHT", -30, -160)
  rule:SetHeight(1)

  local scroll = CreateFrame("ScrollFrame", "WoWForeverBuildsQuestScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -166)
  scroll:SetPoint("BOTTOMRIGHT", -32, 14)
  panel.content = CreateFrame("Frame", nil, scroll)
  panel.content:SetSize(ROW_WIDTH, 1)
  scroll:SetScrollChild(panel.content)

  panel.doneLine = panel.content:CreateTexture(nil, "ARTWORK")
  panel.doneLine:SetColorTexture(1, 1, 1, 0.08)
  panel.doneLine:SetHeight(1)
  panel.doneLine:Hide()
  panel.doneLabel = panel.content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  panel.doneLabel:SetJustifyH("LEFT")
  panel.doneLabel:Hide()

  panel.otherLine = panel.content:CreateTexture(nil, "ARTWORK")
  panel.otherLine:SetColorTexture(1, 1, 1, 0.08)
  panel.otherLine:SetHeight(1)
  panel.otherLine:Hide()
  panel.otherLabel = panel.content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  panel.otherLabel:SetJustifyH("LEFT")
  panel.otherLabel:Hide()

  rows = {}
  buildDropdown()

  panel:SetScript("OnShow", function()
    if not selectedSlug then selectedSlug = defaultSlug() end
    refresh()
  end)
  panel:SetScript("OnHide", function(self)
    if not self.closedByAddon then ns.questPanelDismissed = true end
  end)
  return panel
end

--- Dock beside the group finder if it is open, otherwise keep the panel where the player left it.
local function anchorToFinder()
  for _, name in ipairs({ "PVEFrame", "LFGParentFrame", "LFDParentFrame", "GroupFinderFrame" }) do
    local frame = _G[name]
    if frame and frame:IsShown() then
      panel:ClearAllPoints()
      panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
      return true
    end
  end
  return false
end

local function hideQuietly()
  if not panel or not panel:IsShown() then return end
  panel.closedByAddon = true
  panel:Hide()
  panel.closedByAddon = nil
end

function ns.ToggleQuestPanel()
  -- the watcher relabels the button on its next pass
  build()
  if panel:IsShown() then
    panel:Hide()
    return
  end
  ns.questPanelDismissed = nil
  selectedSlug = defaultSlug() or selectedSlug
  anchorToFinder()
  panel:Show()
end

local function onFinderShown()
  build()
  -- Closing the panel yourself keeps it closed until you ask for it again with /wfb quests.
  if ns.questPanelDismissed then return end
  selectedSlug = defaultSlug() or selectedSlug
  anchorToFinder()
  panel:Show()
end

local function finderOpen()
  for _, name in ipairs({ "PVEFrame", "LFGParentFrame", "LFDParentFrame", "GroupFinderFrame" }) do
    local frame = _G[name]
    if frame and frame:IsShown() then return true end
  end
  return false
end

--- A show/hide button on the group finder, so closing the panel is never a dead end.
local toggleButton
local function ensureToggleButton()
  if not toggleButton then
    -- Parented to UIParent, not the finder: a child of the finder can end up clipped or behind it.
    local ok, button = pcall(CreateFrame, "Button", "WoWForeverBuildsQuestToggle", UIParent, "UIPanelButtonTemplate")
    if not ok or not button then return nil end
    toggleButton = button
    toggleButton:SetSize(130, 24)
    toggleButton:SetFrameStrata("DIALOG")
    toggleButton:SetScript("OnClick", function()
      ns.ToggleQuestPanel()
    end)
  end
  for _, name in ipairs({ "PVEFrame", "LFGParentFrame", "LFDParentFrame", "GroupFinderFrame" }) do
    local frame = _G[name]
    if frame and frame:IsShown() then
      toggleButton:ClearAllPoints()
      -- Just above the window, over the close button corner, so it covers nothing.
      toggleButton:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -2, 1)
      toggleButton:Show()
      return toggleButton
    end
  end
  return nil
end

local announced = false
local function updateToggleButton()
  if toggleButton and toggleButton:IsShown() and not announced then
    announced = true
    DEFAULT_CHAT_FRAME:AddMessage("|cffd4a84bWoW Forever Builds|r Dungeon Quest helper: use the |cffffffffQuest helper|r button on the group finder, or type |cffffffff/wfb quests|r.")
  end
  if not toggleButton or not toggleButton:IsShown() then return end
  toggleButton:SetText(panel and panel:IsShown() and "Hide helper" or "Quest helper")
end

-- Watching beats hooking here: the finder hides and shows its inner frames when you change tabs, so a
-- one-off OnShow hook only fires the first time. This keeps the panel in step however it is opened.
local watcher = CreateFrame("Frame")
local sinceCheck, sinceRefresh = 0, 0
watcher:SetScript("OnUpdate", function(_, elapsed)
  sinceCheck = sinceCheck + elapsed
  if sinceCheck < 0.25 then return end
  sinceCheck = 0
  -- While the panel is open, re-read the quest log about once a second: quests you hand in or pick
  -- up while it is on screen show up without a reload.
  sinceRefresh = sinceRefresh + 0.25
  if sinceRefresh >= 1 and panel and panel:IsShown() then
    sinceRefresh = 0
    refresh()
  end
  local open = finderOpen()
  if open then
    ensureToggleButton()
    if not panel or not panel:IsShown() then
      if not ns.questPanelDismissed then onFinderShown() end
    end
    updateToggleButton()
  elseif toggleButton and toggleButton:IsShown() then
    toggleButton:Hide()
  end
  if not open and panel and panel:IsShown() then
    hideQuietly()
    -- Closing the finder clears the dismissal, so the panel comes back with the next one you open.
    ns.questPanelDismissed = nil
  end
end)

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("QUEST_LOG_UPDATE")
driver:RegisterEvent("QUEST_ACCEPTED")
driver:RegisterEvent("QUEST_TURNED_IN")
driver:RegisterEvent("QUEST_REMOVED")
driver:RegisterEvent("LFG_UPDATE")
driver:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
driver:RegisterEvent("LFG_PROPOSAL_SHOW")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
driver:SetScript("OnEvent", function(_, event)
  if event == "LFG_UPDATE" or event == "LFG_QUEUE_STATUS_UPDATE" or event == "LFG_PROPOSAL_SHOW" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    -- Queue for a dungeon, or walk into one, and the panel follows it.
    local target = matchDungeon(currentInstance()) or matchDungeon(selectedInFinder())
    if target and target ~= selectedSlug then
      selectedSlug = target
      expandedId = nil
    end
    if panel and panel:IsShown() then refresh() end
  else
    refresh()
  end
end)
