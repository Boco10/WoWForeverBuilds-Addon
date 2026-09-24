-- WoW Forever Builds character export.
-- /wfb opens a window with one line of text. Copy it (Ctrl+C) and paste it on
-- wowforeverbuilds.com > My characters > Import from addon.
--
-- Format (parsed by src/lib/characters/addon-import.ts on the site):
--   WFB1;n=<name>;r=<realm>;c=<CLASS token>;ra=<race token>;f=<faction>;l=<level>;t=<points per talent tab, "/"-separated>;p=<professions, ","-separated>;hc=<1 on hardcore>
-- Values never contain ";", "=" or "|" (stripped below).

local _, ns = ...
local FORMAT = "WFB1"

local function clean(value)
  return (tostring(value or ""):gsub("[;=|\r\n]", ""))
end

-- WoW Forever puts all three classic talent tabs into one C_Traits tree, laid out as three
-- columns side by side. Nodes are grouped into tabs by posX (about 600 apart inside a tab,
-- more than 2000 between tabs) and read left to right, which is the classic tab order.
local TAB_GAP = 1500
ns.TAB_GAP = TAB_GAP -- TalentGuide.lua groups nodes the same way

local function traitTalentPoints()
  local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
  local config = configID and C_Traits and C_Traits.GetConfigInfo(configID)
  if not config or not config.treeIDs then return nil end
  local nodes = {}
  for _, treeID in ipairs(config.treeIDs) do
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local node = C_Traits.GetNodeInfo(configID, nodeID)
      if node and node.posX and (node.maxRanks or 0) > 0 then nodes[#nodes + 1] = node end
    end
  end
  if #nodes == 0 then return nil end
  table.sort(nodes, function(a, b) return a.posX < b.posX end)
  local tabs, lastX = {}, nil
  for _, node in ipairs(nodes) do
    if not lastX or node.posX - lastX > TAB_GAP then tabs[#tabs + 1] = 0 end
    tabs[#tabs] = tabs[#tabs] + (tonumber(node.ranksPurchased) or 0)
    lastX = node.posX
  end
  return table.concat(tabs, "/")
end

local function talentPoints()
  if C_Traits and C_ClassTalents then
    local ok, points = pcall(traitTalentPoints)
    if ok and points then return points end
  end
  if not GetNumTalentTabs or not GetTalentInfo then return "" end
  local tabs = {}
  for tab = 1, GetNumTalentTabs() do
    local spent = 0
    for index = 1, (GetNumTalents(tab) or 0) do
      local _, _, _, _, rank = GetTalentInfo(tab, index)
      spent = spent + (tonumber(rank) or 0)
    end
    tabs[#tabs + 1] = spent
  end
  return table.concat(tabs, "/")
end

-- Primary professions are the only skill lines a player can abandon.
local function professions()
  -- WoW Forever uses the retail API: the first two GetProfessions() slots are the primary professions.
  if GetProfessions and GetProfessionInfo then
    local names = {}
    local first, second = GetProfessions()
    for _, index in ipairs({ first or 0, second or 0 }) do
      local name = index > 0 and GetProfessionInfo(index)
      if name then names[#names + 1] = clean(name) end
    end
    return table.concat(names, ",")
  end
  if not GetNumSkillLines or not GetSkillLineInfo then return "" end
  for index = GetNumSkillLines(), 1, -1 do
    local _, isHeader, isExpanded = GetSkillLineInfo(index)
    if isHeader and not isExpanded and ExpandSkillHeader then ExpandSkillHeader(index) end
  end
  local names = {}
  for index = 1, GetNumSkillLines() do
    local name, isHeader, _, _, _, _, _, isAbandonable = GetSkillLineInfo(index)
    if name and not isHeader and isAbandonable then names[#names + 1] = clean(name) end
  end
  return table.concat(names, ",")
end

local function isHardcore()
  return C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() and true or false
end

local function exportString()
  local _, classToken = UnitClass("player")
  local _, raceToken = UnitRace("player")
  local parts = {
    FORMAT,
    "n=" .. clean(UnitName("player")),
    "r=" .. clean(GetRealmName()),
    "c=" .. clean(classToken),
    "ra=" .. clean(raceToken),
    "f=" .. clean(UnitFactionGroup("player")),
    "l=" .. clean(UnitLevel("player")),
    "t=" .. talentPoints(),
    "p=" .. professions(),
  }
  if isHardcore() then parts[#parts + 1] = "hc=1" end
  return table.concat(parts, ";")
end

local frame

local function createFrame()
  local ok, f = pcall(CreateFrame, "Frame", "WoWForeverBuildsExport", UIParent, "BasicFrameTemplateWithInset")
  if not ok then
    f = CreateFrame("Frame", "WoWForeverBuildsExport", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
      f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
      })
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end
  f:SetSize(460, 130)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "WoWForeverBuildsExport")

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -6)
  title:SetText("WoW Forever Builds")

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("TOPLEFT", 18, -36)
  hint:SetPoint("TOPRIGHT", -18, -36)
  hint:SetJustifyH("LEFT")
  hint:SetText("Press Ctrl+C, then paste on wowforeverbuilds.com > My characters > Import from addon.")

  local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  box:SetPoint("TOPLEFT", 24, -72)
  box:SetPoint("TOPRIGHT", -20, -72)
  box:SetHeight(24)
  box:SetAutoFocus(true)
  box:SetScript("OnEscapePressed", function() f:Hide() end)
  box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  -- Read-only: typing restores the export line.
  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      self:SetText(f.exportText or "")
      self:HighlightText()
    end
  end)
  f.box = box

  local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  refresh:SetSize(90, 22)
  refresh:SetPoint("BOTTOMRIGHT", -16, 12)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", function() f:Refresh() end)

  function f:Refresh()
    -- Show API errors in the box so a player can report them instead of getting an empty window.
    local ok, text = pcall(exportString)
    self.exportText = ok and text or ("Error: " .. clean(text))
    self.box:SetText(self.exportText)
    self.box:SetCursorPosition(0)
    self.box:SetFocus()
    self.box:HighlightText()
  end

  return f
end

local function show()
  frame = frame or createFrame()
  frame:Show()
  frame:Refresh()
end
ns.ShowExport = show

-- /wfb debug: saves the client's talent and skill API shape to WoWForeverBuildsDB.debug
-- (written to WTF\Account\<account>\SavedVariables on /reload or logout).
local function plain(value, depth)
  local kind = type(value)
  if kind ~= "table" then
    return (kind == "string" or kind == "number" or kind == "boolean") and value or kind
  end
  if depth <= 0 then return "table" end
  local copy = {}
  for key, inner in pairs(value) do
    if type(key) == "string" or type(key) == "number" then copy[key] = plain(inner, depth - 1) end
  end
  return copy
end

local function try(fn, ...)
  if type(fn) ~= "function" then return "missing" end
  local result = { pcall(fn, ...) }
  if not result[1] then return "error: " .. tostring(result[2]) end
  table.remove(result, 1)
  return plain(result, 6)
end

local function apiNames(namespace)
  if type(namespace) ~= "table" then return "missing" end
  local names = {}
  for name in pairs(namespace) do names[#names + 1] = name end
  table.sort(names)
  return names
end

local function collectDebug()
  local out = {
    build = { GetBuildInfo() },
    player = { class = select(2, UnitClass("player")), level = UnitLevel("player") },
    globals = {},
    namespaces = {
      C_ClassTalents = apiNames(C_ClassTalents),
      C_Traits = apiNames(C_Traits),
      C_SpecializationInfo = apiNames(C_SpecializationInfo),
      C_TradeSkillUI = apiNames(C_TradeSkillUI),
      C_SpellBook = apiNames(C_SpellBook),
    },
  }
  for _, name in ipairs({ "GetNumSkillLines", "GetSkillLineInfo", "GetProfessions", "GetProfessionInfo", "GetSpecialization", "GetSpecializationInfo", "GetNumSpecializations", "GetActiveTalentGroup", "GetUnspentTalentPoints" }) do
    out.globals[name] = type(_G[name])
  end
  out.numSkillLines = try(GetNumSkillLines)
  out.skillLines = {}
  if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
    for index = 1, math.min(GetNumSkillLines() or 0, 60) do out.skillLines[index] = try(GetSkillLineInfo, index) end
  end
  out.professions = try(GetProfessions)
  out.spec = {
    GetSpecialization = try(GetSpecialization),
    GetNumSpecializations = try(GetNumSpecializations),
    ciGetSpecialization = try(C_SpecializationInfo and C_SpecializationInfo.GetSpecialization),
    GetActiveTalentGroup = try(GetActiveTalentGroup),
    GetUnspentTalentPoints = try(GetUnspentTalentPoints),
  }
  -- Which talent window this client uses, so the talent guide can find its buttons.
  out.talentFrames = {}
  for _, name in ipairs({ "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame", "TalentFrame" }) do
    local frame = _G[name]
    out.talentFrames[name] = type(frame) == "table" and {
      shown = frame.IsShown and frame:IsShown() or false,
      talentsFrame = type(frame.TalentsFrame) == "table",
      talentsTab = type(frame.TalentsTab) == "table",
      enumerate = type((frame.TalentsFrame or frame.TalentsTab or frame).EnumerateAllTalentButtons) == "function",
    } or "missing"
  end
  local talentGlobals = {}
  for name, value in pairs(_G) do
    if type(name) == "string" and name:find("Talent") and type(value) == "table" and type(value.GetObjectType) == "function" and #talentGlobals < 60 then
      talentGlobals[#talentGlobals + 1] = name
    end
  end
  table.sort(talentGlobals)
  out.talentGlobals = talentGlobals
  out.specInfo = {}
  for index = 1, 4 do out.specInfo[index] = try(GetSpecializationInfo, index) end

  local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
  out.activeConfigID = configID or "none"
  out.configIDsBySpec = try(C_ClassTalents and C_ClassTalents.GetConfigIDsBySpecID)
  if configID and C_Traits then
    local config = C_Traits.GetConfigInfo(configID)
    out.config = plain(config, 4)
    out.trees = {}
    for _, treeID in ipairs(config and config.treeIDs or {}) do
      local tree = { treeInfo = try(C_Traits.GetTreeInfo, configID, treeID), currency = try(C_Traits.GetTreeCurrencyInfo, configID, treeID, false), nodes = {} }
      local nodeIDs = C_Traits.GetTreeNodes(treeID) or {}
      tree.nodeCount = #nodeIDs
      for i, nodeID in ipairs(nodeIDs) do
        if i > 150 then break end
        local ok, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
        if ok and node then
          local entry = node.entryIDs and node.entryIDs[1]
          local spellName
          if entry then
            local okEntry, entryInfo = pcall(C_Traits.GetEntryInfo, configID, entry)
            local definitionID = okEntry and entryInfo and entryInfo.definitionID
            local okDef, definition = pcall(C_Traits.GetDefinitionInfo, definitionID)
            local spellID = okDef and definition and definition.spellID
            if spellID then
              local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
              spellName = info and info.name or (GetSpellInfo and GetSpellInfo(spellID))
            end
            tree.entrySample = tree.entrySample or plain(entryInfo, 3)
          end
          tree.nodes[#tree.nodes + 1] = {
            id = nodeID, x = node.posX, y = node.posY, type = node.type, maxRanks = node.maxRanks,
            ranksPurchased = node.ranksPurchased, activeRank = node.activeRank, currentRank = node.currentRank,
            subTreeID = node.subTreeID, isVisible = node.isVisible, groupIDs = plain(node.groupIDs, 2),
            costs = try(C_Traits.GetNodeCost, configID, nodeID), spell = spellName,
          }
          tree.nodeSample = tree.nodeSample or plain(node, 3)
        end
      end
      out.trees[#out.trees + 1] = tree
    end
  end
  return out
end

local function command(msg)
  local word, rest = strtrim(msg or ""):match("^(%S*)%s*(.*)$")
  if word:lower() == "guide" then return ns.GuideCommand(rest) end
  if word:lower() == "quests" then
    if ns.ToggleQuestPanel then return ns.ToggleQuestPanel() end
    DEFAULT_CHAT_FRAME:AddMessage("|cffd4a84bWoW Forever Builds|r quest panel is not loaded.")
    return
  end
  if word:lower() == "route" or word:lower() == "routes" then
    if ns.RouteCommand then return ns.RouteCommand(rest) end
    DEFAULT_CHAT_FRAME:AddMessage("|cffd4a84bWoW Forever Builds|r route guides are not loaded.")
    return
  end
  if word:lower() == "options" or word:lower() == "settings" or word:lower() == "config" then
    if ns.OpenOptions then return ns.OpenOptions() end
    return
  end
  if word:lower() == "minimap" then
    if ns.MinimapCommand then return ns.MinimapCommand() end
    return
  end
  if word:lower() == "debug" then
    WoWForeverBuildsDB = WoWForeverBuildsDB or {}
    local ok, result = pcall(collectDebug)
    WoWForeverBuildsDB.debug = ok and result or { error = tostring(result) }
    DEFAULT_CHAT_FRAME:AddMessage("|cffd4a84bWoW Forever Builds|r debug " .. (ok and "saved" or "failed: " .. tostring(result)) .. ". Type |cffffffff/reload|r to write it to disk.")
    return
  end
  show()
end

SLASH_WOWFOREVERBUILDS1 = "/wfb"
SLASH_WOWFOREVERBUILDS2 = "/wowforeverbuilds"
SlashCmdList.WOWFOREVERBUILDS = command

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  DEFAULT_CHAT_FRAME:AddMessage("|cffd4a84bWoW Forever Builds|r loaded. |cffffffff/wfb|r exports this character, |cffffffff/wfb guide|r shows the talent guide, |cffffffff/wfb quests|r lists dungeon quests, |cffffffff/wfb route|r opens the route guides.")
end)
