-- The Dungeon Journal: a window that opens beside the group finder for the selected dungeon.
-- Quests are listed on the left; the one you click is shown on the right like a quest log page, with
-- where it starts, what to do, where it is handed in, the chain before it and the rewards.
-- A Bosses tab lists the dungeon's encounters. Data comes from QuestData.lua (generated); nothing
-- here talks to the network.
local _, ns = ...

local PANEL_WIDTH, PANEL_HEIGHT = 860, 590
local LIST_WIDTH = 330
local ROW_WIDTH = LIST_WIDTH - 40
local ROW_HEIGHT = 46
local BODY_TOP = -134

--- 12,450 rather than 12450.
local function groupDigits(value)
  local text = tostring(value or 0)
  local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

local FACTION = UnitFactionGroup and UnitFactionGroup("player") or nil
local MY_SIDE = FACTION == "Horde" and "horde" or FACTION == "Alliance" and "alliance" or nil

local GREY, GOLD, GREEN = "|cff8a8a8a", "|cffffd100", "|cff40d040"
local ALLIANCE_BLUE, HORDE_RED = "|cff6aa9ff", "|cffe06060"
local ORANGE = "|cffff8000"
local SIDE_TAG = { alliance = ALLIANCE_BLUE .. "A|r", horde = HORDE_RED .. "H|r", both = GREY .. "A/H|r" }

-- Journal colours: dark wood for the frame and the list, parchment for the quest page.
local C = {
  window = { 0.09, 0.07, 0.05, 0.97 },
  card = { 0.17, 0.12, 0.08, 1 },
  cardEdge = { 0.52, 0.39, 0.19, 1 },
  pane = { 0.12, 0.09, 0.06, 1 },
  paneEdge = { 0.4, 0.3, 0.15, 1 },
  row = { 0.2, 0.14, 0.09, 1 },
  rowEdge = { 0.42, 0.31, 0.16, 1 },
  picked = { 0.45, 0.3, 0.12, 1 },
  pickedEdge = { 0.95, 0.75, 0.32, 1 },
  parchmentTop = { 0.9, 0.82, 0.64, 1 },
  parchmentBottom = { 0.78, 0.67, 0.47, 1 },
  parchmentEdge = { 0.33, 0.23, 0.11, 1 },
  inkHead = { 0.1, 0.05, 0.01 },
  ink = { 0.22, 0.14, 0.06 },
  inkTitle = { 0.36, 0.18, 0.02 },
  inkSoft = { 0.4, 0.3, 0.18 },
  inkGood = { 0.1, 0.4, 0.08 },
  inkWarn = { 0.6, 0.3, 0.0 },
  rule = { 0.45, 0.33, 0.18, 0.7 },
}

local CREST = {
  alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
  horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
}
local ICON = {
  available = "Interface\\GossipFrame\\AvailableQuestIcon",
  turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
  done = "Interface\\RaidFrame\\ReadyCheck-Ready",
  boss = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
}
-- Which step of a quest happens inside the dungeon, for the Notes section.
local INSIDE_NOTE = {
  given = "Given inside the dungeon.",
  drop = "Starts from an item that drops inside the dungeon.",
  turnin = "Handed in inside the dungeon.",
  ["do"] = "Done inside the dungeon.",
  entrance = "Picked up at the dungeon entrance.",
}

local panel, dropdown, detail
local rows = {}
local selectedSlug, selectedQuestId, selectedBoss
local mode = "quests"
-- Whose quests the list shows; both-faction quests are always in it.
local viewSide = MY_SIDE or "alliance"

local function say(text)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffd4a84bWoW Forever Builds|r " .. text) end
end

local function dungeonBySlug(slug)
  for _, dungeon in ipairs(ns.dungeons) do
    if dungeon.slug == slug then return dungeon end
  end
end

local function canTake(quest)
  return quest.side == "both" or MY_SIDE == nil or quest.side == MY_SIDE
end

--- Every quest of this dungeon, chain members kept together.
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

--- "done", "active", "turnin" or nil for a quest we only know by name.
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

--- "done", "turnin", "active" or "todo".
local function statusOf(quest)
  if isCompleted(quest.id) then return "done" end
  if readyForTurnIn(quest.id) then return "turnin" end
  if inLog(quest.id) then return "active" end
  return "todo"
end

--- Where the quest starts for the faction the journal is showing.
local function whereFor(quest)
  if viewSide == "horde" then return quest.whereH or quest.whereA end
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

local SITE = "https://wowforeverbuilds.com"

--- The quest's page on the site; Classic-only quests have no page, so they get the quest list.
local function questUrl(quest)
  if quest.slug then return SITE .. "/quests/" .. quest.slug end
  return SITE .. "/quests"
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

local function selectDungeon(slug)
  if slug == selectedSlug then return end
  selectedSlug = slug
  selectedQuestId, selectedBoss = nil, nil
  if detail then detail.scroll:SetVerticalScroll(0) end
end

--- The game's own link for the quest. The server drops a link whose level or title does not match
--- its data and sends plain text instead, so a hand-built one is only the last resort.
local function questLink(quest)
  if C_QuestLog and C_QuestLog.GetQuestLink then
    local ok, link = pcall(C_QuestLog.GetQuestLink, quest.id)
    if ok and type(link) == "string" and link ~= "" then return link end
  end
  if type(GetQuestLink) == "function" then
    local ok, link = pcall(GetQuestLink, quest.id)
    if ok and type(link) == "string" and link ~= "" then return link end
    -- Older clients take a quest log index, so this works for quests you are on.
    if type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function" then
      for index = 1, GetNumQuestLogEntries() do
        local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
        if not isHeader and questID == quest.id then
          ok, link = pcall(GetQuestLink, index)
          if ok and type(link) == "string" and link ~= "" then return link end
        end
      end
    end
  end
  -- The Forever client's own quest log links carry level 0 ("|Hquest:5041:0|h"); a real level makes
  -- the server strip the link. The colour is the quest's difficulty for you, as the quest log gives it.
  local colour = "ffffff00"
  if type(GetQuestDifficultyColor) == "function" and quest.level then
    local ok, c = pcall(GetQuestDifficultyColor, quest.level)
    if ok and type(c) == "table" and c.r then
      colour = ("ff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
    end
  end
  return ("|c%s|Hquest:%d:0|h[%s]|h|r"):format(colour, quest.id, quest.title)
end

local function insertInChat(text)
  if ChatEdit_InsertLink and ChatEdit_InsertLink(text) then return end
  if ChatFrame_OpenChat then ChatFrame_OpenChat(text) end
end

--- A clickable quest link in the chat box, like shift-clicking in the quest log, or the quest's web
--- address when it is not in your log.
local function linkInChat(quest)
  -- The server only lets a quest link through for a quest in your log; anything else arrives as
  -- plain text. Those get the name in brackets and the quest's web address instead.
  if inLog(quest.id) then return insertInChat(questLink(quest)) end
  insertInChat("[" .. quest.title .. "] " .. questUrl(quest):gsub("^https://", ""))
end

--- A small box with a web address, selected for Ctrl+C.
local copyBox
local function showCopyBox(label, url)
  if not copyBox then
    local f = CreateFrame("Frame", "WoWForeverBuildsQuestLink", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
    f:SetSize(460, 96)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    tinsert(UISpecialFrames, "WoWForeverBuildsQuestLink")
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOPLEFT", 20, -18)
    f.label:SetPoint("TOPRIGHT", -20, -18)
    f.label:SetJustifyH("LEFT")
    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", 24, -44)
    box:SetPoint("TOPRIGHT", -20, -44)
    box:SetHeight(24)
    box:SetAutoFocus(true)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    box:SetScript("OnEnterPressed", function() f:Hide() end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- Read-only: typing puts the address back.
    box:SetScript("OnTextChanged", function(self, userInput)
      if userInput then
        self:SetText(f.url or "")
        self:HighlightText()
      end
    end)
    f.box = box
    copyBox = f
  end
  copyBox.url = url
  copyBox.label:SetText(GOLD .. label .. "|r  " .. GREY .. "Ctrl+C to copy, Esc to close|r")
  copyBox:ClearAllPoints()
  copyBox:SetPoint("TOP", panel, "TOP", 0, -40)
  copyBox:Show()
  copyBox.box:SetText(url)
  copyBox.box:SetCursorPosition(0)
  copyBox.box:SetFocus()
  copyBox.box:HighlightText()
end

-- Show on Map -------------------------------------------------------------------------------------

--- Where the quest starts (or, with turnIn, where it is handed in), for the faction on view.
--- An NPC position the beta has seen gives an exact spot; prep notes give a zone and sometimes a
--- spot; quests that start inside, or that we have no place for, fall back to the dungeon's zone.
local function mapSpotFor(quest, dungeon, turnIn)
  if turnIn then return quest.turnInAt, false end
  if quest.startAt then return quest.startAt, false end
  local inside = quest.inside == "given" or quest.inside == "drop" or quest.spot == "Inside" or quest.spot == "Drops inside"
  if not inside then
    local spot
    if viewSide == "horde" then spot = quest.mapH or quest.mapA else spot = quest.mapA or quest.mapH end
    if spot then return spot, false end
  end
  if dungeon.zone then return { zone = dungeon.zone }, true end
  return nil
end

local function openMapAt(id)
  if not WorldMapFrame then return end
  if not WorldMapFrame:IsShown() then
    if type(OpenWorldMap) == "function" then
      pcall(OpenWorldMap, id)
    elseif type(ToggleWorldMap) == "function" then
      pcall(ToggleWorldMap)
    end
  end
  if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, id) end
end

local function showOnMap(quest, dungeon, turnIn)
  local spot, isDungeonZone = mapSpotFor(quest, dungeon, turnIn)
  if not spot then
    say(("%s: no map spot in our data yet."):format(quest.title))
    return
  end
  local id = ns.MapIdForZone and ns.MapIdForZone(spot.zone)
  if not id then
    say(("%s: %s (that map was not found in this client)."):format(quest.title, spot.zone))
    return
  end
  local who = turnIn and quest.turnIn or quest.from
  local heading = ("%s: %s"):format(quest.title, turnIn and "hand in" or "pick up")
  if spot.x then
    -- Our own pin on the world map always works; TomTom or the game's waypoint add an arrow when present.
    if ns.SetQuestPin then ns.SetQuestPin(spot, heading, who and (who .. (spot.place and (", " .. spot.place) or "")) or spot.place) end
    local placed = false
    if TomTom and TomTom.AddWaypoint and (not ns.Option or ns.Option("routeTomTom", true)) then
      placed = pcall(TomTom.AddWaypoint, TomTom, id, spot.x / 100, spot.y / 100, { title = heading, persistent = false, minimap = true, world = true })
    end
    if not placed and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
      if pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(id, spot.x / 100, spot.y / 100)) and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
      end
    end
  end
  openMapAt(id)
  if spot.x then
    say(("%s — map pin at %s %.1f, %.1f%s."):format(heading, spot.zone, spot.x, spot.y, who and (" (" .. who .. ")") or ""))
  elseif isDungeonZone then
    say(("%s: no pick-up spot in our data, so the map shows the dungeon's zone, %s."):format(quest.title, spot.zone))
  else
    say(("%s: starts in %s. Our notes give no exact spot yet, so the map shows the zone."):format(quest.title, spot.zone))
  end
end

-- Experience --------------------------------------------------------------------------------------

local function maxLevel()
  if type(GetMaxPlayerLevel) == "function" then
    local ok, level = pcall(GetMaxPlayerLevel)
    if ok and type(level) == "number" then return level end
  end
  return nil
end

--- The XP this character gets for the quest, by the game's own rule: full up to 5 levels above the
--- quest, then 80%, 60%, 40%, 20% and finally 10%, rounded the way the server rounds; nothing at the
--- level cap. Returns the amount and whether it is cut.
local function xpFor(quest)
  local base = quest.xp
  if not base then return nil, false end
  local level = UnitLevel and UnitLevel("player") or nil
  if not level or not quest.level then return base, false end
  local cap = maxLevel()
  if cap and level >= cap then return 0, true end
  local diff = level - quest.level
  local multiplier = diff <= 5 and 10 or diff == 6 and 8 or diff == 7 and 6 or diff == 8 and 4 or diff == 9 and 2 or 1
  if multiplier == 10 then return base, false end
  local xp = math.floor(base * multiplier / 10)
  if xp <= 100 then
    xp = 5 * math.floor((xp + 2) / 5)
  elseif xp <= 500 then
    xp = 10 * math.floor((xp + 5) / 10)
  elseif xp <= 1000 then
    xp = 25 * math.floor((xp + 12) / 25)
  else
    xp = 50 * math.floor((xp + 25) / 50)
  end
  return xp, true
end

-- Drawing helpers ---------------------------------------------------------------------------------

--- A flat fill with a thin edge, so frames look the same on every client without extra art.
local function paint(frame, fill, edge, size)
  frame.fill = frame:CreateTexture(nil, "BACKGROUND")
  frame.fill:SetAllPoints()
  frame.fill:SetColorTexture(unpack(fill))
  frame.edges = {}
  if not edge then return end
  size = size or 1
  local function line(a, b, horizontal)
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetColorTexture(unpack(edge))
    t:SetPoint(a)
    t:SetPoint(b)
    if horizontal then t:SetHeight(size) else t:SetWidth(size) end
    frame.edges[#frame.edges + 1] = t
  end
  line("TOPLEFT", "TOPRIGHT", true)
  line("BOTTOMLEFT", "BOTTOMRIGHT", true)
  line("TOPLEFT", "BOTTOMLEFT")
  line("TOPRIGHT", "BOTTOMRIGHT")
end

local function recolour(frame, fill, edge)
  frame.fill:SetColorTexture(unpack(fill))
  for _, t in ipairs(frame.edges) do t:SetColorTexture(unpack(edge)) end
end

--- Parchment runs light to dark from top to bottom where the client can blend; flat otherwise.
local function parchment(texture)
  texture:SetColorTexture(1, 1, 1, 1)
  local ok = texture.SetGradient and CreateColor and pcall(texture.SetGradient, texture, "VERTICAL",
    CreateColor(unpack(C.parchmentBottom)), CreateColor(unpack(C.parchmentTop)))
  if not ok then texture:SetColorTexture(unpack(C.parchmentTop)) end
end

local function fontObject(name) return _G[name] or GameFontNormal end

local function crestOn(texture, side)
  texture:SetTexture(CREST[side])
  texture:SetTexCoord(0, 0.625, 0, 0.625)
end

--- One or two crests for a quest's faction, right-aligned at the anchor.
local function showCrests(a, b, side, point, relative, relPoint, x, y)
  a:ClearAllPoints()
  a:SetPoint(point, relative, relPoint, x, y)
  if side == "both" then
    crestOn(a, "horde")
    crestOn(b, "alliance")
    b:ClearAllPoints()
    b:SetPoint("RIGHT", a, "LEFT", 2, 0)
    a:Show()
    b:Show()
  elseif CREST[side] then
    crestOn(a, side)
    a:Show()
    b:Hide()
  else
    a:Hide()
    b:Hide()
  end
end

-- Detail page (parchment) -------------------------------------------------------------------------

local function resetDetail()
  detail.used, detail.y = 0, 0
  for _, text in ipairs(detail.pool) do text:Hide() end
  for _, button in ipairs(detail.rewards) do button:Hide() end
  for _, rule in ipairs(detail.rules) do rule:Hide() end
  detail.rulesUsed = 0
  for _, button in pairs(detail.buttons) do button:Hide() end
  detail.crestA:Hide()
  detail.crestB:Hide()
end

local function detailString(font, colour, width)
  detail.used = detail.used + 1
  local text = detail.pool[detail.used]
  if not text then
    text = detail.content:CreateFontString(nil, "ARTWORK")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    detail.pool[detail.used] = text
  end
  text:SetFontObject(fontObject(font))
  text:SetTextColor(unpack(colour))
  text:SetShadowOffset(0, 0)
  text:SetSpacing(2)
  text:SetWidth(width or detail.width)
  text:ClearAllPoints()
  text:Show()
  return text
end

--- Puts a region at the running y and moves y past it.
local function place(region, gap, x)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", detail.content, "TOPLEFT", x or 0, -detail.y)
  local height = region.GetStringHeight and region:GetStringHeight() or region:GetHeight()
  detail.y = detail.y + height + (gap or 0)
end

local function rule(gap)
  detail.rulesUsed = detail.rulesUsed + 1
  local line = detail.rules[detail.rulesUsed]
  if not line then
    line = detail.content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(C.rule))
    line:SetHeight(1)
    detail.rules[detail.rulesUsed] = line
  end
  line:SetWidth(detail.width)
  line:Show()
  place(line, gap or 10)
end

local function heading(text, font, colour)
  local h = detailString(font or "GameFontNormal", colour or C.inkHead)
  h:SetText(text)
  place(h, 3)
end

local function body(text, colour, gap)
  local b = detailString("GameFontHighlight", colour or C.ink)
  b:SetText(text)
  place(b, gap or 10)
end

local function section(title, text)
  if not text or text == "" then return end
  heading(title)
  body(text)
end

local function itemIcon(item)
  local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
  if getIcon then
    local ok, icon = pcall(getIcon, item.id)
    if ok and icon then return icon end
  end
  if item.icon then return "Interface\\Icons\\" .. item.icon end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function qualityColour(q)
  local colours = ITEM_QUALITY_COLORS
  local c = colours and colours[q or 1]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

local function rewardButton(index)
  local button = detail.rewards[index]
  if button then return button end
  button = CreateFrame("Button", nil, detail.content)
  button:SetSize(math.floor((detail.width - 8) / 2), 40)
  paint(button, { 0.16, 0.11, 0.07, 0.92 }, { 0.3, 0.2, 0.09, 1 })
  local hl = button:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.85, 0.5, 0.12)
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetSize(34, 34)
  button.icon:SetPoint("LEFT", 3, 0)
  button.name = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  button.name:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
  button.name:SetPoint("RIGHT", -4, 0)
  button.name:SetJustifyH("LEFT")
  button:SetScript("OnEnter", function(self)
    if not self.item or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item.id) then
      GameTooltip:SetText(self.item.name)
    end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- Shift-click links the item in chat, like any reward in the quest log.
  button:SetScript("OnClick", function(self)
    if not self.item or not IsShiftKeyDown() then return end
    local link
    if type(GetItemInfo) == "function" then
      local ok, _, itemLink = pcall(GetItemInfo, self.item.id)
      if ok then link = itemLink end
    end
    insertInChat(link or ("[" .. self.item.name .. "]"))
  end)
  detail.rewards[index] = button
  return button
end

--- Items two to a row, like the quest log's reward grid. Returns the next free button index.
local function rewardGrid(items, first)
  local index = first
  for i, item in ipairs(items) do
    local button = rewardButton(index)
    button.item = item
    button.icon:SetTexture(itemIcon(item))
    button.name:SetText(item.name)
    button.name:SetTextColor(qualityColour(item.q))
    button:ClearAllPoints()
    local column = (i - 1) % 2
    button:SetPoint("TOPLEFT", detail.content, "TOPLEFT", column * (button:GetWidth() + 8), -detail.y)
    button:Show()
    if column == 1 or i == #items then detail.y = detail.y + 46 end
    index = index + 1
  end
  detail.y = detail.y + 6
  return index
end

local function detailButton(key, label, width, onClick)
  local button = detail.buttons[key]
  if not button then
    button = CreateFrame("Button", nil, detail.content, "UIPanelButtonTemplate")
    button:SetHeight(22)
    detail.buttons[key] = button
  end
  button:SetText(label)
  button:SetWidth(width)
  button:SetScript("OnClick", onClick)
  button:Show()
  return button
end

local STATUS_LINE = {
  active = { "In your quest log", C.inkWarn },
  turnin = { "Ready to turn in", C.inkGood },
  done = { "Completed", C.inkSoft },
}

local function renderQuest(quest, dungeon)
  resetDetail()
  local title = detailString("QuestTitleFont", C.inkTitle)
  title:SetText(quest.title)
  place(title, 4)

  local levels = ("Available from Level %d"):format(quest.req or quest.level)
  if quest.level and quest.level ~= quest.req then levels = levels .. ("   ·   Quest level %d"):format(quest.level) end
  local avail = detailString("GameFontHighlightSmall", C.inkSoft)
  avail:SetText(levels)
  place(avail, 8)
  showCrests(detail.crestB, detail.crestA, quest.side, "LEFT", avail, "LEFT", avail:GetStringWidth() + (quest.side == "both" and 34 or 8), 0)
  rule(10)

  local status = statusOf(quest)
  if STATUS_LINE[status] then
    local line = detailString("GameFontNormal", STATUS_LINE[status][2])
    line:SetText(STATUS_LINE[status][1])
    place(line, 10)
  end

  -- Objective: the summary, then each thing to kill or collect.
  local objective = quest.goal or ""
  if quest.obj and #quest.obj > 0 then
    local parts = {}
    -- The summary often repeats the only objective word for word; list it once.
    for _, entry in ipairs(quest.obj) do
      if entry ~= quest.goal then parts[#parts + 1] = "- " .. entry end
    end
    if #parts > 0 then objective = objective .. (objective ~= "" and "\n" or "") .. table.concat(parts, "\n") end
  end
  section("Objective", objective)

  -- "Tabitha Heartweaver — Silverpine Forest, The Sepulcher (44.5, 43.0)" when the beta has seen them.
  local function npcLine(name, spot)
    if not spot or not spot.x then return name end
    return ("%s — %s (%.1f, %.1f)"):format(name or "", spot.place or spot.zone, spot.x, spot.y)
  end

  -- Starts at: the quest giver, then the site's note on where to find them.
  local starts = {}
  if quest.item then
    starts[#starts + 1] = "Loot " .. quest.item .. " inside the dungeon. It starts the quest and cannot be shared."
  elseif quest.from then
    starts[#starts + 1] = npcLine(quest.from, quest.startAt)
  end
  local where = whereFor(quest)
  if where and where ~= quest.from then starts[#starts + 1] = where end
  if #starts == 0 and quest.spot then starts[#starts + 1] = quest.spot end
  if #starts == 0 then starts[#starts + 1] = "Picked up at the dungeon." end
  heading("Starts at")
  body(table.concat(starts, "\n"), nil, 6)
  -- An exact spot gets a pin; without one the button only opens the zone, and says so.
  local startSpot = mapSpotFor(quest, dungeon)
  local mapButton = detailButton("map", startSpot and startSpot.x and "Show on Map" or "Show zone", 120, function() showOnMap(quest, dungeon) end)
  place(mapButton, 12)

  if quest.turnIn then
    heading("Turn in")
    body(npcLine(quest.turnIn, quest.turnInAt), nil, quest.turnInAt and 6 or 10)
    if quest.turnInAt then
      local turnInButton = detailButton("turnin", "Show on Map", 120, function() showOnMap(quest, dungeon, true) end)
      place(turnInButton, 12)
    end
  end

  -- Notes: what happens inside, sharing, class and data caveats.
  local notes = {}
  if quest.note then notes[#notes + 1] = quest.note end
  if quest.inside and INSIDE_NOTE[quest.inside] and not quest.note then notes[#notes + 1] = INSIDE_NOTE[quest.inside] end
  if quest.needs then
    local unlocked = quest.needsId and isCompleted(quest.needsId)
    notes[#notes + 1] = unlocked and ("Unlocked: you have done " .. quest.needs .. ".") or ("Needs " .. quest.needs .. " first, so it cannot be shared with players who skipped it.")
  elseif not quest.item then
    notes[#notes + 1] = "Can be shared with your group."
  end
  if quest.only then notes[#notes + 1] = quest.only .. " only." end
  if quest.side ~= "both" and MY_SIDE and quest.side ~= MY_SIDE then
    notes[#notes + 1] = (quest.side == "horde" and "Horde" or "Alliance") .. " quest: your character cannot take it."
  end
  if quest.classic then notes[#notes + 1] = "From the Classic quest list; not seen on the Forever beta yet." end
  section("Notes", table.concat(notes, "\n"))

  -- The questline before this one when it is written in, then the chain the client data knows.
  local chainLines = {}
  if quest.pre then
    local reached = 0
    local states = {}
    for index, line in ipairs(quest.pre) do
      states[index] = statusByName(line:match("^(.-)%s*%(") or line)
      if states[index] then reached = index end
    end
    if quest.needsId and isCompleted(quest.needsId) then reached = #quest.pre + 1 end
    for index, line in ipairs(quest.pre) do
      local state = states[index] or (index < reached and "done") or nil
      local mark = state == "done" and "[x]" or (state == "active" or state == "turnin") and "[~]" or "[  ]"
      chainLines[#chainLines + 1] = ("%s %s"):format(mark, line)
    end
  end
  local chain = chainOf(quest)
  if chain then
    for index, step in ipairs(chain) do
      local mark, name, suffix = "[  ]", step.name or "?", ""
      if step.quest then
        name = step.quest.title
        if isCompleted(step.quest.id) then
          mark = "[x]"
        elseif inLog(step.quest.id) then
          mark = "[~]"
        end
        if step.quest.id == quest.id then suffix = "   < this quest" end
        if step.dungeon and step.dungeon.slug ~= selectedSlug then suffix = suffix .. "   (" .. step.dungeon.name .. ")" end
      else
        suffix = "   (outside this dungeon)"
      end
      chainLines[#chainLines + 1] = ("%d. %s %s%s"):format(index, mark, name, suffix)
    end
  end
  if #chainLines > 0 then section(quest.pre and "Before you can take it" or "Quest chain", table.concat(chainLines, "\n")) end

  -- Rewards, in the quest log's order: the choice, the fixed items, then XP, money and reputation.
  local nextButton = 1
  if quest.choice and #quest.choice > 0 then
    heading(#quest.choice > 1 and "Choose one reward" or "You will receive", "QuestTitleFont", C.inkTitle)
    detail.y = detail.y + 4
    nextButton = rewardGrid(quest.choice, nextButton)
  end
  if quest.items and #quest.items > 0 then
    heading(quest.choice and "You will also receive" or "You will receive", "QuestTitleFont", C.inkTitle)
    detail.y = detail.y + 4
    nextButton = rewardGrid(quest.items, nextButton)
  end
  local extras = {}
  -- XP for this character at its current level; the full amount is shown beside it when it is cut.
  local xp, cut = xpFor(quest)
  if xp then
    if cut and xp == 0 then
      extras[#extras + 1] = "No XP at the level cap"
    elseif cut then
      extras[#extras + 1] = ("%s XP for you (full %s)"):format(groupDigits(xp), groupDigits(quest.xp))
    else
      extras[#extras + 1] = groupDigits(xp) .. " XP"
    end
  end
  if quest.money then extras[#extras + 1] = quest.money end
  if quest.rep then
    for _, line in ipairs(quest.rep) do extras[#extras + 1] = line end
  end
  if #extras > 0 then
    if not quest.choice and not quest.items then heading("Rewards", "QuestTitleFont", C.inkTitle) end
    body(table.concat(extras, "   ·   "), C.ink, 2)
    if quest.xp then
      local source = (quest.classic or dungeon.classic) and "XP from the Classic quest list." or "XP from the beta client's quest data."
      body(source .. (" Full until level %d, then less for every level above that."):format(quest.level + 5), C.inkSoft, 10)
    end
  end

  rule(10)
  local chatButton = detailButton("chat", "Link in chat", 120, function() linkInChat(quest) end)
  local webButton = detailButton("web", "Copy web link", 120, function() showCopyBox(quest.title, questUrl(quest)) end)
  place(chatButton, 0)
  webButton:ClearAllPoints()
  webButton:SetPoint("LEFT", chatButton, "RIGHT", 8, 0)
  detail.y = detail.y + 8
  local hint = detailString("GameFontHighlightSmall", C.inkSoft)
  hint:SetText("Shift-click a reward to link it. Outside your quest log, the chat link is the quest's web address.")
  place(hint, 10)
  detail.content:SetHeight(math.max(detail.y, 1))
end

--- Quests of this dungeon whose goal names the boss.
local function questsForBoss(dungeon, boss)
  local names = {}
  local lower = boss:lower()
  for _, quest in ipairs(dungeon) do
    local text = ((quest.goal or "") .. " " .. table.concat(quest.obj or {}, " ")):lower()
    if text:find(lower, 1, true) then names[#names + 1] = quest.title end
  end
  return names
end

local function renderBoss(dungeon)
  resetDetail()
  local bosses = dungeon.bosses or {}
  local boss = bosses[selectedBoss or 1]
  if not boss then
    local title = detailString("QuestTitleFont", C.inkTitle)
    title:SetText(dungeon.name)
    place(title, 8)
    rule(10)
    body("No boss list for this dungeon yet. The beta has not shown its encounters.", C.ink)
  else
    local title = detailString("QuestTitleFont", C.inkTitle)
    title:SetText(boss)
    place(title, 4)
    local sub = detailString("GameFontHighlightSmall", C.inkSoft)
    sub:SetText(dungeon.bossesFrom == "beta" and "Encounter from the Forever beta client data" or ("Boss %d of %d in the Classic dungeon"):format(selectedBoss or 1, #bosses))
    place(sub, 8)
    rule(10)
    local quests = questsForBoss(dungeon, boss)
    if #quests > 0 then section("Quests that need this boss", table.concat(quests, "\n")) end
  end
  local facts = { ("Level %d-%d"):format(dungeon.min, dungeon.max) }
  if dungeon.zone then facts[#facts + 1] = "entrance in " .. dungeon.zone end
  section("Dungeon", table.concat(facts, ", ") .. ".")
  if dungeon.mobs then section("Enemies inside", "Level " .. dungeon.mobs .. ".") end
  if dungeon.boss then section("Last boss", dungeon.boss .. ".") end
  if dungeon.bossesFrom == "classic" then
    section("About this list", "The main bosses of the Classic version of this dungeon, as a reference. WoW Forever may change them.")
  elseif dungeon.bossesFrom == "beta" then
    section("About this list", "Encounter names found in the Forever beta client's data. The order is not confirmed.")
  end
  rule(10)
  local webButton = detailButton("web", "Dungeon guide", 130, function() showCopyBox(dungeon.name, SITE .. "/dungeons/" .. dungeon.slug) end)
  place(webButton, 10)
  detail.content:SetHeight(math.max(detail.y, 1))
end

-- Quest and boss list -----------------------------------------------------------------------------

local function buildRow(index)
  local row = CreateFrame("Button", nil, panel.listContent)
  row:SetSize(ROW_WIDTH, ROW_HEIGHT)
  paint(row, C.row, C.rowEdge)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.85, 0.5, 0.08)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(22, 22)
  row.icon:SetPoint("LEFT", 7, 0)

  row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  row.title:SetPoint("TOPLEFT", 36, -8)
  row.title:SetWidth(ROW_WIDTH - 36 - 84)
  row.title:SetJustifyH("LEFT")
  row.title:SetWordWrap(false)

  row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.sub:SetPoint("TOPLEFT", 36, -26)
  row.sub:SetWidth(ROW_WIDTH - 36 - 50)
  row.sub:SetJustifyH("LEFT")
  row.sub:SetWordWrap(false)
  row.sub:SetTextColor(0.86, 0.8, 0.68)

  row.tag = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  row.tag:SetPoint("TOPRIGHT", -6, -5)
  row.tag:SetJustifyH("RIGHT")

  row.crestA = row:CreateTexture(nil, "ARTWORK")
  row.crestA:SetSize(22, 22)
  row.crestB = row:CreateTexture(nil, "ARTWORK")
  row.crestB:SetSize(22, 22)

  row:SetScript("OnClick", function(self)
    if self.boss then
      selectedBoss = self.boss
    elseif self.quest then
      if IsShiftKeyDown() then return linkInChat(self.quest) end
      if IsControlKeyDown() then return showCopyBox(self.quest.title, questUrl(self.quest)) end
      selectedQuestId = self.quest.id
    end
    detail.scroll:SetVerticalScroll(0)
    refresh()
  end)
  rows[index] = row
  return row
end

local function layoutRow(row, index)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", panel.listContent, "TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + 5))
  row:Show()
end

local TAG = {
  active = GOLD .. "YOU HAVE IT|r",
  turnin = GREEN .. "TURN IN|r",
  done = GREY .. "DONE|r",
}

--- Quests the list shows for the faction on view: open ones first, finished ones at the bottom.
local function visibleQuests(dungeon)
  local open, finished = {}, {}
  for _, quest in ipairs(questsFor(dungeon)) do
    if quest.side == "both" or quest.side == viewSide then
      if isCompleted(quest.id) then finished[#finished + 1] = quest else open[#open + 1] = quest end
    end
  end
  for _, quest in ipairs(finished) do open[#open + 1] = quest end
  return open
end

local function renderQuestList(dungeon)
  local list = visibleQuests(dungeon)
  panel.listTitle:SetText(("Quests  |  %d"):format(#list))

  local picked
  for _, quest in ipairs(list) do
    if quest.id == selectedQuestId then picked = quest end
  end
  -- Nothing picked yet: the first quest you are on, else the first open one.
  if not picked then
    for _, quest in ipairs(list) do
      if not picked and inLog(quest.id) then picked = quest end
    end
    picked = picked or list[1]
    selectedQuestId = picked and picked.id or nil
  end

  -- The page is only redrawn when something on it can have changed, so a reward tooltip stays up
  -- through the once-a-second refresh.
  local keyParts = { "quests", selectedSlug, viewSide, tostring(selectedQuestId), tostring(UnitLevel and UnitLevel("player")) }
  for i, quest in ipairs(list) do
    local row = rows[i] or buildRow(i)
    row.quest, row.boss = quest, nil
    local status = statusOf(quest)
    keyParts[#keyParts + 1] = status
    row.title:SetText(quest.title)
    if status == "done" then
      row.title:SetTextColor(0.6, 0.6, 0.6)
    else
      row.title:SetTextColor(1, 0.82, 0)
    end
    local sub = ("Available from Level %d"):format(quest.req or quest.level)
    if quest.step and quest.of and quest.of > 1 then sub = sub .. ("  ·  step %d/%d"):format(quest.step, quest.of) end
    row.sub:SetText(sub)
    local tag = TAG[status]
    if not tag and (quest.pre or (quest.needs and not (quest.needsId and isCompleted(quest.needsId)))) then tag = ORANGE .. "PRE-QUEST|r" end
    row.tag:SetText(tag or "")
    row.icon:SetTexture(status == "turnin" and ICON.turnin or status == "done" and ICON.done or ICON.available)
    row.icon:SetDesaturated(false)
    row.icon:SetVertexColor(1, 1, 1)
    if status == "active" then row.icon:SetVertexColor(1, 0.95, 0.6) end
    showCrests(row.crestA, row.crestB, quest.side, "BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 4)
    if quest.id == selectedQuestId then recolour(row, C.picked, C.pickedEdge) else recolour(row, C.row, C.rowEdge) end
    row:SetAlpha(status == "done" and quest.id ~= selectedQuestId and 0.6 or 1)
    layoutRow(row, i)
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  panel.listContent:SetHeight(math.max(#list * (ROW_HEIGHT + 5), 1))

  if #list == 0 then
    local other = viewSide == "horde" and "Alliance" or "Horde"
    panel.empty:SetText(("No %s quests in this dungeon.\nClick the %s crest above to see theirs."):format(viewSide == "horde" and "Horde" or "Alliance", other))
    panel.empty:Show()
  else
    panel.empty:Hide()
  end

  local key = table.concat(keyParts, ":")
  if key == detail.key then return end
  detail.key = key
  if picked then
    renderQuest(picked, dungeon)
  else
    resetDetail()
    detail.content:SetHeight(1)
  end
end

local function renderBossList(dungeon)
  local bosses = dungeon.bosses or {}
  panel.listTitle:SetText(("Bosses  |  %d"):format(#bosses))
  if not selectedBoss or selectedBoss > #bosses then selectedBoss = 1 end
  for i, boss in ipairs(bosses) do
    local row = rows[i] or buildRow(i)
    row.quest, row.boss = nil, i
    row.title:SetText(boss)
    row.title:SetTextColor(1, 0.82, 0)
    row.sub:SetText(dungeon.bossesFrom == "beta" and "Beta encounter" or ("Boss %d"):format(i))
    row.tag:SetText("")
    row.icon:SetTexture(ICON.boss)
    row.icon:SetVertexColor(1, 1, 1)
    row.crestA:Hide()
    row.crestB:Hide()
    if i == selectedBoss then recolour(row, C.picked, C.pickedEdge) else recolour(row, C.row, C.rowEdge) end
    row:SetAlpha(1)
    layoutRow(row, i)
  end
  for i = #bosses + 1, #rows do rows[i]:Hide() end
  panel.listContent:SetHeight(math.max(#bosses * (ROW_HEIGHT + 5), 1))
  if #bosses == 0 then
    panel.empty:SetText("No boss list for this dungeon yet.")
    panel.empty:Show()
  else
    panel.empty:Hide()
  end
  local key = ("bosses:%s:%d"):format(selectedSlug, selectedBoss)
  if key == detail.key then return end
  detail.key = key
  renderBoss(dungeon)
end

local function updateTabs()
  local quests = mode == "quests"
  -- The open tab is the pressed (dark) one, like the mockup's Quests button.
  if quests then panel.questTab:Disable() else panel.questTab:Enable() end
  if quests then panel.bossTab:Enable() else panel.bossTab:Disable() end
  for side, button in pairs(panel.factionButtons) do
    button:SetShown(quests)
    local on = side == viewSide
    recolour(button, on and C.picked or C.pane, on and C.pickedEdge or C.paneEdge)
    button.crest:SetDesaturated(not on)
    button.crest:SetAlpha(on and 1 or 0.55)
  end
end

refresh = function()
  if not panel or not panel:IsShown() then return end
  local dungeon = dungeonBySlug(selectedSlug)
  if not dungeon then return end

  panel.name:SetText(dungeon.name)
  local line = ("LV %d-%d"):format(dungeon.min, dungeon.max)
  if dungeon.zone then line = line .. "   |   " .. dungeon.zone end
  if dungeon.side == "alliance" then
    line = line .. "   " .. ALLIANCE_BLUE .. "Mostly Alliance|r"
  elseif dungeon.side == "horde" then
    line = line .. "   " .. HORDE_RED .. "Mostly Horde|r"
  end
  panel.place:SetText(line)
  -- Dungeons the beta has not shown yet fall back to the Classic quest list, which may differ.
  panel.source:SetText(dungeon.classic and (ORANGE .. "Classic list, not seen on the beta yet|r") or (GREY .. "Forever beta data|r"))

  -- Progress over the quests your character can take.
  local done, mine, inLogCount, leftXp = 0, 0, 0, 0
  for _, quest in ipairs(dungeon) do
    if canTake(quest) then
      mine = mine + 1
      if isCompleted(quest.id) then
        done = done + 1
      else
        leftXp = leftXp + (xpFor(quest) or 0)
        if inLog(quest.id) then inLogCount = inLogCount + 1 end
      end
    end
  end
  panel.progress:SetText(("%d of %d done  ·  %d in your log  ·  %s XP to earn at your level"):format(done, mine, inLogCount, groupDigits(leftXp)))

  updateTabs()
  if mode == "bosses" then renderBossList(dungeon) else renderQuestList(dungeon) end
end

-- Window ------------------------------------------------------------------------------------------

local function buildDropdown(anchor)
  if not UIDropDownMenu_Initialize then return end
  local ok, frame = pcall(CreateFrame, "Frame", "WoWForeverBuildsQuestDropdown", panel, "UIDropDownMenuTemplate")
  if not ok or not frame then return end
  dropdown = frame
  dropdown:Hide()
  UIDropDownMenu_Initialize(dropdown, function()
    for _, dungeon in ipairs(ns.dungeons) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = ("%s (%d-%d) %s"):format(dungeon.name, dungeon.min, dungeon.max, SIDE_TAG[dungeon.side or "both"] or "")
      info.checked = dungeon.slug == selectedSlug
      info.func = function()
        selectDungeon(dungeon.slug)
        CloseDropDownMenus()
        refresh()
      end
      UIDropDownMenu_AddButton(info)
    end
  end, "MENU")
  anchor:SetScript("OnClick", function(self) ToggleDropDownMenu(1, nil, dropdown, self, 0, 0) end)
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
  panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
  panel:SetPoint("CENTER")
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetFrameStrata("HIGH")
  panel:Hide()
  if panel.TitleText then panel.TitleText:SetText("Dungeon Journal") end

  local backing = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
  backing:SetPoint("TOPLEFT", 6, -26)
  backing:SetPoint("BOTTOMRIGHT", -6, 6)
  backing:SetColorTexture(unpack(C.window))

  panel.source = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.source:SetPoint("TOPRIGHT", -34, -6)

  -- Dungeon picker, top left.
  local picker = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  picker:SetSize(118, 22)
  picker:SetPoint("TOPLEFT", 14, -32)
  picker:SetText("Dungeons")
  buildDropdown(picker)

  -- Header card: dungeon name, level and zone; tabs and progress on the right.
  local card = CreateFrame("Frame", nil, panel)
  card:SetPoint("TOPLEFT", 12, -60)
  card:SetPoint("TOPRIGHT", -12, -60)
  card:SetHeight(64)
  paint(card, C.card, C.cardEdge)
  panel.name = card:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  panel.name:SetPoint("TOPLEFT", 14, -10)
  panel.name:SetJustifyH("LEFT")
  panel.place = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  panel.place:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -6)
  panel.place:SetTextColor(0.86, 0.8, 0.68)

  panel.questTab = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
  panel.questTab:SetSize(100, 24)
  panel.questTab:SetPoint("TOPRIGHT", -12, -9)
  panel.questTab:SetText("Quests")
  panel.bossTab = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
  panel.bossTab:SetSize(100, 24)
  panel.bossTab:SetPoint("RIGHT", panel.questTab, "LEFT", -10, 0)
  panel.bossTab:SetText("Bosses")
  for _, tab in ipairs({ panel.questTab, panel.bossTab }) do
    if tab.SetDisabledFontObject then tab:SetDisabledFontObject(GameFontHighlight) end
  end
  panel.questTab:SetScript("OnClick", function()
    mode = "quests"
    detail.scroll:SetVerticalScroll(0)
    refresh()
  end)
  panel.bossTab:SetScript("OnClick", function()
    mode = "bosses"
    detail.scroll:SetVerticalScroll(0)
    refresh()
  end)
  panel.progress = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  panel.progress:SetPoint("BOTTOMRIGHT", -12, 9)
  panel.progress:SetJustifyH("RIGHT")

  -- Left pane: the list.
  local left = CreateFrame("Frame", nil, panel)
  left:SetPoint("TOPLEFT", 12, BODY_TOP)
  left:SetPoint("BOTTOMLEFT", 12, 12)
  left:SetWidth(LIST_WIDTH)
  paint(left, C.pane, C.paneEdge)
  panel.listTitle = left:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  panel.listTitle:SetPoint("TOPLEFT", 12, -14)
  panel.listTitle:SetTextColor(0.95, 0.9, 0.8)

  -- Faction crests: which side's quests the list shows. Yours is picked when the window opens.
  panel.factionButtons = {}
  local previous
  for _, side in ipairs({ "horde", "alliance" }) do
    local button = CreateFrame("Button", nil, left)
    button:SetSize(34, 34)
    if previous then
      button:SetPoint("RIGHT", previous, "LEFT", -6, 0)
    else
      button:SetPoint("TOPRIGHT", -8, -6)
    end
    paint(button, C.pane, C.paneEdge)
    button.crest = button:CreateTexture(nil, "ARTWORK")
    button.crest:SetSize(28, 28)
    button.crest:SetPoint("CENTER", 3, -3)
    crestOn(button.crest, side)
    button:SetScript("OnClick", function()
      viewSide = side
      selectedQuestId = nil
      detail.scroll:SetVerticalScroll(0)
      refresh()
    end)
    button:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(side == "horde" and "Horde quests" or "Alliance quests")
      GameTooltip:AddLine("Quests both factions can take are always listed.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    panel.factionButtons[side] = button
    previous = button
  end

  local listScroll = CreateFrame("ScrollFrame", "WoWForeverBuildsJournalList", left, "UIPanelScrollFrameTemplate")
  listScroll:SetPoint("TOPLEFT", 8, -48)
  listScroll:SetPoint("BOTTOMRIGHT", -30, 8)
  panel.listContent = CreateFrame("Frame", nil, listScroll)
  panel.listContent:SetSize(ROW_WIDTH, 1)
  listScroll:SetScrollChild(panel.listContent)
  panel.empty = left:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  panel.empty:SetPoint("TOP", 0, -70)
  panel.empty:SetWidth(LIST_WIDTH - 40)
  panel.empty:Hide()

  -- Right pane: the parchment page.
  local right = CreateFrame("Frame", nil, panel)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
  right:SetPoint("BOTTOMRIGHT", -12, 12)
  paint(right, C.parchmentTop, C.parchmentEdge, 3)
  parchment(right.fill)
  local detailScroll = CreateFrame("ScrollFrame", "WoWForeverBuildsJournalPage", right, "UIPanelScrollFrameTemplate")
  detailScroll:SetPoint("TOPLEFT", 16, -14)
  detailScroll:SetPoint("BOTTOMRIGHT", -32, 12)
  local pageWidth = PANEL_WIDTH - 24 - LIST_WIDTH - 10 - 16 - 32
  detail = {
    scroll = detailScroll,
    content = CreateFrame("Frame", nil, detailScroll),
    width = pageWidth - 4,
    pool = {},
    rewards = {},
    rules = {},
    buttons = {},
    used = 0,
    rulesUsed = 0,
    y = 0,
  }
  detail.content:SetSize(pageWidth, 1)
  detailScroll:SetScrollChild(detail.content)
  detail.crestA = detail.content:CreateTexture(nil, "ARTWORK")
  detail.crestA:SetSize(24, 24)
  detail.crestB = detail.content:CreateTexture(nil, "ARTWORK")
  detail.crestB:SetSize(24, 24)

  -- The world map opens over the journal when Show on Map is used, then the journal comes back on top.
  if WorldMapFrame and WorldMapFrame.HookScript then
    WorldMapFrame:HookScript("OnShow", function() panel:SetFrameStrata("MEDIUM") end)
    WorldMapFrame:HookScript("OnHide", function() panel:SetFrameStrata("HIGH") end)
  end

  panel:SetScript("OnShow", function()
    if not selectedSlug then selectedSlug = defaultSlug() end
    refresh()
  end)
  panel:SetScript("OnHide", function(self)
    if not self.closedByAddon then ns.questPanelDismissed = true end
    self.openedByHand = nil
  end)
  return panel
end

--- Dock beside the group finder if it is open, otherwise keep the panel where the player left it.
local function anchorToFinder()
  for _, name in ipairs({ "PVEFrame", "LFGParentFrame", "LFDParentFrame", "GroupFinderFrame" }) do
    local frame = _G[name]
    if frame and frame:IsShown() then
      panel:ClearAllPoints()
      -- Room for the finder's side tabs, which hang off its right edge.
      panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 52, 0)
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
  selectDungeon(defaultSlug() or selectedSlug)
  -- Opened without the group finder (chat, minimap, options): stays open until you close it.
  panel.openedByHand = not anchorToFinder()
  panel:Show()
end

local function onFinderShown()
  build()
  -- Closing the panel yourself keeps it closed until you ask for it again with /wfb quests.
  if ns.questPanelDismissed then return end
  if ns.Option and not ns.Option("questAutoOpen", true) then return end
  selectDungeon(defaultSlug() or selectedSlug)
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
    say("Dungeon Journal: use the |cffffffffDungeon Journal|r button on the group finder, or type |cffffffff/wfb quests|r.")
  end
  if not toggleButton or not toggleButton:IsShown() then return end
  toggleButton:SetText(panel and panel:IsShown() and "Hide journal" or "Dungeon Journal")
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
      if not ns.questPanelDismissed and (not ns.Option or ns.Option("questAutoOpen", true)) then onFinderShown() end
    end
    updateToggleButton()
  elseif toggleButton and toggleButton:IsShown() then
    toggleButton:Hide()
  end
  if not open and panel and panel:IsShown() and not panel.openedByHand then
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
    if target then selectDungeon(target) end
    if panel and panel:IsShown() then refresh() end
  else
    refresh()
  end
end)
