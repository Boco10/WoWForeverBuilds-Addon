-- Marks quests in the quest log that matter for a dungeon: the dungeon quests themselves, and the
-- ones that open a dungeon chain. Titles get a small prefix, and hovering one explains it.
local _, ns = ...

local GOLD, GREY = "|cffffd100", "|cff8a8a8a"
-- Prefix put in front of a quest title in the log: [D] for a dungeon quest, [D>] for one that opens a chain.
local MARK = "|cffffd100[D]|r "
local MARK_OPENS = "|cffff8000[D>]|r "

local index
--- title (lower case) -> { dungeon = "Wailing Caverns", opens = "Hamuul Runetotem" or nil }
local function questIndex()
  if index then return index end
  index = {}
  for _, dungeon in ipairs(ns.dungeons or {}) do
    for _, quest in ipairs(dungeon) do
      index[quest.title:lower()] = { dungeon = dungeon.name }
      -- A written prelude step: the quest itself is not a dungeon quest, but it leads to one.
      for _, line in ipairs(quest.pre or {}) do
        local name = line:match("^(.-)%s*%(") or line
        index[name:lower()] = { dungeon = dungeon.name, opens = quest.title }
      end
    end
  end
  return index
end

local function entryFor(title)
  return type(title) == "string" and questIndex()[title:lower()] or nil
end

local function addTooltipLine(title)
  local entry = entryFor(title)
  if not entry or not GameTooltip or not GameTooltip:IsShown() then return end
  if entry.opens then
    GameTooltip:AddLine(GOLD .. "Opens " .. entry.opens .. "|r " .. GREY .. "(" .. entry.dungeon .. ")|r", 1, 1, 1, true)
  else
    GameTooltip:AddLine(GOLD .. "Dungeon quest|r " .. GREY .. "(" .. entry.dungeon .. ")|r", 1, 1, 1, true)
  end
  GameTooltip:Show()
end

--- The quest title behind a quest log button, whichever UI version is running.
local function titleOfButton(button)
  if type(button) ~= "table" then return nil end
  if button.questID and C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, title = pcall(C_QuestLog.GetTitleForQuestID, button.questID)
    if ok and title then return title end
  end
  local logIndex = button.questLogIndex or button.index
  if logIndex and C_QuestLog and C_QuestLog.GetInfo then
    local info = C_QuestLog.GetInfo(logIndex)
    if info then return info.title end
  end
  if logIndex and type(GetQuestLogTitle) == "function" then
    return (GetQuestLogTitle(logIndex))
  end
  return nil
end

--- The quest name inside a log line, which reads "[16] The Stagnant Oasis".
local function titleFromText(text)
  if type(text) ~= "string" or text == "" then return nil end
  local name = text:gsub("^%s*%[[^%]]*%]%s*", ""):gsub("%s+$", "")
  return name ~= "" and name or nil
end

--- Put the prefix in front of a title font string, once.
local function markFontString(fontString)
  if not fontString or not fontString.GetText or not fontString.SetText then return false end
  local text = fontString:GetText()
  if type(text) ~= "string" or text == "" then return false end
  if text:find("|cffffd100[D]", 1, true) or text:find("|cffff8000[D>]", 1, true) then return true end
  local entry = entryFor(titleFromText(text))
  if not entry then return false end
  fontString:SetText((entry.opens and MARK_OPENS or MARK) .. text)
  return true
end

--- Every font string under a frame, one level deep, which is where quest titles live.
local function markFrame(frame)
  if not frame or not frame.GetRegions then return end
  for _, region in ipairs({ frame:GetRegions() }) do
    if region and region.GetObjectType and region:GetObjectType() == "FontString" then markFontString(region) end
  end
  if frame.Text then markFontString(frame.Text) end
end

--- Walk whatever quest log this client uses and mark the titles we know.
local function markVisibleTitles()
  local containers = {}
  local function add(frame)
    if frame and frame.GetChildren then containers[#containers + 1] = frame end
  end
  if QuestMapFrame then
    add(QuestMapFrame.QuestsFrame and QuestMapFrame.QuestsFrame.Contents)
    add(QuestMapFrame.QuestsFrame)
  end
  add(_G.QuestScrollFrame and _G.QuestScrollFrame.Contents)
  add(_G.QuestLogQuestsContainer)
  add(_G.QuestLogListScrollFrame and _G.QuestLogListScrollFrame.ScrollChild)
  for _, container in ipairs(containers) do
    for _, child in ipairs({ container:GetChildren() }) do
      if child and child.IsShown and child:IsShown() then markFrame(child) end
    end
  end
  -- The classic quest log's numbered buttons.
  for i = 1, 30 do
    local text = _G["QuestLogTitle" .. i .. "NormalText"]
    if not text then break end
    markFontString(text)
  end
end

--- The quest log redraws itself constantly, so re-mark it while it is on screen.
local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
  since = since + elapsed
  if since < 0.4 then return end
  since = 0
  local open = (QuestMapFrame and QuestMapFrame:IsShown()) or (_G.QuestLogFrame and _G.QuestLogFrame:IsShown()) or (_G.QuestLogExFrame and _G.QuestLogExFrame:IsShown())
  if open then markVisibleTitles() end
end)

local hookedNames = {}
local function hookQuestLog()
  for _, name in ipairs({ "QuestMapLogTitleButton_OnEnter", "QuestLogTitleButton_OnEnter" }) do
    if not hookedNames[name] and type(_G[name]) == "function" then
      hookedNames[name] = true
      hooksecurefunc(name, function(button)
        addTooltipLine(titleOfButton(button))
      end)
    end
  end
  -- Redrawing the list wipes the prefixes, so put them back after every rebuild.
  for _, name in ipairs({ "QuestLogQuests_Update", "QuestMapFrame_UpdateAll", "QuestLog_Update" }) do
    if not hookedNames[name] and type(_G[name]) == "function" then
      hookedNames[name] = true
      hooksecurefunc(name, markVisibleTitles)
    end
  end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("QUEST_ACCEPTED")
driver:RegisterEvent("QUEST_LOG_UPDATE")
driver:SetScript("OnEvent", function(_, event)
  if event == "QUEST_ACCEPTED" then
    -- The new quest lands in the log, so its title needs the prefix too.
    markVisibleTitles()
  elseif event == "QUEST_LOG_UPDATE" then
    hookQuestLog()
    markVisibleTitles()
  else
    hookQuestLog()
  end
end)
