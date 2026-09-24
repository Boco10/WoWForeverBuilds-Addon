-- In-game talent guide. The guides in Guides.lua (generated from wowforeverbuilds.com) are shown in the talent
-- window: the next talent to take glows, every talent the guide still wants shows the level of its next point, a
-- panel beside the window lists the whole order, and chat says what to take on level up or when you leave the guide.
-- /wfb guide [list | <number> | on | off | reset]   (reset puts the dragged panel back beside the window)
local _, ns = ...

local PREFIX = "|cffd4a84bWoW Forever Builds|r "
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"

local classToken, db
local lookup -- this class's site talents by name and by grid cell
local nodeNames = {}
local lastOff -- signature of the talents taken off the guide, so the warning is printed once per change

local function print(text) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text) end
local function lower(text) return type(text) == "string" and text:lower() or nil end

-- Site data -----------------------------------------------------------------------------------------------------

local function buildLookup()
  local trees = ns.talents[classToken]
  if not trees then return nil end
  local result = { byTree = {}, byName = {}, byCell = {}, minRow = {}, minCol = {} }
  for t, tree in ipairs(trees) do
    result.byTree[t], result.byCell[t] = {}, {}
    for index, talent in ipairs(tree) do
      local key, name = t .. ":" .. index, lower(talent[1])
      result.byTree[t][name] = key
      -- A name used in two trees is only matched inside its own tree.
      result.byName[name] = result.byName[name] == nil and key or false
      result.byCell[t][talent[2] .. ":" .. talent[3]] = key
      result.minRow[t] = math.min(result.minRow[t] or 99, talent[2])
      result.minCol[t] = math.min(result.minCol[t] or 99, talent[3])
    end
  end
  return result
end

local function siteTalent(key)
  local t, index = key:match("^(%d+):(%d+)$")
  return ns.talents[classToken][tonumber(t)][tonumber(index)], tonumber(t)
end

-- Steps of a guide: { key, name, tree, rank reached with this point, maxRank, level }.
local function stepsOf(guide)
  if guide.steps then return guide.steps end
  local steps, reached = {}, {}
  for i = 1, #guide.order - 1, 2 do
    local t = tonumber(guide.order:sub(i, i)) + 1
    local index = B36:find(guide.order:sub(i + 1, i + 1), 1, true)
    local key = t .. ":" .. index
    local talent = ns.talents[classToken][t][index]
    reached[key] = (reached[key] or 0) + 1
    steps[#steps + 1] = { key = key, name = talent[1], tree = t, rank = reached[key], maxRank = talent[4], level = ns.firstTalentLevel + #steps }
  end
  guide.steps = steps
  return steps
end

-- Character talents ---------------------------------------------------------------------------------------------
-- Both readers return site talent key -> { rank, maxRank, nodeID or tab/index }. Talents are matched by name first
-- (English client) and by their row/column in the tab otherwise.

local function nodeName(configID, nodeID, node)
  if nodeNames[nodeID] ~= nil then return nodeNames[nodeID] end
  local name = false
  local entryID = node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
  local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
  local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
  if definition then
    if definition.overrideName and definition.overrideName ~= "" then
      name = definition.overrideName
    elseif definition.spellID then
      name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(definition.spellID)) or (GetSpellInfo and GetSpellInfo(definition.spellID)) or false
    end
  end
  nodeNames[nodeID] = name
  return name
end

local function gridStep(values)
  table.sort(values)
  local step
  for i = 2, #values do
    local gap = values[i] - values[i - 1]
    if gap > 1 and (not step or gap < step) then step = gap end
  end
  return values[1], step or 1
end

local function traitTalents()
  local configID = C_ClassTalents.GetActiveConfigID()
  local config = configID and C_Traits.GetConfigInfo(configID)
  if not config or not config.treeIDs then return nil end
  local nodes = {}
  for _, treeID in ipairs(config.treeIDs) do
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local node = C_Traits.GetNodeInfo(configID, nodeID)
      if node and node.posX and (node.maxRanks or 0) > 0 and node.isVisible ~= false then
        node.wfbID = nodeID
        nodes[#nodes + 1] = node
      end
    end
  end
  if #nodes == 0 then return nil end
  -- Tabs are columns of nodes side by side, as in the export (ns.TAB_GAP).
  table.sort(nodes, function(a, b) return a.posX < b.posX end)
  local tabs, lastX = {}, nil
  for _, node in ipairs(nodes) do
    if not lastX or node.posX - lastX > ns.TAB_GAP then tabs[#tabs + 1] = {} end
    local tab = tabs[#tabs]
    tab[#tab + 1] = node
    lastX = node.posX
  end

  local talents, unmatched = {}, {}
  local function add(key, node)
    talents[key] = { rank = tonumber(node.ranksPurchased or node.currentRank) or 0, maxRank = node.maxRanks, nodeID = node.wfbID }
  end
  for t, tab in ipairs(tabs) do
    for _, node in ipairs(tab) do
      local name = lower(nodeName(configID, node.wfbID, node))
      local key = name and ((lookup.byTree[t] and lookup.byTree[t][name]) or lookup.byName[name])
      if key and not talents[key] then add(key, node) elseif t <= 3 then unmatched[#unmatched + 1] = { t = t, node = node } end
    end
  end
  if #unmatched > 0 then
    local grids = {}
    for _, item in ipairs(unmatched) do
      local grid = grids[item.t]
      if not grid then
        local xs, ys = {}, {}
        for _, node in ipairs(tabs[item.t]) do xs[#xs + 1], ys[#ys + 1] = node.posX, node.posY end
        local minX, stepX = gridStep(xs)
        local minY, stepY = gridStep(ys)
        grid = { minX = minX, stepX = stepX, minY = minY, stepY = stepY }
        grids[item.t] = grid
      end
      local row = math.floor((item.node.posY - grid.minY) / grid.stepY + 0.5) + lookup.minRow[item.t]
      local col = math.floor((item.node.posX - grid.minX) / grid.stepX + 0.5) + lookup.minCol[item.t]
      local key = lookup.byCell[item.t][row .. ":" .. col]
      if key and not talents[key] then add(key, item.node) end
    end
  end
  return talents
end

local function classicTalents()
  if not GetNumTalentTabs or not GetTalentInfo then return nil end
  local talents = {}
  for tab = 1, math.min(GetNumTalentTabs() or 0, 3) do
    for index = 1, (GetNumTalents(tab) or 0) do
      local name, _, tier, column, rank, maxRank = GetTalentInfo(tab, index)
      name = lower(name)
      local key = name and (lookup.byTree[tab][name] or lookup.byName[name])
      if not key and tier and column then key = lookup.byCell[tab][(tier - 1) .. ":" .. (column - 1)] end
      if key and not talents[key] then talents[key] = { rank = tonumber(rank) or 0, maxRank = maxRank, tab = tab, index = index } end
    end
  end
  return talents
end

local function readTalents()
  if C_Traits and C_ClassTalents and C_ClassTalents.GetActiveConfigID then
    local ok, talents = pcall(traitTalents)
    if ok and talents then return talents end
  end
  local ok, talents = pcall(classicTalents)
  return ok and talents or {}
end

-- Guide state ---------------------------------------------------------------------------------------------------

local function classGuides() return ns.guides[classToken] or {} end

-- Where the character stands in the guide: done flags per step, the next step, the level of each talent's next
-- point, and talents that hold more points than the guide has spent on them by now.
local function evaluate(guide, talents)
  local steps = stepsOf(guide)
  local spent = 0
  for _, talent in pairs(talents) do spent = spent + talent.rank end
  local done, nextIndex, nextLevel, allowed = {}, nil, {}, {}
  for i, step in ipairs(steps) do
    local have = talents[step.key] and talents[step.key].rank or 0
    done[i] = have >= step.rank
    if not done[i] then
      nextIndex = nextIndex or i
      nextLevel[step.key] = nextLevel[step.key] or step.level
    end
    if i <= spent then allowed[step.key] = (allowed[step.key] or 0) + 1 end
  end
  local off = {}
  for key, talent in pairs(talents) do
    if talent.rank > (allowed[key] or 0) then off[key] = talent.rank end
  end
  local level = UnitLevel("player")
  local available = math.max(0, math.min(51, level - ns.firstTalentLevel + 1) - spent)
  return { steps = steps, done = done, nextIndex = nextIndex, nextLevel = nextLevel, off = off, allowed = allowed, spent = spent, available = available }
end

local KIND_RANK = { ["Leveling"] = 1, ["Duo leveling"] = 2, ["Dungeon leveling"] = 3, ["Endgame PvE"] = 4, ["Endgame PvP"] = 5 }

local function fitsLevel(guide, level)
  return guide.from <= level and (level < guide.to or (guide.to >= 60 and level >= 60))
end

-- The class's guides, best first: guides your spent talents follow, then guides for your level, then the rest.
-- Each entry: { guide, index, matches = no talent off the guide, fits = level in range, agree = points in common }.
local function rankedGuides(talents, level)
  local ranked = {}
  for index, guide in ipairs(classGuides()) do
    local state = evaluate(guide, talents)
    local agree = 0
    for key, talent in pairs(talents) do agree = agree + math.min(talent.rank, state.allowed[key] or 0) end
    ranked[#ranked + 1] = { guide = guide, index = index, matches = next(state.off) == nil, fits = fitsLevel(guide, level), agree = agree }
  end
  table.sort(ranked, function(a, b)
    if a.matches ~= b.matches then return a.matches end
    if a.fits ~= b.fits then return a.fits end
    if a.agree ~= b.agree then return a.agree > b.agree end
    if a.guide.kind ~= b.guide.kind then return (KIND_RANK[a.guide.kind] or 9) < (KIND_RANK[b.guide.kind] or 9) end
    return a.index < b.index
  end)
  return ranked
end

local function currentGuide()
  if not db or db.off then return nil end
  local list = classGuides()
  for index, guide in ipairs(list) do
    if guide.id == db.guideID then return guide, index end
  end
  local best = rankedGuides(readTalents(), UnitLevel("player"))[1]
  if not best then return nil end
  db.guideID = best.guide.id
  return best.guide, best.index
end

local function offText(off)
  local names, keys = {}, {}
  for key in pairs(off) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local talent = siteTalent(key)
    names[#names + 1] = string.format("%s %d/%d", talent[1], off[key], talent[4])
  end
  return table.concat(names, ", ")
end

-- The off-guide talents right now, taken as the baseline when a guide is chosen so only later changes are reported.
local function offSignature()
  local guide = currentGuide()
  return guide and offText(evaluate(guide, readTalents()).off) or ""
end

-- Talent window -------------------------------------------------------------------------------------------------
-- Returns the shown talent window: { content = frame holding the talent buttons, window = frame to put the panel beside }.

local function shownTalentFrame()
  local spells = _G.PlayerSpellsFrame
  if spells and spells.TalentsFrame and spells.TalentsFrame:IsVisible() then return { content = spells.TalentsFrame, window = spells } end
  local classTalents = _G.ClassTalentFrame
  if classTalents and classTalents.TalentsTab and classTalents.TalentsTab:IsVisible() then return { content = classTalents.TalentsTab, window = classTalents } end
  for _, name in ipairs({ "PlayerTalentFrame", "TalentFrame" }) do
    local frame = _G[name]
    if frame and frame.IsVisible and frame:IsVisible() then return { content = frame, window = frame, classic = name } end
  end
end

local function nodeButtons(content)
  local buttons = {}
  if content.EnumerateAllTalentButtons then
    local ok = pcall(function()
      for button in content:EnumerateAllTalentButtons() do
        local nodeID = button.GetNodeID and button:GetNodeID()
        if nodeID then buttons[nodeID] = button end
      end
    end)
    if ok and next(buttons) then return buttons end
  end
  local function scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
      local nodeID = child.nodeID
      if child.GetNodeID then
        local ok, id = pcall(child.GetNodeID, child)
        if ok then nodeID = id end
      end
      if type(nodeID) == "number" then
        buttons[nodeID] = child
      elseif depth < 6 then
        scan(child, depth + 1)
      end
    end
  end
  scan(content, 0)
  return buttons
end

local function selectedClassicTab(frame)
  if PanelTemplates_GetSelectedTab then
    local ok, tab = pcall(PanelTemplates_GetSelectedTab, frame)
    if ok and tab then return tab end
  end
  return frame.selectedTab or 1
end

local overlays = {}

local function overlayFor(button)
  local overlay = button.wfbGuideOverlay
  if overlay then return overlay end
  overlay = CreateFrame("Frame", nil, button)
  overlay:SetAllPoints(button)
  overlay:SetFrameLevel(button:GetFrameLevel() + 5)
  overlay.glow = overlay:CreateTexture(nil, "OVERLAY")
  overlay.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  overlay.glow:SetBlendMode("ADD")
  overlay.glow:SetPoint("CENTER")
  local pulse = overlay.glow:CreateAnimationGroup()
  local fade = pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.35)
  fade:SetDuration(0.6)
  pulse:SetLooping("BOUNCE")
  overlay.pulse = pulse
  overlay.label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local font, size = overlay.label:GetFont()
  overlay.label:SetFont(font, size, "OUTLINE")
  overlay.label:SetPoint("TOPLEFT", -2, 2)
  button.wfbGuideOverlay = overlay
  overlays[#overlays + 1] = overlay
  return overlay
end

local function hideOverlays()
  for _, overlay in ipairs(overlays) do overlay:Hide() end
end

local function markButton(button, key, state)
  local overlay = overlayFor(button)
  local nextStep = state.nextIndex and state.steps[state.nextIndex]
  local isNext = nextStep and nextStep.key == key
  local level = state.nextLevel[key]
  if state.off[key] then
    overlay.label:SetText("|cffff4040x|r")
  elseif level then
    overlay.label:SetText((isNext and "|cff40ff40" or "|cffffd100") .. level .. "|r")
  else
    overlay.label:SetText("")
  end
  if isNext then
    local width, height = button:GetSize()
    overlay.glow:SetSize(width * 1.9, height * 1.9)
    overlay.glow:SetVertexColor(0.3, 1, 0.3)
    overlay.glow:Show()
    -- Pulses only while a point is waiting to be spent; refreshes keep the running animation.
    if state.available == 0 then
      overlay.pulse:Stop()
    elseif not overlay.pulse:IsPlaying() then
      overlay.pulse:Play()
    end
  else
    overlay.glow:Hide()
    overlay.pulse:Stop()
  end
  overlay:Show()
end

-- Side panel ----------------------------------------------------------------------------------------------------

local panel

local function selectGuide(offset)
  local list = classGuides()
  local _, index = currentGuide()
  if #list == 0 then return end
  index = ((index or 1) - 1 + offset) % #list + 1
  db.guideID = list[index].id
  db.off = nil
  lastOff = offSignature()
end

-- Beside the talent window, at the offset the player dragged it to (default: right next to it).
local function placePanel()
  local window = panel:GetParent()
  local offset = WoWForeverBuildsDB.panelOffset
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", window, "TOPRIGHT", offset and offset.x or 2, offset and offset.y or 0)
end

local function createPanel()
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "WoWForeverBuildsGuidePanel", UIParent, template)
  f:SetSize(270, 440)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
  end
  f:EnableMouse(true)
  -- Drag anywhere on the panel to move it; the spot is kept relative to the talent window (/wfb guide reset).
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(false) -- the addon keeps the spot, not the game's layout cache
    local window = self:GetParent()
    if window and window.GetRight and window:GetRight() then
      WoWForeverBuildsDB.panelOffset = { x = self:GetLeft() - window:GetRight(), y = self:GetTop() - window:GetTop() }
    end
    placePanel()
  end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("WoW Forever Builds guide")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    db.hidePanel = true
    ns.RefreshGuide()
  end)

  local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  prev:SetSize(26, 20)
  prev:SetPoint("TOPLEFT", 10, -30)
  prev:SetText("<")
  prev:SetScript("OnClick", function() selectGuide(-1); ns.RefreshGuide() end)

  local nextButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  nextButton:SetSize(26, 20)
  nextButton:SetPoint("LEFT", prev, "RIGHT", 4, 0)
  nextButton:SetText(">")
  nextButton:SetScript("OnClick", function() selectGuide(1); ns.RefreshGuide() end)

  f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.counter:SetPoint("LEFT", nextButton, "RIGHT", 8, 0)

  -- Switches the list between the guide's talent order and a list of every guide for the class, best match first.
  f.choose = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.choose:SetSize(100, 20)
  f.choose:SetPoint("TOPRIGHT", -12, -30)
  f.choose:SetText("Choose guide")
  f.choose:SetScript("OnClick", function()
    f.picking = not f.picking
    f.scrolledTo = nil
    ns.RefreshGuide()
  end)
  f.rows = {}

  f.guideTitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.guideTitle:SetPoint("TOPLEFT", 12, -58)
  f.guideTitle:SetPoint("TOPRIGHT", -12, -58)
  f.guideTitle:SetJustifyH("LEFT")

  f.meta = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.meta:SetPoint("TOPLEFT", f.guideTitle, "BOTTOMLEFT", 0, -4)
  f.meta:SetPoint("TOPRIGHT", f.guideTitle, "BOTTOMRIGHT", 0, -4)
  f.meta:SetJustifyH("LEFT")

  f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.status:SetPoint("TOPLEFT", f.meta, "BOTTOMLEFT", 0, -6)
  f.status:SetPoint("TOPRIGHT", f.meta, "BOTTOMRIGHT", 0, -6)
  f.status:SetJustifyH("LEFT")

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", -30, 12)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(220, 10)
  scroll:SetScrollChild(content)
  f.list = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.list:SetPoint("TOPLEFT")
  f.list:SetWidth(220)
  f.list:SetJustifyH("LEFT")
  f.list:SetSpacing(2)
  f.scroll, f.content = scroll, content
  return f
end

local function pickerRow(i)
  local row = panel.rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, panel.content)
  row:SetSize(220, 36)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * 38)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.selected = row:CreateTexture(nil, "BACKGROUND")
  row.selected:SetAllPoints()
  row.selected:SetColorTexture(0.83, 0.66, 0.29, 0.18)
  row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.title:SetPoint("TOPLEFT", 4, -3)
  row.title:SetPoint("TOPRIGHT", -4, -3)
  row.title:SetJustifyH("LEFT")
  row.title:SetWordWrap(false)
  row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.meta:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
  row.meta:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0, -3)
  row.meta:SetJustifyH("LEFT")
  row:SetScript("OnClick", function(self)
    db.guideID, db.off = self.guideID, nil
    lastOff = offSignature()
    panel.picking, panel.scrolledTo = false, nil
    ns.RefreshGuide()
  end)
  panel.rows[i] = row
  return row
end

local function showPicker(current)
  local ranked = rankedGuides(readTalents(), UnitLevel("player"))
  panel.guideTitle:SetText("Choose a guide")
  panel.meta:SetText("Best match first: guides your talents already follow, then guides for your level.")
  panel.status:SetText("")
  panel.list:SetText("")
  for i, entry in ipairs(ranked) do
    local row, guide = pickerRow(i), entry.guide
    local tag = entry.matches and "|cff40ff40follows your talents|r" or (entry.fits and "|cffffd100your level|r" or "")
    row.guideID = guide.id
    row.title:SetText(guide.title)
    row.meta:SetText(string.format("%s · %s · %d–%d%s", guide.kind, guide.spec, guide.from, guide.to, tag ~= "" and (" · " .. tag) or ""))
    row.selected:SetShown(guide == current)
    row:Show()
  end
  for i = #ranked + 1, #panel.rows do panel.rows[i]:Hide() end
  panel.content:SetHeight(#ranked * 38)
  if not panel.scrolledTo then
    panel.scrolledTo = "picker"
    panel.scroll:UpdateScrollChildRect()
    panel.scroll:SetVerticalScroll(0)
  end
end

local function updatePanel(talentFrame, guide, index, state)
  if db.hidePanel then
    if panel then panel:Hide() end
    return
  end
  panel = panel or createPanel()
  if panel:GetParent() ~= talentFrame.window then
    panel:SetParent(talentFrame.window)
    placePanel()
  end
  panel:Show()
  local list = classGuides()
  panel.counter:SetText(guide and string.format("%d / %d", index, #list) or ("off (" .. #list .. " guides)"))
  panel.choose:SetText(panel.picking and "Back" or "Choose guide")
  if panel.picking and #list > 0 then return showPicker(guide) end
  for _, row in ipairs(panel.rows) do row:Hide() end
  if not guide then
    panel.guideTitle:SetText(#list > 0 and "Guide is off." or "No guide for this class yet.")
    panel.meta:SetText(#list > 0 and "Use the arrows or |cffffffff/wfb guide on|r." or "")
    panel.status:SetText("")
    panel.list:SetText("")
    return
  end
  panel.guideTitle:SetText(guide.title)
  panel.meta:SetText(string.format("%s · %s · levels %d–%d", guide.kind, guide.spec, guide.from, guide.to))

  local status
  if next(state.off) then
    status = "|cffff4040Off the guide:|r " .. offText(state.off)
  elseif not state.nextIndex then
    status = "|cff40ff40Guide complete.|r Pick the next one with Choose guide."
  else
    local step = state.steps[state.nextIndex]
    local when = step.level <= UnitLevel("player") and "now" or ("at level " .. step.level)
    status = string.format("Next (%s): |cff40ff40%s %d/%d|r", when, step.name, step.rank, step.maxRank)
  end
  panel.status:SetText(status)

  local specTree
  for t, tree in ipairs(ns.talents[classToken]) do if tree.name == guide.spec then specTree = t end end
  local lines = {}
  for i, step in ipairs(state.steps) do
    local color = state.done[i] and "|cff7f7f7f" or (i == state.nextIndex and "|cff40ff40" or "|cffffffff")
    local treeName = step.tree ~= specTree and (" (" .. ns.talents[classToken][step.tree].name .. ")") or ""
    lines[i] = string.format("%s%2d  %s %d/%d%s|r", color, step.level, step.name, step.rank, step.maxRank, treeName)
  end
  panel.list:SetText(table.concat(lines, "\n"))
  panel.content:SetHeight(panel.list:GetStringHeight() + 4)
  if panel.scrolledTo ~= guide.id .. ":" .. tostring(state.nextIndex) then
    panel.scrolledTo = guide.id .. ":" .. tostring(state.nextIndex)
    panel.scroll:UpdateScrollChildRect()
    local lineHeight = panel.list:GetStringHeight() / math.max(#lines, 1)
    local target = math.max(0, ((state.nextIndex or #lines) - 4) * lineHeight)
    panel.scroll:SetVerticalScroll(math.min(target, panel.scroll:GetVerticalScrollRange()))
  end
end

-- Refresh -------------------------------------------------------------------------------------------------------

-- Small button in the talent window's bottom-left corner that shows or hides the guide (panel and talent marks).
local toggle

local function updateToggle(window)
  if not toggle then
    toggle = CreateFrame("Button", "WoWForeverBuildsGuideToggle", window, "UIPanelButtonTemplate")
    toggle:SetSize(96, 22)
    toggle:SetScript("OnClick", function()
      db.hidePanel = not db.hidePanel or nil
      ns.RefreshGuide()
    end)
    toggle:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText("WoW Forever Builds guide")
      GameTooltip:AddLine("Shows or hides the talent guide panel and the level numbers on your talents.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  if toggle:GetParent() ~= window then toggle:SetParent(window) end
  toggle:ClearAllPoints()
  toggle:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 14, 8)
  toggle:SetFrameLevel(window:GetFrameLevel() + 20)
  toggle:SetText(db.hidePanel and "Show guide" or "Hide guide")
  toggle:Show()
end

function ns.RefreshGuide()
  local talentFrame = shownTalentFrame()
  if not talentFrame or not lookup then
    return
  end
  hideOverlays()
  updateToggle(talentFrame.window)
  local guide, index = currentGuide()
  local state
  if guide and not db.hidePanel then
    local talents = readTalents()
    state = evaluate(guide, talents)
    if talentFrame.classic then
      local tab = selectedClassicTab(talentFrame.content)
      for key, talent in pairs(talents) do
        local button = talent.tab == tab and _G[talentFrame.classic .. "Talent" .. talent.index]
        if button and button:IsShown() then markButton(button, key, state) end
      end
    else
      local buttons = nodeButtons(talentFrame.content)
      for key, talent in pairs(talents) do
        local button = talent.nodeID and buttons[talent.nodeID]
        if button and button:IsShown() then markButton(button, key, state) end
      end
    end
  end
  updatePanel(talentFrame, guide, index, state)
end

-- Chat messages -------------------------------------------------------------------------------------------------

local function chatOn() return not ns.Option or ns.Option("guideChat", true) end

local function announceLevel(level)
  if not chatOn() then return end
  local guide = currentGuide()
  if not guide or level < ns.firstTalentLevel then return end
  local state = evaluate(guide, readTalents())
  if not state.nextIndex then
    if level >= guide.to then print("You finished |cffffffff" .. guide.title .. "|r. Pick the next guide beside the talent window.") end
    return
  end
  local step = state.steps[state.nextIndex]
  if step.level > level then return end
  local points = state.available > 1 and (" (" .. state.available .. " points to spend)") or ""
  print(string.format("Level %d: take |cff40ff40%s %d/%d|r%s.", level, step.name, step.rank, step.maxRank, points))
end

local function checkOffGuide()
  local guide = currentGuide()
  if not guide then return end
  local state = evaluate(guide, readTalents())
  local signature = offText(state.off)
  if signature ~= lastOff and signature ~= "" and lastOff ~= nil and chatOn() then
    local step = state.nextIndex and state.steps[state.nextIndex]
    print("|cffff4040Off the guide:|r " .. signature .. (step and string.format(". The guide's next pick is %s %d/%d.", step.name, step.rank, step.maxRank) or "."))
  end
  lastOff = signature
end

-- Commands ------------------------------------------------------------------------------------------------------

--- Open or close the talent window. Forever uses the modern PlayerSpellsFrame (talents are a tab of it),
--- older clients the classic talent frame. Called through securecallfunction, as Blizzard's own
--- buttons do, so opening it from an addon does not taint it.
function ns.ToggleTalents()
  if InCombatLockdown and InCombatLockdown() then
    return print("The talent window cannot be opened from an addon in combat.")
  end
  local run = securecallfunction or function(fn, ...) return fn(...) end
  local util = _G.PlayerSpellsUtil
  if util then
    for _, name in ipairs({ "ToggleClassTalentFrame", "ToggleClassTalentOrSpecFrame", "OpenToClassTalentsTab" }) do
      if type(util[name]) == "function" and pcall(run, util[name]) then return end
    end
  end
  if type(ToggleTalentFrame) ~= "function" and type(TalentFrame_LoadUI) == "function" then pcall(TalentFrame_LoadUI) end
  if type(ToggleTalentFrame) == "function" and pcall(run, ToggleTalentFrame) then return end
  print("Could not open the talent window on this client. Press the talent key (N) instead.")
end

--- For the minimap menu's on/off tick; nil when this class has no guides.
function ns.TalentGuideEnabled()
  if not db then return nil end
  return not db.off
end

--- For the options panel: this class's guides and the one in use.
function ns.TalentGuideChoices()
  if not db then return nil end
  local _, index = currentGuide()
  return classGuides(), index
end

--- For the options panel: whether the order panel sits beside the talent window.
function ns.TalentGuidePanelShown()
  return db ~= nil and not db.hidePanel
end
function ns.SetTalentGuidePanelShown(shown)
  if not db then return end
  db.hidePanel = not shown or nil
  ns.RefreshGuide()
end

function ns.GuideCommand(args)
  if not db then return end
  args = strtrim(args or ""):lower()
  local list = classGuides()
  if args == "off" then
    db.off = true
    hideOverlays()
    print("Talent guide off. |cffffffff/wfb guide on|r turns it back on.")
  elseif args == "on" then
    db.off, db.hidePanel = nil, nil
    print("Talent guide on: " .. (currentGuide() and currentGuide().title or "no guide for this class") .. ".")
  elseif args == "reset" then
    WoWForeverBuildsDB.panelOffset = nil
    if panel and panel:GetParent() ~= UIParent then placePanel() end
    print("Guide panel moved back next to the talent window.")
  elseif args == "list" then
    for i, guide in ipairs(list) do
      print(string.format("%d. %s (%s, %d–%d)", i, guide.title, guide.kind, guide.from, guide.to))
    end
    print("Choose one with |cffffffff/wfb guide <number>|r.")
  elseif tonumber(args) then
    local guide = list[tonumber(args)]
    if not guide then return print("No guide number " .. args .. ". See |cffffffff/wfb guide list|r.") end
    db.guideID, db.off = guide.id, nil
    lastOff = offSignature()
    print("Guide set: |cffffffff" .. guide.title .. "|r.")
  else
    db.hidePanel, db.off = nil, nil
    local guide = currentGuide()
    print(guide and ("Guide: |cffffffff" .. guide.title .. "|r. Open your talents to follow it. |cffffffff/wfb guide list|r shows all " .. #list .. " guides.") or "No guide for this class yet.")
  end
  ns.RefreshGuide()
end

-- Setup ---------------------------------------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local elapsed = 0
driver:SetScript("OnUpdate", function(_, delta)
  elapsed = elapsed + delta
  if elapsed < 0.5 then return end
  elapsed = 0
  ns.RefreshGuide()
end)

local function onTalentsChanged()
  if C_Timer then C_Timer.After(0.3, checkOffGuide) else checkOffGuide() end
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_LEVEL_UP")
for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "CHARACTER_POINTS_CHANGED" }) do
  pcall(driver.RegisterEvent, driver, event) -- not every client has every event
end
driver:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    classToken = select(2, UnitClass("player"))
    WoWForeverBuildsCharDB = WoWForeverBuildsCharDB or {}
    WoWForeverBuildsDB = WoWForeverBuildsDB or {}
    db = WoWForeverBuildsCharDB
    lookup = buildLookup()
    if not lookup then db = nil return end
    lastOff = offSignature()
  elseif not db then
    return
  elseif event == "PLAYER_LEVEL_UP" then
    local level = tonumber(arg1) or UnitLevel("player")
    if C_Timer then C_Timer.After(1, function() announceLevel(level) end) else announceLevel(level) end
  else
    onTalentsChanged()
  end
end)
