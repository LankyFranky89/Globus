-- Globus: a clean, borderless world map for WoW Forever.
-- Only the map and quest tracking stay (quest areas, quest icons, you and your group).
-- Mouse wheel zooms toward the cursor, far past the normal limit. Drag the top edge to
-- move, drag the bottom-right corner to resize. Works with Quest Ledger Forever and QuestMates.
local ADDON, NS = ...
local DB

local function Print(msg) print("|cff4fc3f7Globus:|r " .. msg) end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------- settings
local DEFAULTS = {
  zoom = 8,        -- how far past the game's own max zoom you can go (x times)
  scale = 1,       -- window size
  alpha = 1,       -- map transparency
  allPins = false, -- true = show every map icon again (flight points, dungeons, ...)
  locked = false,  -- true = no moving / resizing
  mini = false,    -- mini mode: small, see-through, stays open while you play
  miniScale = 0.5,
  miniAlpha = 0.6,
  coords = true, crumbs = true, zoomBar = true, zoomBarHover = true, follow = false, zoneLevels = true,
  questFilter = "all", questRings = false, modernQuest = false, nearestLine = true, partyNames = true, ping = true,
  waypoint = true, fadeMoving = true, fadeAlpha = 0.35,
  terrain = true, terrainAlpha = 0.85,
}
NS.DEFAULTS = DEFAULTS
NS.Print = function(m) print("|cff4fc3f7Globus:|r " .. m) end

---------------------------------------------------------------- helpers
local function SC() return WorldMapFrame and WorldMapFrame.ScrollContainer end

-- turn a frame (and everything inside it) invisible and click-through
local function Mute(fr, depth)
  if not fr or depth > 6 then return end
  if fr.SetAlpha then fr:SetAlpha(0) end
  if fr.EnableMouse then pcall(fr.EnableMouse, fr, false) end
  if fr.EnableMouseWheel then pcall(fr.EnableMouseWheel, fr, false) end
  if fr.GetChildren then
    for _, c in ipairs({ fr:GetChildren() }) do Mute(c, depth + 1) end
  end
end

---------------------------------------------------------------- the visible map frame
-- A click-through frame lying exactly over the map area. It draws the thin edge and
-- carries the move bar, close button, resize grip (and QuestMates' corner icon).
local view

function Globus_GetMapFrame() return view end

local function MakeView()
  if view or not SC() then return end
  local sc = SC()
  view = CreateFrame("Frame", "GlobusMapFrame", WorldMapFrame)
  view:SetAllPoints(sc)
  view:EnableMouse(false)
  -- above the map's own icons and QuestMates' dots
  view:SetFrameLevel(math.min(sc:GetFrameLevel() + 3000, 9000))

  -- thin dark edge with a soft gold inner line
  local function line(r, g, b, a, p1, p2, x, y, w, h)
    local t = view:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8X8"); t:SetVertexColor(r, g, b, a)
    t:SetPoint(p1, view, p1, x, y); t:SetPoint(p2, view, p2, x, y)
    if w then t:SetWidth(w) else t:SetHeight(h) end
    return t
  end
  -- thin gold edge (dark line inside it for contrast with the map art)
  line(0.78, 0.62, 0.22, 1, "TOPLEFT", "TOPRIGHT", 0, 0, nil, 1)
  line(0.78, 0.62, 0.22, 1, "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, nil, 1)
  line(0.78, 0.62, 0.22, 1, "TOPLEFT", "BOTTOMLEFT", 0, 0, 1, nil)
  line(0.78, 0.62, 0.22, 1, "TOPRIGHT", "BOTTOMRIGHT", 0, 0, 1, nil)
  line(0, 0, 0, 0.6, "TOPLEFT", "TOPRIGHT", 0, -1, nil, 1)
  line(0, 0, 0, 0.6, "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1, nil, 1)
  line(0, 0, 0, 0.6, "TOPLEFT", "BOTTOMLEFT", 1, 0, 1, nil)
  line(0, 0, 0, 0.6, "TOPRIGHT", "BOTTOMRIGHT", -1, 0, 1, nil)
  -- soft dark shadow outside the frame
  if CreateColor then
    local shadow = CreateFrame("Frame", nil, WorldMapFrame)
    shadow:SetFrameLevel(math.max(0, sc:GetFrameLevel() - 1))
    shadow:SetFrameStrata(WorldMapFrame:GetFrameStrata())
    local SH = 10
    local function strip(p1, a1, p2, a2, x1, y1, x2, y2, orient, dark, clear)
      local t = shadow:CreateTexture(nil, "BACKGROUND")
      t:SetTexture("Interface\\Buttons\\WHITE8X8")
      t:SetPoint(p1, view, a1, x1, y1); t:SetPoint(p2, view, a2, x2, y2)
      if t.SetGradient then t:SetGradient(orient, dark, clear) else t:Hide() end
    end
    local D, C = CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0)
    strip("TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, 0, -SH, "VERTICAL", C, D)  -- below
    strip("BOTTOMLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", 0, 0, 0, SH, "VERTICAL", D, C)        -- above
    strip("TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, SH, 0, "HORIZONTAL", D, C)  -- right
    strip("TOPRIGHT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, -SH, 0, "HORIZONTAL", C, D)   -- left
  end

  -- controls: hidden until the mouse is over the map
  local controls = CreateFrame("Frame", "GlobusControls", view)
  controls:SetAllPoints()
  controls:SetFrameLevel(view:GetFrameLevel() + 50)
  controls:SetAlpha(0)
  view.controls = controls

  -- toolbar along the top edge: dark Blizzard-style strip with gold trim (drag it to move the map)
  local bar = CreateFrame("Frame", nil, controls)
  bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(24)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints(); bar.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  bar.bg:SetVertexColor(0.04, 0.03, 0.02, 0.88)
  local function gold(p1, p2, y)
    local t = bar:CreateTexture(nil, "BORDER")
    t:SetTexture("Interface\\Buttons\\WHITE8X8"); t:SetVertexColor(0.78, 0.62, 0.22, 0.9)
    t:SetPoint(p1, bar, p1, 0, y); t:SetPoint(p2, bar, p2, 0, y); t:SetHeight(1)
    return t
  end
  bar.line = gold("BOTTOMLEFT", "BOTTOMRIGHT", 0)
  bar.shine = gold("TOPLEFT", "TOPRIGHT", 0); bar.shine:SetVertexColor(0.78, 0.62, 0.22, 0.45)
  bar.txt = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bar.txt:SetPoint("LEFT", 10, 0); bar.txt:SetText("drag to move")
  bar:EnableMouse(true) -- the top strip can always be dragged to move the map
  bar:RegisterForDrag("LeftButton")
  view.bar = bar

  -- close button, right end of the toolbar: the game's own red X
  local close = CreateFrame("Button", nil, controls, "UIPanelCloseButton")
  close:SetSize(26, 26)
  close:SetPoint("RIGHT", bar, "RIGHT", 2, 0)
  close:SetFrameLevel(bar:GetFrameLevel() + 5)
  close:EnableMouse(false)
  close:SetScript("OnClick", function()
    if ToggleWorldMap then ToggleWorldMap() else HideUIPanel(WorldMapFrame) end
  end)
  view.close = close

  -- resize grip, bottom-right corner
  local grip = CreateFrame("Button", nil, controls)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  -- small gold corner piece
  grip.tex = grip:CreateTexture(nil, "ARTWORK")
  grip.tex:SetTexture("Interface\\AddOns\\Globus\\Grip"); grip.tex:SetAllPoints()
  grip.tex:SetVertexColor(0.85, 0.68, 0.25, 0.95)
  grip:SetScript("OnEnter", function(s) s.tex:SetVertexColor(1, 0.86, 0.35, 1) end)
  grip:SetScript("OnLeave", function(s) s.tex:SetVertexColor(0.85, 0.68, 0.25, 0.95) end)
  grip:EnableMouse(false)
  view.grip = grip

  -- fade the controls in while hovering the map (or while dragging)
  local shown = false
  view:SetScript("OnUpdate", function()
    local want = view.busy or view:IsMouseOver()
    if want == shown then return end
    shown = want
    controls:SetAlpha(want and 1 or 0)
    bar:EnableMouse(not DB.locked); close:EnableMouse(want); grip:EnableMouse(want and not DB.locked)
    grip:SetShown(not DB.locked)
    if NS.OnControlsShown then NS.OnControlsShown(want) end
  end)
  -- lock changes while hovering: re-check
  view.RefreshControls = function() shown = nil end
  NS.view, NS.controls = view, controls
end

---------------------------------------------------------------- position and size
local function FilterPinsLater() C_Timer.After(0, function() if NS.FilterPins then NS.FilterPins() end end) end
local function SavePos()
  local l, t = WorldMapFrame:GetLeft(), WorldMapFrame:GetTop()
  if not (l and t) then return end -- in the map's own scale, from the screen's bottom-left
  if DB.mini then DB.miniPos = { l, t } else DB.pos = { l, t } end
end

local function Redock()
  if QuestLedgerForever_Dock then pcall(QuestLedgerForever_Dock) end
end
NS.Redock = Redock

-- Window size. Real resize when the game supports it (map icons keep their size and quest
-- areas stay in place); otherwise the whole window is scaled.
local baseW, baseH, insetW, insetH
local noSize -- set if the map's inside doesn't follow the window size (then we scale instead)
local function SizeMode() return not noSize and WorldMapFrame.OnFrameSizeChanged ~= nil and baseW ~= nil end
local function SetFactor(f)
  if not baseW then
    local w, h = WorldMapFrame:GetSize()
    if w and w > 100 and h and h > 100 then
      baseW, baseH = w, h
      -- space the window keeps around the map area (title strip, edges); it doesn't grow
      local sc = WorldMapFrame.ScrollContainer
      local sw, sh = sc:GetWidth(), sc:GetHeight()
      insetW = (sw and sw > 0) and math.max(0, w - sw) or 0
      insetH = (sh and sh > 0) and math.max(0, h - sh) or 0
    end
  end
  if SizeMode() then
    if math.abs(WorldMapFrame:GetScale() - 1) > 0.001 then WorldMapFrame:SetScale(1) end
    -- grow only the map area, so it keeps the map's exact shape (no empty strips at the edges)
    local w = (baseW - insetW) * f + insetW
    local h = (baseH - insetH) * f + insetH
    if math.abs(WorldMapFrame:GetWidth() - w) > 0.5 or math.abs(WorldMapFrame:GetHeight() - h) > 0.5 then
      local sc = WorldMapFrame.ScrollContainer
      local before, oldW = sc:GetWidth(), WorldMapFrame:GetWidth()
      WorldMapFrame:SetSize(w, h)
      pcall(WorldMapFrame.OnFrameSizeChanged, WorldMapFrame) -- let the map re-lay out its canvas and icons
      if math.abs(w - oldW) > 20 and math.abs(sc:GetWidth() - before) < 0.5 then
        -- the map didn't grow with the window: go back to scaling the whole window
        noSize = true
        WorldMapFrame:SetSize(baseW, baseH)
        pcall(WorldMapFrame.OnFrameSizeChanged, WorldMapFrame)
        WorldMapFrame:SetScale(f)
      end
    end
  elseif math.abs(WorldMapFrame:GetScale() - f) > 0.001 then
    WorldMapFrame:SetScale(f)
  end
end
local function GetFactor()
  if SizeMode() then return (WorldMapFrame:GetWidth() - insetW) / (baseW - insetW) end
  return WorldMapFrame:GetScale()
end
NS.SizeMode = SizeMode

local function ApplyPos()
  if not (DB and WorldMapFrame) or InCombat() then return end
  if WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() then return end
  local scale = DB.mini and DB.miniScale or DB.scale
  SetFactor(scale)
  if WorldMapFrame.SetUserPlaced then pcall(WorldMapFrame.SetUserPlaced, WorldMapFrame, false) end
  local pos = DB.mini and DB.miniPos or (not DB.mini and DB.pos)
  if pos then
    pcall(function()
      WorldMapFrame:ClearAllPoints()
      WorldMapFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    end)
  elseif DB.mini then -- first time in mini mode: right side of the screen
    pcall(function()
      WorldMapFrame:ClearAllPoints()
      WorldMapFrame:SetPoint("RIGHT", UIParent, "RIGHT", -20 / scale, 0)
    end)
  end
end
NS.ApplyPos = ApplyPos

local function SetupMoveResize()
  WorldMapFrame:SetMovable(true)
  WorldMapFrame:SetClampedToScreen(true)
  local bar, grip = view.bar, view.grip

  bar:SetScript("OnDragStart", function()
    if DB.locked then return end
    if InCombat() then Print("can't move the map in combat.") return end
    view.busy = true
    -- keep only the visible map on screen, not the invisible space around it
    local l = view:GetLeft() - WorldMapFrame:GetLeft()
    local r = WorldMapFrame:GetRight() - view:GetRight()
    local t = WorldMapFrame:GetTop() - view:GetTop()
    local b = view:GetBottom() - WorldMapFrame:GetBottom()
    if l and r and t and b then WorldMapFrame:SetClampRectInsets(l, -r, -t, b) end
    WorldMapFrame:StartMoving()
  end)
  bar:SetScript("OnDragStop", function()
    WorldMapFrame:StopMovingOrSizing()
    view.busy = nil
    SavePos()
    ApplyPos()
    Redock()
  end)

  -- resizing scales the whole window, so the map keeps its shape and the top-left corner stays put
  local sx, sy, startScale, startW, startH, left, top
  grip:SetScript("OnMouseDown", function(_, btn)
    if btn ~= "LeftButton" or DB.locked then return end
    if InCombat() then Print("can't resize the map in combat.") return end
    local eff = WorldMapFrame:GetEffectiveScale()
    sx, sy = GetCursorPosition()
    startScale = GetFactor()
    startW, startH = view:GetWidth() * view:GetEffectiveScale(), view:GetHeight() * view:GetEffectiveScale()
    left, top = WorldMapFrame:GetLeft() * eff, WorldMapFrame:GetTop() * eff -- in screen pixels
    view.busy = true
    grip:SetScript("OnUpdate", function()
      local cx, cy = GetCursorPosition()
      local fx = (startW + (cx - sx)) / startW
      local fy = (startH + (sy - cy)) / startH
      local s = startScale * math.max(fx, fy)
      s = math.max(0.35, math.min(3, s))
      SetFactor(s)
      local e = WorldMapFrame:GetEffectiveScale()
      WorldMapFrame:ClearAllPoints()
      WorldMapFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / e, top / e)
    end)
  end)
  grip:SetScript("OnMouseUp", function()
    grip:SetScript("OnUpdate", nil)
    if not view.busy then return end
    view.busy = nil
    if DB.mini then DB.miniScale = GetFactor() else DB.scale = GetFactor() end
    SavePos()
    ApplyPos()
    -- redraw quest areas and icons for the new size
    if WorldMapFrame.RefreshAllDataProviders then pcall(WorldMapFrame.RefreshAllDataProviders, WorldMapFrame) end
    FilterPinsLater()
    Redock()
  end)

  -- the game re-places the map when other panels open/close: put it back
  if UpdateUIPanelPositions then
    hooksecurefunc("UpdateUIPanelPositions", function() if WorldMapFrame:IsShown() then ApplyPos() end end)
  end
end

---------------------------------------------------------------- only map + quest tracking
-- the quest list side panel (moved here from Quest Ledger Forever's "pure map")
local function SidePanel() return QuestMapFrame or (WorldMapFrame and WorldMapFrame.QuestLog) end
local function SideToggle()
  local t = WorldMapFrame.SidePanelToggle or (WorldMapFrame.BorderFrame and WorldMapFrame.BorderFrame.SidePanelToggle)
  if t then return t end
  local function scan(fr, depth)
    if depth > 4 then return end
    for _, c in ipairs({ fr:GetChildren() }) do
      if c.OpenButton and c.CloseButton then return c end
      local hit = scan(c, depth + 1); if hit then return hit end
    end
  end
  return scan(WorldMapFrame, 0)
end
local function PanelOpen()
  local q = SidePanel()
  if q and q:IsShown() then return true end
  if WorldMapFrame.IsQuestLogPanelShown then
    local ok, v = pcall(WorldMapFrame.IsQuestLogPanelShown, WorldMapFrame); if ok and v then return true end
  end
  return false
end

local applying, waitCombat
local function CloseSidePanel()
  if applying or not PanelOpen() then return end
  if InCombat() then waitCombat = true return end
  applying = true
  -- close it the way the game does, so the map shrinks with it (no empty space)
  if WorldMapFrame.SetQuestLogPanelShown then
    pcall(WorldMapFrame.SetQuestLogPanelShown, WorldMapFrame, false)
  elseif WorldMapFrame.HandleUserActionToggleSidePanel then
    pcall(WorldMapFrame.HandleUserActionToggleSidePanel, WorldMapFrame)
  else
    local t = SideToggle()
    if t and t.CloseButton then pcall(t.CloseButton.Click, t.CloseButton) end
  end
  if SetCVar then pcall(SetCVar, "questLogOpen", 0) end
  if WorldMapFrame.SynchronizeDisplayState then pcall(WorldMapFrame.SynchronizeDisplayState, WorldMapFrame) end
  applying = false
end

-- hide the window chrome: title bar, portrait, frame border, buttons, zone bar, filters
local function ApplyChrome()
  if not WorldMapFrame then return end
  if WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() and WorldMapFrame.Minimize and not InCombat() then
    pcall(WorldMapFrame.Minimize, WorldMapFrame) -- Globus is a window, never fullscreen
  end
  Mute(WorldMapFrame.BorderFrame, 0)
  Mute(WorldMapFrame.MiniBorderFrame, 0)
  Mute(WorldMapFrame.NavBar, 0)
  Mute(WorldMapFrame.BlackoutFrame, 0)
  Mute(WorldMapFrame.TitleCanvasSpacerFrame, 0)
  Mute(SideToggle(), 0)
  -- the window's own background, title strip and frame art (anything the game keyed on the map)
  local sc = SC()
  for _, r in ipairs({ WorldMapFrame:GetRegions() }) do if r.SetAlpha then r:SetAlpha(0) end end
  for k, v in pairs(WorldMapFrame) do
    if type(k) == "string" and type(v) == "table" and v ~= sc and v ~= view and v.GetObjectType
      and v.GetParent and v:GetParent() == WorldMapFrame and k ~= "pinPools" then
      Mute(v, 0)
    end
  end
  if WorldMapFrame.overlayFrames then
    for _, o in ipairs(WorldMapFrame.overlayFrames) do Mute(o, 0) end
  end
  -- the invisible frame around the map must not catch clicks
  if not InCombat() then pcall(WorldMapFrame.EnableMouse, WorldMapFrame, false) end
  WorldMapFrame:SetAlpha(NS.TargetAlpha and NS.TargetAlpha() or DB.alpha or 1)
  CloseSidePanel()
end

-- map icons: keep quest tracking, you, your group and the map's own layers
local KEEP = {
  "Quest", "Blob", "Bonus", "GroupMember", "Player", "Ping", "Waypoint", "SuperTrack",
  "Exploration", "FogOfWar", "Highlight", "AreaLabel",
}
local function Blocked(template)
  if DB.allPins then return false end
  local t = tostring(template or "")
  for _, k in ipairs(KEEP) do if t:find(k, 1, true) then return false end end
  return true
end
local function HidePin(pin) if pin.globusBlocked then pin:Hide() end end
local function FilterPool(template, pool)
  if not (pool and pool.EnumerateActive) then return end
  local block = Blocked(template)
  for pin in pool:EnumerateActive() do
    if not pin.globusHooked then
      pin.globusHooked = true
      hooksecurefunc(pin, "Show", HidePin) -- some icons show themselves again later
    end
    local hide = block
    if not hide and NS.PinHidden then hide = NS.PinHidden(template, pin) end -- quest filter
    local was = pin.globusBlocked
    pin.globusBlocked = hide
    if hide then pin:Hide() elseif was then pin:Show() end
    if NS.DecoratePin then NS.DecoratePin(template, pin, hide) end -- quest rings
  end
end
local function FilterPins()
  if not WorldMapFrame.pinPools then return end
  for template, pool in pairs(WorldMapFrame.pinPools) do FilterPool(template, pool) end
end
NS.FilterPins = FilterPins
local function SetAllPins(on)
  DB.allPins = on
  if WorldMapFrame.pinPools then
    for _, pool in pairs(WorldMapFrame.pinPools) do
      if pool.EnumerateActive then for pin in pool:EnumerateActive() do pin.globusBlocked = nil end end
    end
  end
  if WorldMapFrame.RefreshAllDataProviders then pcall(WorldMapFrame.RefreshAllDataProviders, WorldMapFrame) end
  FilterPins()
end
NS.SetAllPins = SetAllPins

---------------------------------------------------------------- deep zoom
-- the game builds a short list of zoom steps per map; add more steps past the last one
local function ExtendZoom(sc)
  local zl = sc.zoomLevels
  if type(zl) ~= "table" or #zl == 0 then return end
  local last = zl[#zl]
  if type(last) ~= "table" or type(last.scale) ~= "number" or last.globus then return end
  sc.globusBaseMax = last.scale -- the game's own closest zoom (Terrain.lua fades in past this)
  local top = last.scale * (DB.zoom or DEFAULTS.zoom)
  local s = last.scale
  while s < top do
    s = math.min(s * 1.5, top)
    local step = {}
    for k, v in pairs(last) do step[k] = v end -- same detail layer as the game's closest zoom
    step.scale = s
    step.globus = true
    zl[#zl + 1] = step
  end
end

-- mouse wheel: zoom toward the cursor (the spot under the mouse stays under the mouse)
local STEP = 1.3
-- keep the view inside the map: the visible area may never go past the map's edges,
-- and when fully zoomed out the map is centered again
function NS.ClampView(sc, scale, nx, ny)
  local child = sc.Child
  local cw, ch = child and child:GetWidth() or 0, child and child:GetHeight() or 0
  if cw <= 0 or ch <= 0 or not scale or scale <= 0 then return nx, ny end
  if sc.GetScaleForMinZoom and scale <= sc:GetScaleForMinZoom() * 1.001 then return 0.5, 0.5 end
  local hw = sc:GetWidth() / (cw * scale) / 2   -- half the visible width, in map units
  local hh = sc:GetHeight() / (ch * scale) / 2
  if hw >= 0.5 then nx = 0.5 else nx = math.max(hw, math.min(1 - hw, nx)) end
  if hh >= 0.5 then ny = 0.5 else ny = math.max(hh, math.min(1 - hh, ny)) end
  return nx, ny
end
local function ZoomAtCursor(sc, delta)
  local cur = sc:GetCanvasScale()
  local minS, maxS = sc:GetScaleForMinZoom(), sc:GetScaleForMaxZoom()
  local from = sc.targetScale or cur
  local new = delta > 0 and from * STEP or from / STEP
  new = math.max(minS, math.min(maxS, new))
  if math.abs(new - from) < 0.0001 then return end
  local px, py = sc:GetNormalizedCursorPosition()
  local cx, cy = sc.currentScrollX, sc.currentScrollY
  local r = cur / new
  local nx, ny = px - (px - cx) * r, py - (py - cy) * r
  sc:SetZoomTarget(new)
  nx, ny = NS.ClampView(sc, new, nx, ny)
  sc:SetPanTarget(nx, ny)
end

-- zoom to a scale and center the view on a map spot (used by the zoom bar, + / - and "me")
function NS.ZoomTo(scale, nx, ny)
  local sc = SC()
  if not (sc and sc.SetZoomTarget and sc.SetPanTarget and sc.GetScaleForMinZoom and sc.GetScaleForMaxZoom) then return end
  scale = math.max(sc:GetScaleForMinZoom(), math.min(sc:GetScaleForMaxZoom(), scale))
  nx = nx or sc.targetScrollX or sc.currentScrollX or 0.5
  ny = ny or sc.targetScrollY or sc.currentScrollY or 0.5
  sc:SetZoomTarget(scale)
  nx, ny = NS.ClampView(sc, scale, nx, ny)
  sc:SetPanTarget(nx, ny)
end

local function SetupZoom()
  local sc = SC()
  if not sc then return end
  if sc.CreateZoomLevels then
    hooksecurefunc(sc, "CreateZoomLevels", ExtendZoom)
    ExtendZoom(sc)
  end
  local orig = sc:GetScript("OnMouseWheel")
  local canAnchor = sc.GetCanvasScale and sc.GetScaleForMinZoom and sc.GetScaleForMaxZoom and sc.SetZoomTarget
    and sc.SetPanTarget and sc.GetNormalizedCursorPosition
  sc:EnableMouseWheel(true)
  sc:SetScript("OnMouseWheel", function(self, delta)
    if canAnchor and type(self.currentScrollX) == "number" and type(self.currentScrollY) == "number" then
      local ok = pcall(ZoomAtCursor, self, delta)
      if ok then return end
    end
    if orig then return orig(self, delta) end
  end)
end

---------------------------------------------------------------- setup
local function Refresh()
  if not WorldMapFrame:IsShown() then return end
  if NS.ApplyMode then NS.ApplyMode() end
  ApplyChrome()
  ApplyPos()
  FilterPins()
end

NS.SC = SC
NS.InCombat = InCombat

-- Combat safety: Globus changes the map's zoom, which makes the game treat map code as
-- "touched by an addon". In combat the game then blocks one protected call that every new
-- map icon makes (SetPassThroughButtons) and shows ADDON_ACTION_BLOCKED. That call only
-- decides which mouse buttons click through an icon, so in combat we simply skip it.
local function SafePassthrough(orig)
  return function(self, ...)
    if InCombatLockdown and InCombatLockdown() then return end
    return orig(self, ...)
  end
end
local patchedPass
local function PatchPassthrough()
  if MapCanvasPinMixin and MapCanvasPinMixin.CheckMouseButtonPassthrough and not patchedPass then
    patchedPass = MapCanvasPinMixin.CheckMouseButtonPassthrough
    local safe = SafePassthrough(patchedPass)
    -- every icon type copied this function from MapCanvasPinMixin when the game loaded,
    -- so patch each copy (icons made from now on use the safe version)
    for k, v in pairs(_G) do
      if type(k) == "string" and type(v) == "table" and k:find("Mixin$") and rawget(v, "CheckMouseButtonPassthrough") == patchedPass then
        v.CheckMouseButtonPassthrough = safe
      end
    end
  end
  -- icons that already exist got their own copy of the function: patch those too
  if WorldMapFrame and WorldMapFrame.pinPools then
    for _, pool in pairs(WorldMapFrame.pinPools) do
      local function fix(pin)
        if pin.CheckMouseButtonPassthrough and not pin.globusSafePass then
          pin.globusSafePass = true
          pin.CheckMouseButtonPassthrough = SafePassthrough(pin.CheckMouseButtonPassthrough)
        end
      end
      if pool.EnumerateActive then for pin in pool:EnumerateActive() do fix(pin) end end
      if pool.EnumerateInactive then for _, pin in pool:EnumerateInactive() do fix(pin) end end
      if pool.inactiveObjects then for _, pin in pairs(pool.inactiveObjects) do if type(pin) == "table" then fix(pin) end end end
    end
  end
end
NS.PatchPassthrough = PatchPassthrough

local function Setup()
  if not WorldMapFrame or not SC() then Print("couldn't find the world map.") return end
  PatchPassthrough()
  MakeView()
  SetupMoveResize()
  SetupZoom()
  WorldMapFrame:HookScript("OnShow", function()
    Refresh()                                   -- same frame: no visible jump
    C_Timer.After(0, function() Refresh(); Redock() end)
  end)
  for _, m in ipairs({ "SynchronizeDisplayState", "Maximize", "Minimize", "OnMapChanged" }) do
    if WorldMapFrame[m] then hooksecurefunc(WorldMapFrame, m, function() if not applying then C_Timer.After(0, Refresh) end end) end
  end
  local q = SidePanel()
  if q then q:HookScript("OnShow", function() C_Timer.After(0, CloseSidePanel) end) end
  if WorldMapFrame.AcquirePin then
    hooksecurefunc(WorldMapFrame, "AcquirePin", function(self, template)
      PatchPassthrough() -- catch brand-new icons before their next use
      if self.pinPools then FilterPool(template, self.pinPools[template]) end
    end)
  end
  if SetCVar then pcall(SetCVar, "questLogOpen", 0) end
  NS.Refresh = Refresh
  if NS.SetupFeatures then
    local ok, err = pcall(NS.SetupFeatures, DB)
    if not ok then geterrorhandler()("Globus features: " .. tostring(err)) end
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    if waitCombat then waitCombat = nil; CloseSidePanel() end
    if WorldMapFrame and WorldMapFrame:IsShown() then Refresh() end
    return
  end
  GlobusDB = GlobusDB or {}
  DB = GlobusDB
  if not DB.migrated then
    -- first run: take over the map spot and transparency from Quest Ledger Forever
    DB.migrated = true
    local L = QuestLedgerForeverDB
    if L then
      if L.mapMovable and type(L.mapPos) == "table" and L.mapPos[1] == "TOPLEFT" and L.mapPos[2] == "BOTTOMLEFT" then
        DB.pos = { L.mapPos[3], L.mapPos[4] }
      end
      if type(L.mapAlpha) == "number" then DB.alpha = L.mapAlpha end
      L.pureMap, L.mapMovable, L.mapPos, L.mapAlpha, L.matchHeight = nil, nil, nil, nil, nil
    end
  end
  for k, v in pairs(DEFAULTS) do if DB[k] == nil then DB[k] = v end end
  if not DB.questIconsReverted then -- back to the game's own quest icons (with the colored rings)
    DB.questIconsReverted = true
    DB.modernQuest = false
  end
  if not DB.questRingsOff then -- plain game quest icons, no colored ring around them
    DB.questRingsOff = true
    DB.questRings = false
  end
  Setup()
end)

---------------------------------------------------------------- slash
SLASH_GLOBUS1 = "/globus"
SlashCmdList.GLOBUS = function(msg)
  msg = (msg or ""):lower()
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  if cmd == "reset" then
    if InCombat() then Print("not in combat.") return end
    DB.pos, DB.scale, DB.miniPos, DB.miniScale = nil, 1, nil, DEFAULTS.miniScale
    SetFactor(DB.mini and DB.miniScale or 1)
    if WorldMapFrame:IsShown() and UpdateUIPanelPositions then pcall(UpdateUIPanelPositions, WorldMapFrame) end
    Refresh(); Redock()
    Print("map size and position reset.")
  elseif cmd == "zoom" then
    local n = tonumber(arg)
    if not n then Print("max zoom is " .. DB.zoom .. "x past the normal limit. Change it with /globus zoom 2-20.") return end
    DB.zoom = math.max(1, math.min(20, n))
    local sc = SC()
    if sc and sc.CreateZoomLevels and WorldMapFrame:GetMapID() then pcall(sc.CreateZoomLevels, sc) end
    Print("max zoom set to " .. DB.zoom .. "x past the normal limit.")
  elseif cmd == "icons" or cmd == "pins" then
    SetAllPins(not DB.allPins)
    Print(DB.allPins and "showing all map icons." or "showing only quest tracking, you and your group.")
  elseif cmd == "alpha" then
    local n = tonumber(arg)
    if not n then Print("transparency is " .. math.floor(DB.alpha * 100 + 0.5) .. "%. Change it with /globus alpha 30-100.") return end
    DB.alpha = math.max(30, math.min(100, n)) / 100
    WorldMapFrame:SetAlpha(DB.alpha)
    Print("map transparency " .. math.floor(DB.alpha * 100 + 0.5) .. "%.")
  elseif cmd == "mini" and NS.SetMini then
    NS.SetMini(not DB.mini)
  elseif cmd == "lock" and NS.SetLocked then
    NS.SetLocked(not DB.locked)
  elseif cmd == "follow" and NS.SetFollow then
    NS.SetFollow(not DB.follow)
  elseif (cmd == "options" or cmd == "config" or cmd == "settings") and NS.OpenOptions then
    NS.OpenOptions()
  elseif cmd == "terrain" and NS.TerrainCommand then
    NS.TerrainCommand(arg)
  elseif cmd == "debug" then
    local sc = SC()
    Print("zoom levels=" .. tostring(sc and sc.zoomLevels and #sc.zoomLevels)
      .. " scale=" .. tostring(sc and sc.GetCanvasScale and string.format("%.2f", sc:GetCanvasScale()))
      .. " max=" .. tostring(sc and sc.GetScaleForMaxZoom and string.format("%.2f", sc:GetScaleForMaxZoom()))
      .. " cursorZoom=" .. tostring(sc and type(sc.currentScrollX) == "number")
      .. " realResize=" .. tostring(SizeMode()))
    if WorldMapFrame.pinPools then
      for template, pool in pairs(WorldMapFrame.pinPools) do
        local n = 0
        if pool.EnumerateActive then for _ in pool:EnumerateActive() do n = n + 1 end end
        if n > 0 then print("  " .. tostring(template) .. " x" .. n .. (Blocked(template) and " |cffff6666hidden|r" or " |cff66ff66shown|r")) end
      end
    end
  else
    Print("mouse wheel zooms, drag the top edge to move, drag the bottom-right corner to resize, right-click zooms out a level.")
    print("  /globus options - settings window (also Esc > Options > AddOns)")
    print("  /globus mini - mini mode on/off")
    print("  /globus lock - lock / unlock moving and resizing")
    print("  /globus follow - map follows you while zoomed in")
    print("  Ctrl-click: waypoint - Alt-click: ping your group")
    print("  /globus terrain - detailed minimap terrain when zoomed in on/off (/globus terrain test)")
    print("  /globus zoom 8 - how far past the normal zoom limit you can go")
    print("  /globus icons - show all map icons / only quest tracking")
    print("  /globus alpha 80 - map transparency")
    print("  /globus reset - size and position back to default")
    print("  /globus debug - diagnostics")
  end
end
