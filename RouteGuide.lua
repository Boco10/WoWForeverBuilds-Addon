-- Route guides: a panel that walks you through an errand stop by stop (RouteData.lua).
-- The current stop gets a map waypoint (TomTom when it is installed, the game's own pin otherwise),
-- chat tells you when you arrive, and picking up a quest near the stop moves you on to the next one.
-- Progress is kept per character.
local _, ns = ...

local PREFIX = "|cffd4a84bWoW Forever Builds|r "
local GREY, WHITE, GOLD, GREEN, ORANGE = "|cff8a8a8a", "|cffffffff", "|cffffd100", "|cff40d040", "|cffff8000"
local PANEL_WIDTH = 540
local ROW_WIDTH = PANEL_WIDTH - 46
-- Map percent: close enough to count as standing at the stop, and close enough that a quest you
-- accept belongs to it.
local ARRIVE_RADIUS, QUEST_RADIUS = 1.5, 4

--- Read when needed: the faction is not always known while the addon loads.
local function mySide()
  return UnitFactionGroup and UnitFactionGroup("player") == "Horde" and "horde" or "alliance"
end

local panel, rows, routeButtons
local selectedSlug

local function say(text)
  DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text)
end

--- The routes this character can run: shared ones and its own faction's.
local function myRoutes()
  local side = mySide()
  local list = {}
  for _, route in ipairs(ns.routes or {}) do
    if not route.side or route.side == side then list[#list + 1] = route end
  end
  return list
end
ns.MyRoutes = myRoutes

local function routeBySlug(slug)
  for _, route in ipairs(myRoutes()) do
    if route.slug == slug then return route end
  end
end

local function stopsOf(route)
  return route.steps
end

local function progress()
  WoWForeverBuildsCharDB = WoWForeverBuildsCharDB or {}
  WoWForeverBuildsCharDB.routes = WoWForeverBuildsCharDB.routes or {}
  return WoWForeverBuildsCharDB.routes
end

--- Index of the stop you are on; one past the last means the route is done.
local function currentIndex(route)
  return progress()[route.slug] or 1
end

local function hasItem(route)
  if not route.item or type(GetItemCount) ~= "function" then return false end
  local ok, count = pcall(GetItemCount, route.item)
  return ok and (count or 0) > 0
end

local function isDone(route)
  return currentIndex(route) > #route.steps or hasItem(route)
end

-- Map ids ------------------------------------------------------------------------------------------

local mapIds = {}
--- The uiMapID for a stop: the Classic id if its name matches, otherwise found by zone name.
local function mapIdOf(step)
  if mapIds[step.zone] ~= nil then return mapIds[step.zone] or nil end
  if not (C_Map and C_Map.GetMapInfo) then return step.map end
  local info = step.map and C_Map.GetMapInfo(step.map)
  if info and info.name == step.zone then
    mapIds[step.zone] = step.map
    return step.map
  end
  for id = 1, 3000 do
    local candidate = C_Map.GetMapInfo(id)
    if candidate and candidate.name == step.zone and (candidate.mapType == nil or candidate.mapType == 3) then
      mapIds[step.zone] = id
      return id
    end
  end
  mapIds[step.zone] = false
  return nil
end

--- Where the player stands on the stop's map, in map percent, or nil when on another map.
local function playerAt(step)
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local id = mapIdOf(step)
  if not id or C_Map.GetBestMapForUnit("player") ~= id then return nil end
  local position = C_Map.GetPlayerMapPosition(id, "player")
  if not position then return nil end
  local x, y = position:GetXY()
  if not x then return nil end
  return x * 100, y * 100
end

local function distanceTo(step)
  local x, y = playerAt(step)
  if not x then return nil end
  return math.sqrt((x - step.x) ^ 2 + (y - step.y) ^ 2)
end

-- Waypoints ----------------------------------------------------------------------------------------

local tomtomWaypoint
local function clearWaypoint()
  if tomtomWaypoint and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomWaypoint) end
  tomtomWaypoint = nil
end

--- quiet: put the pin back without a chat line (after a loading screen).
local function setWaypoint(route, step, number, quiet)
  clearWaypoint()
  local label = ("%s %d: %s"):format(route.name, number, step.title)
  local where = ("%s %.1f, %.1f"):format(step.zone, step.x, step.y)
  local id = mapIdOf(step)
  if id and TomTom and TomTom.AddWaypoint and (not ns.Option or ns.Option("routeTomTom", true)) then
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, id, step.x / 100, step.y / 100, { title = label, persistent = false, minimap = true, world = true })
    if ok and uid then
      tomtomWaypoint = uid
      if not quiet then say(("TomTom arrow set: %s (%s)"):format(label, where)) end
      return
    end
  end
  if id and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(id, step.x / 100, step.y / 100))
    if ok then
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
      if not quiet then say(("Map pin set: %s (%s)"):format(label, where)) end
      return
    end
  end
  say(("Next stop: %s — %s"):format(label, where))
end

-- Moving along ------------------------------------------------------------------------------------

local refresh
local arrivedAt = {}
-- Quests picked up at the current stop; a stop with quests = 2 waits for both.
local acceptedAt = {}

local function goTo(route, index)
  local stops = stopsOf(route)
  index = math.max(1, math.min(index, #stops + 1))
  progress()[route.slug] = index
  arrivedAt[route.slug] = nil
  acceptedAt[route.slug] = 0
  if index > #stops then
    clearWaypoint()
    say(("%s route finished."):format(route.name))
  else
    setWaypoint(route, stops[index], index)
  end
  if refresh then refresh() end
end

local function activeRoute()
  local slug = progress().active
  local route = slug and routeBySlug(slug)
  if route and not isDone(route) then return route end
end

local function start(route)
  progress().active = route.slug
  selectedSlug = route.slug
  goTo(route, currentIndex(route))
end

--- Once a second: tell the player when they reach the stop.
local function checkArrival()
  local route = activeRoute()
  if not route then return end
  local index = currentIndex(route)
  local step = stopsOf(route)[index]
  if not step or arrivedAt[route.slug] == index then return end
  local distance = distanceTo(step)
  if distance and distance <= ARRIVE_RADIUS then
    arrivedAt[route.slug] = index
    if not ns.Option or ns.Option("routeChat", true) then
      say(("%sStop %d/%d reached:|r %s"):format(GOLD, index, #route.steps, step.text))
    end
    if refresh then refresh() end
  end
end

--- A quest accepted near the current stop is that stop's quest, so move on once it has all of them.
local function onQuestAccepted()
  local route = activeRoute()
  if not route then return end
  local index = currentIndex(route)
  local step = stopsOf(route)[index]
  local distance = step and distanceTo(step)
  if not distance or distance > QUEST_RADIUS or index >= #route.steps then return end
  acceptedAt[route.slug] = (acceptedAt[route.slug] or 0) + 1
  if acceptedAt[route.slug] >= (step.quests or 1) then goTo(route, index + 1) end
end

local function onBagUpdate()
  local route = activeRoute()
  if not route and progress().active then
    local finished = routeBySlug(progress().active)
    if finished and hasItem(finished) and currentIndex(finished) <= #finished.steps then
      progress()[finished.slug] = #finished.steps + 1
      clearWaypoint()
      say(("%s%s is in your bags. Route finished.|r"):format(GREEN, finished.item))
      if refresh then refresh() end
    end
  end
end

-- Panel -------------------------------------------------------------------------------------------
-- Fixed header (route, reward, progress bar), then a scrolling list: the stops as numbered cards
-- (the current one open, the others open on click), what the reward does, and the links as
-- read-only text boxes so they can be copied.

local expanded = {} -- route slug -> the stop opened by hand (0 = all closed)
local BODY_WIDTH = ROW_WIDTH - 50

local function stepRow(index)
  local row = rows[index]
  if row then return row end
  row = CreateFrame("Button", nil, panel.content)
  row:SetWidth(ROW_WIDTH)
  row.baseAlpha = 0.03
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.stripe = row:CreateTexture(nil, "ARTWORK")
  row.stripe:SetPoint("TOPLEFT")
  row.stripe:SetPoint("BOTTOMLEFT")
  row.stripe:SetWidth(3)
  row.stripe:SetColorTexture(0.25, 0.9, 0.25, 0.9)

  row.badge = row:CreateTexture(nil, "ARTWORK")
  row.badge:SetSize(24, 24)
  row.badge:SetPoint("TOPLEFT", 10, -7)
  row.badge:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  row.number = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.number:SetPoint("CENTER", row.badge, "CENTER", 0, 0)
  row.number:SetTextColor(0, 0, 0)
  row.check = row:CreateTexture(nil, "OVERLAY")
  row.check:SetSize(18, 18)
  row.check:SetPoint("CENTER", row.badge, "CENTER")
  row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")

  row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  row.title:SetPoint("TOPLEFT", 42, -6)
  row.title:SetWidth(BODY_WIDTH - 90)
  row.title:SetJustifyH("LEFT")
  row.state = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  row.state:SetPoint("TOPRIGHT", -8, -8)
  row.state:SetJustifyH("RIGHT")
  row.place = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  row.place:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
  row.place:SetWidth(BODY_WIDTH)
  row.place:SetJustifyH("LEFT")
  row.body = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.body:SetPoint("TOPLEFT", row.place, "BOTTOMLEFT", 0, -6)
  row.body:SetWidth(BODY_WIDTH)
  row.body:SetJustifyH("LEFT")
  row.body:SetSpacing(2)
  row.make = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.make:SetSize(190, 20)
  row.make:SetText("Make this the current stop")

  row:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, self.baseAlpha + 0.05) end)
  row:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, self.baseAlpha) end)
  rows[index] = row
  return row
end

--- A copyable link: a label and a read-only text box; clicking it selects the address for Ctrl+C.
local function linkRow(index)
  panel.linkRows = panel.linkRows or {}
  local link = panel.linkRows[index]
  if link then return link end
  link = {}
  link.label = panel.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  link.label:SetJustifyH("LEFT")
  link.box = CreateFrame("EditBox", nil, panel.content, "InputBoxTemplate")
  link.box:SetSize(ROW_WIDTH - 24, 20)
  link.box:SetAutoFocus(false)
  link.box:SetFontObject("GameFontHighlightSmall")
  link.box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  link.box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
  link.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  link.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  -- Read-only: typing puts the address back.
  link.box:SetScript("OnTextChanged", function(self, byUser)
    if byUser and self.url then
      self:SetText(self.url)
      self:HighlightText()
    end
  end)
  panel.linkRows[index] = link
  return link
end

local function place(region, y, x)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", panel.content, "TOPLEFT", x or 0, -y)
end

refresh = function()
  if not panel or not panel:IsShown() then return end
  local route = routeBySlug(selectedSlug) or myRoutes()[1]
  if not route then return end
  selectedSlug = route.slug
  for _, button in ipairs(routeButtons) do
    button:SetText(button.route.slug == route.slug and (GOLD .. button.route.name .. "|r") or button.route.name)
  end

  local stops = stopsOf(route)
  local index = currentIndex(route)
  local done = isDone(route)
  local tracking = progress().active == route.slug and not done

  -- Header.
  panel.title:SetText(route.name)
  panel.level:SetText(("suggested level %d"):format(route.level or 1))
  panel.reward:SetText(route.reward and (GREEN .. route.reward .. "|r") or "")
  local finished = done and #stops or math.min(index - 1, #stops)
  panel.bar:SetMinMaxValues(0, #stops)
  panel.bar:SetValue(finished)
  if done then
    panel.bar:SetStatusBarColor(0.25, 0.8, 0.25)
    panel.barText:SetText((route.item or "Route") .. " collected — route done")
  elseif tracking then
    panel.bar:SetStatusBarColor(0.9, 0.7, 0.1)
    panel.barText:SetText(("Stop %d of %d  ·  %s"):format(index, #stops, stops[index].zone))
  else
    panel.bar:SetStatusBarColor(0.5, 0.5, 0.5)
    panel.barText:SetText(index > 1 and ("Paused at stop %d of %d — press Start"):format(index, #stops) or "Not started — press Start for the first waypoint")
  end

  -- Stops.
  local y = 4
  place(panel.stopsHeading, y)
  panel.stopsHeading:SetText(GOLD .. "STOPS|r   " .. GREY .. "click a stop to open or close it|r")
  y = y + 20
  local open = expanded[route.slug] or (not done and index) or nil
  for i, step in ipairs(stops) do
    local row = stepRow(i)
    local isDoneStep = done or i < index
    local isCurrent = not done and i == index
    row.baseAlpha = isCurrent and 0.1 or 0.03
    row.bg:SetColorTexture(1, 1, 1, row.baseAlpha)
    if isCurrent then row.stripe:Show() else row.stripe:Hide() end
    if isDoneStep then
      row.badge:SetVertexColor(0.35, 0.35, 0.35)
      row.number:SetText("")
      row.check:Show()
    elseif isCurrent then
      row.badge:SetVertexColor(0.25, 0.9, 0.25)
      row.number:SetText(i)
      row.check:Hide()
    else
      row.badge:SetVertexColor(1, 0.82, 0)
      row.number:SetText(i)
      row.check:Hide()
    end
    row.title:SetText((isDoneStep and GREY or isCurrent and WHITE or "|cffe6c878") .. step.title .. "|r")
    row.place:SetText(("%s  %.1f, %.1f"):format(step.zone, step.x, step.y))
    if isCurrent then
      row.state:SetText(GREEN .. (arrivedAt[route.slug] == i and "you are here" or "next stop") .. "|r")
    else
      row.state:SetText(isDoneStep and (GREY .. "done|r") or "")
    end
    local isOpen = open == i
    local height = 12 + row.title:GetStringHeight() + 2 + row.place:GetStringHeight()
    if isOpen then
      row.body:SetText(step.text)
      row.body:Show()
      height = height + 6 + row.body:GetStringHeight()
      if not isCurrent then
        row.make:ClearAllPoints()
        row.make:SetPoint("TOPLEFT", row.body, "BOTTOMLEFT", 0, -8)
        row.make:SetScript("OnClick", function()
          progress().active = route.slug
          expanded[route.slug] = nil
          goTo(route, i)
        end)
        row.make:Show()
        height = height + 30
      else
        row.make:Hide()
      end
    else
      row.body:SetText("")
      row.body:Hide()
      row.make:Hide()
    end
    height = math.max(height + 8, 38)
    row:SetScript("OnClick", function()
      expanded[route.slug] = (open == i) and 0 or i
      refresh()
    end)
    row:SetHeight(height)
    place(row, y)
    row:Show()
    y = y + height + 4
  end
  for i = #stops + 1, #rows do rows[i]:Hide() end

  -- About the reward.
  y = y + 12
  place(panel.aboutHeading, y)
  panel.aboutHeading:SetText(GOLD .. "ABOUT THE REWARD|r")
  y = y + 18
  local about = {}
  for _, line in ipairs(route.about or {}) do about[#about + 1] = "•  " .. line end
  panel.about:SetText(table.concat(about, "\n"))
  place(panel.about, y, 4)
  y = y + panel.about:GetStringHeight() + 16

  -- Sources and links.
  place(panel.linksHeading, y)
  panel.linksHeading:SetText(GOLD .. "SOURCES|r   " .. GREY .. "click a link, then Ctrl+C to copy it|r")
  y = y + 18
  if route.unconfirmed then
    panel.unconfirmed:SetText(ORANGE .. route.unconfirmed .. "|r")
    place(panel.unconfirmed, y, 4)
    panel.unconfirmed:Show()
    y = y + panel.unconfirmed:GetStringHeight() + 10
  else
    panel.unconfirmed:Hide()
  end
  local links = route.links or {}
  for i, entry in ipairs(links) do
    local link = linkRow(i)
    link.label:SetText(entry.label)
    place(link.label, y, 4)
    link.label:Show()
    y = y + 15
    link.box.url = entry.url
    link.box:SetText(entry.url)
    link.box:SetCursorPosition(0)
    place(link.box, y, 10)
    link.box:Show()
    y = y + 28
  end
  for i = #links + 1, #(panel.linkRows or {}) do
    panel.linkRows[i].label:Hide()
    panel.linkRows[i].box:Hide()
  end
  panel.content:SetHeight(math.max(y + 8, 1))

  panel.start:SetText(tracking and "Waypoint" or done and "Start over" or "Start")
  panel.next:SetEnabled(tracking)
  panel.back:SetEnabled(tracking and index > 1)
end

local function button(label, width, onClick)
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(width, 24)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function build()
  if panel then return panel end
  local ok, frame = pcall(CreateFrame, "Frame", "WoWForeverBuildsRoutePanel", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not frame then
    frame = CreateFrame("Frame", "WoWForeverBuildsRoutePanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if frame.SetBackdrop then
      frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end
  panel = frame
  panel:SetSize(PANEL_WIDTH, 620)
  panel:SetPoint("CENTER", 200, 0)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetFrameStrata("HIGH")
  panel:Hide()
  if panel.TitleText then panel.TitleText:SetText("wowforeverbuilds - Route guides") end

  -- A solid backing so the text does not sit on top of the game world.
  local backing = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
  backing:SetPoint("TOPLEFT", 6, -26)
  backing:SetPoint("BOTTOMRIGHT", -6, 6)
  backing:SetColorTexture(0.05, 0.05, 0.06, 0.92)

  -- Route tabs, only when there is more than one to choose from.
  routeButtons = {}
  local top = -32
  local list = myRoutes()
  if #list > 1 then
    local x = 14
    for _, route in ipairs(list) do
      local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
      b:SetSize(math.max(110, #route.name * 7 + 20), 22)
      b:SetPoint("TOPLEFT", x, top)
      b.route = route
      b:SetText(route.name)
      b:SetScript("OnClick", function()
        selectedSlug = route.slug
        refresh()
      end)
      routeButtons[#routeButtons + 1] = b
      x = x + b:GetWidth() + 4
    end
    top = top - 28
  end

  panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  panel.title:SetPoint("TOPLEFT", 16, top - 4)
  panel.level = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  panel.level:SetPoint("BOTTOMLEFT", panel.title, "BOTTOMRIGHT", 10, 2)
  panel.reward = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  panel.reward:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
  panel.reward:SetWidth(PANEL_WIDTH - 32)
  panel.reward:SetJustifyH("LEFT")

  panel.bar = CreateFrame("StatusBar", nil, panel)
  panel.bar:SetPoint("TOPLEFT", panel.reward, "BOTTOMLEFT", 0, -10)
  panel.bar:SetSize(PANEL_WIDTH - 32, 18)
  panel.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  local barBg = panel.bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(1, 1, 1, 0.08)
  panel.barText = panel.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.barText:SetPoint("CENTER")

  panel.start = button("Start", 110, function()
    local route = routeBySlug(selectedSlug)
    if not route then return end
    if currentIndex(route) > #route.steps then progress()[route.slug] = 1 end
    expanded[route.slug] = nil
    start(route)
  end)
  panel.start:SetPoint("BOTTOMLEFT", 14, 12)
  panel.back = button("Back", 90, function()
    local route = routeBySlug(selectedSlug)
    if route then
      expanded[route.slug] = nil
      goTo(route, currentIndex(route) - 1)
    end
  end)
  panel.back:SetPoint("LEFT", panel.start, "RIGHT", 6, 0)
  panel.next = button("Next stop", 110, function()
    local route = routeBySlug(selectedSlug)
    if route then
      expanded[route.slug] = nil
      goTo(route, currentIndex(route) + 1)
    end
  end)
  panel.next:SetPoint("LEFT", panel.back, "RIGHT", 6, 0)
  local stop = button("Stop", 90, function()
    progress().active = nil
    clearWaypoint()
    say("Route guide stopped. Your progress is kept.")
    refresh()
  end)
  stop:SetPoint("BOTTOMRIGHT", -14, 12)

  local scroll = CreateFrame("ScrollFrame", "WoWForeverBuildsRouteScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", panel.bar, "BOTTOMLEFT", -2, -12)
  scroll:SetPoint("BOTTOMRIGHT", -32, 46)
  panel.content = CreateFrame("Frame", nil, scroll)
  panel.content:SetSize(ROW_WIDTH, 1)
  scroll:SetScrollChild(panel.content)

  local function section(font)
    local line = panel.content:CreateFontString(nil, "ARTWORK", font)
    line:SetWidth(ROW_WIDTH - 8)
    line:SetJustifyH("LEFT")
    return line
  end
  panel.stopsHeading = section("GameFontNormalSmall")
  panel.aboutHeading = section("GameFontNormalSmall")
  panel.about = section("GameFontHighlight")
  panel.about:SetSpacing(3)
  panel.linksHeading = section("GameFontNormalSmall")
  panel.unconfirmed = section("GameFontHighlightSmall")

  rows = {}
  panel:SetScript("OnShow", refresh)
  return panel
end

function ns.ToggleRoutePanel()
  build()
  if panel:IsShown() then
    panel:Hide()
  else
    selectedSlug = selectedSlug or progress().active
    panel:Show()
  end
end

--- /wfb route [list | next | back | stop | <number or name>]
function ns.RouteCommand(rest)
  rest = strtrim(rest or ""):lower()
  local routes = myRoutes()
  if rest == "" then return ns.ToggleRoutePanel() end
  if rest == "list" then
    for i, route in ipairs(routes) do
      say(("%d. %s (level %d)%s"):format(i, route.name, route.level or 1, isDone(route) and (GREY .. " — done|r") or ""))
    end
    return
  end
  local route = activeRoute()
  if rest == "next" or rest == "back" then
    if not route then return say("No route running. Type |cffffffff/wfb route|r to pick one.") end
    return goTo(route, currentIndex(route) + (rest == "next" and 1 or -1))
  end
  if rest == "stop" then
    progress().active = nil
    clearWaypoint()
    return say("Route guide stopped. Your progress is kept.")
  end
  local picked = routes[tonumber(rest) or 0]
  if not picked then
    for _, candidate in ipairs(routes) do
      if candidate.name:lower():find(rest, 1, true) or candidate.slug == rest then picked = candidate end
    end
  end
  if not picked then return say("No route called " .. rest .. ". Type |cffffffff/wfb route list|r.") end
  start(picked)
end

local function stopRoute()
  progress().active = nil
  clearWaypoint()
  say("Route guide stopped. Your progress is kept.")
  if refresh then refresh() end
end

-- Shared with the minimap button's menu.
function ns.StartRoute(slug)
  local route = routeBySlug(slug)
  if not route then return end
  if currentIndex(route) > #route.steps then progress()[route.slug] = 1 end
  start(route)
end
ns.StopRoute = stopRoute
function ns.ActiveRouteSlug()
  local route = activeRoute()
  return route and route.slug
end
function ns.RouteLabel(route)
  local label = ("%s (level %d)"):format(route.name, route.level or 1)
  if isDone(route) then return label .. GREY .. " — done|r" end
  if progress().active == route.slug then return label .. GOLD .. (" — stop %d/%d|r"):format(currentIndex(route), #route.steps) end
  return label
end

-- World map ---------------------------------------------------------------------------------------
-- A Routes button in the corner of the world map picks a route; the stops of the running route are
-- drawn on the map as numbered pins (on the zone map and on the continent). Click a pin to make it
-- your current stop.

local mapButton, mapMenu
local pins = {}
local previewSlug -- a route picked on the map but not started: its pins still show
local pinSignature

local function mapCanvas()
  if not WorldMapFrame then return nil end
  if WorldMapFrame.GetCanvas then
    local ok, canvas = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
    if ok and canvas then return canvas end
  end
  return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function shownMapId()
  if WorldMapFrame and WorldMapFrame.GetMapID then
    local ok, id = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
    if ok then return id end
  end
end

--- Where a stop sits on the map being shown (0-1), or nil when that map does not contain it.
local function stopOnMap(step, shownMap)
  local id = mapIdOf(step)
  if not id or not shownMap then return nil end
  if id == shownMap then return step.x / 100, step.y / 100 end
  if C_Map and C_Map.GetMapRectOnMap then
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, id, shownMap)
    if ok and minX and maxX and maxX > minX and maxY > minY then
      return minX + (maxX - minX) * step.x / 100, minY + (maxY - minY) * step.y / 100
    end
  end
end

local function mapRoute()
  return activeRoute() or routeBySlug(previewSlug)
end

local function pinFor(index, canvas)
  local pin = pins[index]
  if pin then return pin end
  pin = CreateFrame("Button", nil, canvas)
  pin:SetSize(26, 26)
  -- A dark disc behind a coloured one: a round pin with an outline, from a stock circular texture.
  pin.border = pin:CreateTexture(nil, "BORDER")
  pin.border:SetAllPoints()
  pin.border:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  pin.border:SetVertexColor(0, 0, 0, 0.9)
  pin.dot = pin:CreateTexture(nil, "ARTWORK")
  pin.dot:SetPoint("TOPLEFT", 3, -3)
  pin.dot:SetPoint("BOTTOMRIGHT", -3, 3)
  pin.dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  pin.number = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  pin.number:SetPoint("CENTER", 0, 0)
  pin.number:SetTextColor(0, 0, 0)
  pin:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.heading, 1, 0.82, 0)
    GameTooltip:AddLine(self.where, 0.6, 0.6, 0.6)
    GameTooltip:AddLine(self.text, 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: make this your current stop", 0.25, 0.85, 0.25)
    GameTooltip:Show()
  end)
  pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pins[index] = pin
  return pin
end

local function hidePins(from)
  for i = from or 1, #pins do pins[i]:Hide() end
end

local function drawPins()
  local canvas = mapCanvas()
  local route = mapRoute()
  local shown = shownMapId()
  if not canvas or not route or not shown or not WorldMapFrame:IsShown() then return hidePins() end
  local stops = stopsOf(route)
  local index = activeRoute() and currentIndex(route) or 0
  local width, height = canvas:GetWidth(), canvas:GetHeight()
  local scale = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
  local used = 0
  for i, step in ipairs(stops) do
    local x, y = stopOnMap(step, shown)
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
      used = used + 1
      local pin = pinFor(used, canvas)
      pin:SetParent(canvas)
      pin:SetFrameStrata(canvas:GetFrameStrata())
      pin:SetFrameLevel(canvas:GetFrameLevel() + 2000)
      pin:SetScale(1 / math.max(scale, 0.01))
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", canvas, "TOPLEFT", x * width * scale, -y * height * scale)
      pin.number:SetText(i)
      if i < index then
        pin.dot:SetVertexColor(0.55, 0.55, 0.55)
      elseif i == index then
        pin.dot:SetVertexColor(0.25, 0.9, 0.25)
      else
        pin.dot:SetVertexColor(1, 0.82, 0)
      end
      pin.heading = ("%s — stop %d: %s"):format(route.name, i, step.title)
      pin.where = ("%s %.1f, %.1f"):format(step.zone, step.x, step.y)
      pin.text = step.text
      pin:SetScript("OnClick", function()
        progress().active = route.slug
        previewSlug = nil
        goTo(route, i)
      end)
      pin:Show()
    end
  end
  hidePins(used + 1)
end

local function showOnMap(route)
  local step = stopsOf(route)[math.min(currentIndex(route), #route.steps)]
  local id = step and mapIdOf(step)
  if id and WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, id) end
  pinSignature = nil
end

local function mapMenuInit(_, level)
  local info = UIDropDownMenu_CreateInfo()
  info.text, info.isTitle, info.notCheckable = "WoW Forever Builds — route guides", true, true
  UIDropDownMenu_AddButton(info, level)
  local running = activeRoute()
  for _, route in ipairs(myRoutes()) do
    info = UIDropDownMenu_CreateInfo()
    info.text = ns.RouteLabel(route)
    info.checked = (running and running.slug == route.slug) or previewSlug == route.slug
    info.func = function()
      previewSlug = route.slug
      -- Once the item is in your bags the route only shows its pins.
      if not hasItem(route) then ns.StartRoute(route.slug) end
      showOnMap(route)
    end
    UIDropDownMenu_AddButton(info, level)
  end
  info = UIDropDownMenu_CreateInfo()
  info.text, info.notCheckable = "Open the route panel", true
  info.func = function()
    build()
    selectedSlug = (mapRoute() or {}).slug or selectedSlug
    panel:Show()
  end
  UIDropDownMenu_AddButton(info, level)
  if running then
    info = UIDropDownMenu_CreateInfo()
    info.text, info.notCheckable = "Stop the route", true
    info.func = function()
      previewSlug = nil
      stopRoute()
    end
    UIDropDownMenu_AddButton(info, level)
  end
end

local function buildMapButton()
  if mapButton or not WorldMapFrame then return end
  local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
  local ok, b = pcall(CreateFrame, "Button", "WoWForeverBuildsMapRoutesButton", parent, "UIPanelButtonTemplate")
  if not ok or not b then return end
  mapButton = b
  mapButton:SetSize(86, 22)
  mapButton:SetText("Routes")
  mapButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -8)
  mapButton:SetFrameLevel(parent:GetFrameLevel() + 3000)
  mapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("WoW Forever Builds route guides")
    GameTooltip:AddLine("Pick a route: its stops show on the map as numbered pins, with a waypoint on the current one.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  mapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  if UIDropDownMenu_Initialize then
    local okMenu, frame = pcall(CreateFrame, "Frame", "WoWForeverBuildsMapRoutesMenu", UIParent, "UIDropDownMenuTemplate")
    if okMenu and frame then
      mapMenu = frame
      UIDropDownMenu_Initialize(mapMenu, mapMenuInit, "MENU")
    end
  end
  mapButton:SetScript("OnClick", function(self)
    if mapMenu and ToggleDropDownMenu then
      ToggleDropDownMenu(1, nil, mapMenu, self, 0, 0)
    else
      ns.ToggleRoutePanel()
    end
  end)
end

-- Redraw when the shown map, the zoom or the route's progress changes.
local mapWatcher = CreateFrame("Frame")
local sinceMap = 0
mapWatcher:SetScript("OnUpdate", function(_, elapsed)
  sinceMap = sinceMap + elapsed
  if sinceMap < 0.2 then return end
  sinceMap = 0
  if not WorldMapFrame then return end
  buildMapButton()
  -- The options panel can take the button and the pins off the map.
  local onMap = not ns.Option or ns.Option("routeMap", true)
  if mapButton then
    if onMap then mapButton:Show() else mapButton:Hide() end
  end
  if not WorldMapFrame:IsShown() or not onMap then
    if pinSignature then
      pinSignature = nil
      hidePins()
    end
    return
  end
  local route = mapRoute()
  local canvas = mapCanvas()
  local scale = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
  local signature = table.concat({
    tostring(shownMapId()), route and route.slug or "-", route and currentIndex(route) or 0, tostring(activeRoute() ~= nil),
    canvas and math.floor(canvas:GetWidth()) or 0, math.floor(scale * 1000),
  }, ":")
  if signature ~= pinSignature then
    pinSignature = signature
    drawPins()
  end
end)

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("QUEST_ACCEPTED")
driver:RegisterEvent("BAG_UPDATE_DELAYED")
driver:SetScript("OnEvent", function(_, event)
  if event == "QUEST_ACCEPTED" then
    onQuestAccepted()
  elseif event == "BAG_UPDATE_DELAYED" then
    onBagUpdate()
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Put the waypoint back after a reload or a loading screen.
    local route = activeRoute()
    if route then setWaypoint(route, stopsOf(route)[currentIndex(route)], currentIndex(route), true) end
  end
end)
local since = 0
driver:SetScript("OnUpdate", function(_, elapsed)
  since = since + elapsed
  if since < 1 then return end
  since = 0
  checkArrival()
end)
