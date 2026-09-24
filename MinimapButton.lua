-- The minimap icon: left click opens the route guides, right click a menu with everything the addon
-- does. Drag it around the minimap edge; /wfb minimap hides or shows it. No libraries needed.
local _, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local PREFIX = "|cffd4a84bWoW Forever Builds|r "
local button, menu
-- WoW's Lua 5.1 has math.atan2; the fallback keeps the file working on newer Lua.
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function settings()
  WoWForeverBuildsDB = WoWForeverBuildsDB or {}
  WoWForeverBuildsDB.minimap = WoWForeverBuildsDB.minimap or { angle = 200 }
  return WoWForeverBuildsDB.minimap
end

local function place()
  local angle = math.rad(settings().angle or 200)
  local radius = Minimap:GetWidth() / 2 + 10
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  settings().angle = math.deg(atan2(cy / scale - my, cx / scale - mx))
  place()
end

local function call(fn, ...)
  if type(fn) == "function" then pcall(fn, ...) end
end

local function menuInit(_, level)
  local function add(text, func, extra)
    local info = UIDropDownMenu_CreateInfo()
    info.text, info.func, info.notCheckable = text, func, true
    for k, v in pairs(extra or {}) do info[k] = v end
    UIDropDownMenu_AddButton(info, level)
  end
  add("WoW Forever Builds", nil, { isTitle = true })
  add("Route guides", function() call(ns.ToggleRoutePanel) end)
  local active = ns.ActiveRouteSlug and ns.ActiveRouteSlug()
  for _, route in ipairs(ns.MyRoutes and ns.MyRoutes() or {}) do
    add("   " .. (ns.RouteLabel and ns.RouteLabel(route) or route.name), function() call(ns.StartRoute, route.slug) end,
      { notCheckable = false, checked = active == route.slug })
  end
  if active then add("   Stop the route", function() call(ns.StopRoute) end) end
  add("Dungeon Quest helper", function() call(ns.ToggleQuestPanel) end)
  local guideOn = ns.TalentGuideEnabled and ns.TalentGuideEnabled()
  if guideOn ~= nil then
    add("Talent guide in the talent window", function()
      call(ns.GuideCommand, guideOn and "off" or "on")
    end, { notCheckable = false, isNotRadio = true, checked = guideOn })
  end
  add("Open the talent window", function() call(ns.ToggleTalents) end)
  add("Character export", function() call(ns.ShowExport) end)
  add("Settings", function() call(ns.OpenOptions) end)
  add("Hide this icon", function()
    settings().hide = true
    button:Hide()
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "minimap icon hidden. |cffffffff/wfb minimap|r brings it back.")
  end)
end

local function build()
  if button or not Minimap then return end
  button = CreateFrame("Button", "WoWForeverBuildsMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetSize(20, 20)
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetPoint("TOPLEFT", 7, -5)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture(ICON)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  icon:SetPoint("TOPLEFT", 7, -6)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")

  if UIDropDownMenu_Initialize then
    local ok, frame = pcall(CreateFrame, "Frame", "WoWForeverBuildsMinimapMenu", UIParent, "UIDropDownMenuTemplate")
    if ok and frame then
      menu = frame
      UIDropDownMenu_Initialize(menu, menuInit, "MENU")
    end
  end

  button:SetScript("OnClick", function(self, mouse)
    GameTooltip:Hide()
    if mouse == "RightButton" and menu and ToggleDropDownMenu then
      ToggleDropDownMenu(1, nil, menu, self, 0, 0)
    else
      call(ns.ToggleRoutePanel)
    end
  end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", onDragUpdate)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("WoW Forever Builds")
    GameTooltip:AddLine("Left click: route guides", 1, 1, 1)
    GameTooltip:AddLine("Right click: quest helper, talent guide, export", 1, 1, 1)
    GameTooltip:AddLine("Drag: move the icon", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  place()
  if settings().hide then button:Hide() end
end

--- For the options panel.
function ns.MinimapShown()
  return not settings().hide
end
function ns.SetMinimapShown(shown)
  build()
  settings().hide = not shown or nil
  if not button then return end
  if shown then
    button:Show()
    place()
  else
    button:Hide()
  end
end
function ns.ResetMinimapPosition()
  settings().angle = 200
  if button then place() end
end

--- /wfb minimap: show or hide the icon.
function ns.MinimapCommand()
  build()
  if not button then return end
  settings().hide = not settings().hide or nil
  if settings().hide then
    button:Hide()
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "minimap icon hidden. |cffffffff/wfb minimap|r brings it back.")
  else
    button:Show()
    place()
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "minimap icon shown.")
  end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", build)
