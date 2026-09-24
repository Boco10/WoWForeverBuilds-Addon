-- The addon's page in the game's Options > AddOns list: on/off switches for every part of the addon,
-- and dropdowns to pick the talent guide and the route guide. Also opened with /wfb options.
-- Switches are account-wide (WoWForeverBuildsDB.options); the talent guide choice is per character.
local _, ns = ...

local TITLE = "WoW Forever Builds"
local WIDTH = 600
local GREY = "|cff8a8a8a"

--- An account-wide option, with the value used while it has never been changed.
function ns.Option(key, default)
  local options = WoWForeverBuildsDB and WoWForeverBuildsDB.options
  local value = options and options[key]
  if value == nil then return default end
  return value
end

function ns.SetOption(key, value)
  WoWForeverBuildsDB = WoWForeverBuildsDB or {}
  WoWForeverBuildsDB.options = WoWForeverBuildsDB.options or {}
  WoWForeverBuildsDB.options[key] = value
end

local frame, content, category
local controls = {}
local y = 0
local dropdownCount = 0

local function heading(text)
  y = y + 14
  local line = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  line:SetPoint("TOPLEFT", 0, -y)
  line:SetText(text)
  y = y + 26
end

local function note(text)
  local line = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  line:SetPoint("TOPLEFT", 4, -y)
  line:SetWidth(WIDTH - 20)
  line:SetJustifyH("LEFT")
  line:SetText(GREY .. text .. "|r")
  y = y + line:GetStringHeight() + 8
end

--- A tick box. get() reads the current value, set(value) applies it.
local function checkbox(label, tooltip, get, set)
  local box = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
  box:SetSize(26, 26)
  box:SetPoint("TOPLEFT", 0, -y)
  box.label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  box.label:SetPoint("LEFT", box, "RIGHT", 4, 1)
  box.label:SetText(label)
  box:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    if frame.Refresh then frame:Refresh() end
  end)
  if tooltip then
    box:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(label)
      GameTooltip:AddLine(tooltip, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  box.update = function() box:SetChecked(get() and true or false) end
  controls[#controls + 1] = box
  y = y + 28
  return box
end

--- A dropdown. items() returns { { text =, value =, checked = }, ... } and a label for the closed box;
--- pick(value) applies a choice.
local function dropdown(label, items, pick)
  local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", 4, -y - 6)
  text:SetText(label)
  dropdownCount = dropdownCount + 1
  local ok, menu = pcall(CreateFrame, "Frame", "WoWForeverBuildsOptionsDropdown" .. dropdownCount, content, "UIDropDownMenuTemplate")
  if not ok or not menu then
    y = y + 30
    return
  end
  menu:SetPoint("TOPLEFT", 150, -y)
  UIDropDownMenu_SetWidth(menu, 330)
  UIDropDownMenu_Initialize(menu, function(_, level)
    local list = items()
    for _, item in ipairs(list) do
      local info = UIDropDownMenu_CreateInfo()
      info.text, info.checked = item.text, item.checked
      info.func = function()
        pick(item.value)
        CloseDropDownMenus()
        if frame.Refresh then frame:Refresh() end
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  menu.update = function()
    local _, shown = items()
    UIDropDownMenu_SetText(menu, shown or "")
  end
  controls[#controls + 1] = menu
  y = y + 34
end

local function button(label, width, onClick, x)
  local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  b:SetSize(width, 24)
  b:SetPoint("TOPLEFT", x or 0, -y)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function call(fn, ...)
  if type(fn) == "function" then pcall(fn, ...) end
end

--- For the buttons that open another window: close the options first so it is not hidden behind them.
local function open(fn, ...)
  if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then
    HideUIPanel(SettingsPanel)
  elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() and HideUIPanel then
    HideUIPanel(InterfaceOptionsFrame)
  end
  call(fn, ...)
end

-- The talent guide dropdown: this class's guides, the one in use ticked.
local function talentItems()
  local list, current = nil, nil
  if ns.TalentGuideChoices then list, current = ns.TalentGuideChoices() end
  if not list or #list == 0 then return {}, "No guides for this class yet" end
  local items = {}
  for index, guide in ipairs(list) do
    items[#items + 1] = {
      text = ("%s  %s(%s, %d-%d)|r"):format(guide.title, GREY, guide.kind or "guide", guide.from or 1, guide.to or 60),
      value = index,
      checked = index == current,
    }
  end
  local shown = current and list[current] and list[current].title or "Pick a guide"
  if ns.TalentGuideEnabled and ns.TalentGuideEnabled() == false then shown = "Off — tick the box above to turn it on" end
  return items, shown
end

-- The route dropdown: this faction's routes; picking one starts it.
local function routeItems()
  local routes = ns.MyRoutes and ns.MyRoutes() or {}
  local active = ns.ActiveRouteSlug and ns.ActiveRouteSlug()
  local items, shown = {}, "No route running"
  for _, route in ipairs(routes) do
    local text = ns.RouteLabel and ns.RouteLabel(route) or route.name
    items[#items + 1] = { text = text, value = route.slug, checked = route.slug == active }
    if route.slug == active then shown = route.name end
  end
  return items, shown
end

local function build()
  if frame then return end
  frame = CreateFrame("Frame", "WoWForeverBuildsOptions", UIParent)
  frame.name = TITLE
  frame:Hide()

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(TITLE)
  local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  version:SetPoint("LEFT", title, "RIGHT", 10, -2)
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local okVersion, number = pcall(getMeta, "WoWForeverBuilds", "Version")
  version:SetText(okVersion and number and ("v" .. number) or "")

  local scroll = CreateFrame("ScrollFrame", "WoWForeverBuildsOptionsScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -50)
  scroll:SetPoint("BOTTOMRIGHT", -30, 10)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(WIDTH, 1)
  scroll:SetScrollChild(content)

  note("Talent guides, a dungeon quest panel, route guides with waypoints, and character export for wowforeverbuilds.com. Type /wfb in chat for the commands.")

  heading("General")
  checkbox("Show the minimap icon", "Left click opens the route guides, right click a menu with everything the addon does.",
    function() return not ns.MinimapShown or ns.MinimapShown() end,
    function(value) call(ns.SetMinimapShown, value) end)
  button("Reset icon position", 150, function() call(ns.ResetMinimapPosition) end, 30)
  button("Character export", 150, function() open(ns.ShowExport) end, 186)
  y = y + 30

  heading("Talent guide")
  checkbox("Show the talent guide in the talent window", "The next talent glows, talents show the level of their next point, and a panel lists the order.",
    function() return ns.TalentGuideEnabled and ns.TalentGuideEnabled() end,
    function(value) call(ns.GuideCommand, value and "on" or "off") end)
  dropdown("Guide", talentItems, function(index) call(ns.GuideCommand, tostring(index)) end)
  checkbox("Show the order panel beside the talent window", nil,
    function() return ns.TalentGuidePanelShown and ns.TalentGuidePanelShown() end,
    function(value) call(ns.SetTalentGuidePanelShown, value) end)
  checkbox("Chat: what to take on level up, and a warning off the guide", nil,
    function() return ns.Option("guideChat", true) end,
    function(value) ns.SetOption("guideChat", value) end)
  button("Open the talent window", 180, function() open(ns.ToggleTalents) end, 30)
  y = y + 30

  heading("Dungeon Quest helper")
  checkbox("Open the quest panel with the group finder", "Off: the panel only opens from the Quest helper button or /wfb quests.",
    function() return ns.Option("questAutoOpen", true) end,
    function(value) ns.SetOption("questAutoOpen", value) end)
  checkbox("Mark dungeon quests in the quest log with [D]", "Takes effect the next time the quest log redraws; /reload clears marks already shown.",
    function() return ns.Option("questLogTags", true) end,
    function(value) ns.SetOption("questLogTags", value) end)
  button("Open the quest panel", 180, function() open(ns.ToggleQuestPanel) end, 30)
  y = y + 30

  heading("Route guides")
  dropdown("Route", routeItems, function(slug) call(ns.StartRoute, slug) end)
  checkbox("Show the Routes button and the stop pins on the world map", nil,
    function() return ns.Option("routeMap", true) end,
    function(value) ns.SetOption("routeMap", value) end)
  checkbox("Chat: what to do when you reach a stop", nil,
    function() return ns.Option("routeChat", true) end,
    function(value) ns.SetOption("routeChat", value) end)
  checkbox("Use a TomTom arrow when TomTom is installed", "Off: the game's own map pin is used instead.",
    function() return ns.Option("routeTomTom", true) end,
    function(value) ns.SetOption("routeTomTom", value) end)
  button("Open the route panel", 180, function() open(ns.ToggleRoutePanel) end, 30)
  button("Stop the route", 150, function() call(ns.StopRoute) end, 216)
  y = y + 40

  content:SetHeight(y)
  frame.Refresh = function()
    for _, control in ipairs(controls) do control.update() end
  end
  frame:SetScript("OnShow", frame.Refresh)
  -- Older option windows call these.
  frame.refresh = frame.Refresh
  frame.okay, frame.cancel, frame.default = function() end, function() end, function() end

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    category = Settings.RegisterCanvasLayoutCategory(frame, TITLE)
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(frame)
  end
end

function ns.OpenOptions()
  build()
  if Settings and Settings.OpenToCategory and category then
    local id = category.GetID and category:GetID() or category.ID
    pcall(Settings.OpenToCategory, id)
  elseif InterfaceOptionsFrame_OpenToCategory then
    -- Called twice: the first call only opens the window on some clients.
    InterfaceOptionsFrame_OpenToCategory(frame)
    InterfaceOptionsFrame_OpenToCategory(frame)
  end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", build)
