-- Globus features: coordinates, waypoints, zoom bar, follow mode, breadcrumbs, quest filter,
-- quest rings, nearest-objective line, zone levels, mini mode, fade while moving, lock,
-- options page, party names and group pings.
local ADDON, NS = ...
local DB
local MEDIA = "Interface\\AddOns\\Globus\\"
local PREFIX = "GLOBUS1"
local Print = NS.Print

local function SC() return NS.SC() end
local function MapID() return WorldMapFrame and WorldMapFrame:GetMapID() end

---------------------------------------------------------------- small helpers
local function XY(v)
  if not v then return end
  if v.GetXY then return v:GetXY() end
  return v.x, v.y
end

local function PlayerPos(mapID, unit)
  if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then return end
  local ok, v = pcall(C_Map.GetPlayerMapPosition, mapID, unit or "player")
  if not ok then return end
  local x, y = XY(v)
  if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return end -- hidden by the game right now
  if x and y and (x > 0 or y > 0) and x <= 1 and y <= 1 then return x, y end
end

-- map spot on map A -> same spot on map B (nil if it isn't on B)
local function Project(m, x, y, viewMap)
  if m == viewMap then return x, y end
  if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
  local ok, contID, world = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
  if not ok or not world then return end
  local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, contID, world, viewMap)
  if not ok2 or not pos then return end
  local px, py = XY(pos)
  if not px or px < 0 or px > 1 or py < 0 or py > 1 then return end
  return px, py
end

-- things drawn on the map keep the same size on screen at any zoom
local function InvScale(child)
  local cur = child:GetScale()
  if not cur or cur <= 0 then return 1 end
  local base = cur
  local sc = SC()
  if sc and sc.GetScaleForMinZoom then
    local ok, v = pcall(sc.GetScaleForMinZoom, sc)
    if ok and type(v) == "number" and v > 0 then base = v end
  end
  return base / cur
end

local host -- frame lying on the map canvas, above the map art, below the controls
local function Place(fr, nx, ny, point, dy)
  local child = SC().Child
  local inv = InvScale(child)
  fr:SetScale(inv)
  fr:ClearAllPoints()
  fr:SetPoint(point or "CENTER", host, "TOPLEFT", nx * child:GetWidth() / inv, -ny * child:GetHeight() / inv + (dy or 0))
end

-- Blizzard-style tooltip: gold title, white text, green click hint
local function Tip(owner, title, text, hint)
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:AddLine(title, 1, 0.82, 0)
  if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
  if type(hint) == "function" then hint = hint() end
  if hint then GameTooltip:AddLine(hint, 0.4, 1, 0.4) end
  GameTooltip:Show()
end

---------------------------------------------------------------- quests
local function LogIndex(qid)
  if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(qid) end
  if GetQuestLogIndexByID then return GetQuestLogIndexByID(qid) end
end
local function Watched(qid)
  local idx = LogIndex(qid)
  if QuestLedgerForever_IsWatched then
    local ok, w = pcall(QuestLedgerForever_IsWatched, qid, idx); if ok then return w and true or false end
  end
  if C_QuestLog and C_QuestLog.GetQuestWatchType then return C_QuestLog.GetQuestWatchType(qid) ~= nil end
  if idx and IsQuestWatched then return IsQuestWatched(idx) and true or false end
  return true
end
local function Finished(qid)
  if C_QuestLog and C_QuestLog.IsComplete then
    local ok, v = pcall(C_QuestLog.IsComplete, qid); if ok then return v and true or false end
  end
  local idx = LogIndex(qid)
  if idx and GetQuestLogTitle then
    local _, _, _, _, _, isComplete = GetQuestLogTitle(idx)
    return isComplete == 1 or isComplete == true
  end
  return false
end
local function QuestShown(qid)
  if DB.questFilter == "tracked" then return Watched(qid) end
  if DB.questFilter == "notdone" then return not Finished(qid) end
  return true
end

local function IsQuestIcon(template, pin)
  local t = tostring(template or "")
  return t:find("Quest", 1, true) and not t:find("Blob", 1, true) and type(pin.questID) == "number"
end

-- quest filter (#6): called by Globus for every map icon
function NS.PinHidden(template, pin)
  if DB.questFilter == "all" or not IsQuestIcon(template, pin) then return false end
  return not QuestShown(pin.questID)
end

-- quest rings (#7): every quest icon gets its own colored ring
local PALETTE = {
  { 0.20, 0.85, 1.00 }, { 1.00, 0.55, 0.15 }, { 0.45, 1.00, 0.30 }, { 1.00, 0.35, 0.80 },
  { 1.00, 0.90, 0.20 }, { 0.60, 0.45, 1.00 }, { 0.25, 1.00, 0.80 }, { 1.00, 0.30, 0.30 },
}
local function QuestColor(qid) return PALETTE[(qid % #PALETTE) + 1] end
-- zone name shown when hovering the map: gold Friz Quadrata like the game's own headers
local function GoldLabel(fs)
  if fs.globusGold then return end
  fs.globusGold = true
  local function paint(f) f:SetTextColor(1, 0.82, 0); f:SetShadowColor(0, 0, 0, 1); f:SetShadowOffset(2, -2) end
  hooksecurefunc(fs, "SetText", paint)
  paint(fs)
end
local function StyleAreaLabel(pin)
  local best, size
  local function scan(f, depth)
    if depth > 2 then return end
    for _, r in ipairs({ f:GetRegions() }) do
      if r.GetObjectType and r:GetObjectType() == "FontString" then
        local _, h = r:GetFont()
        if h and (not size or h > size) then best, size = r, h end
      end
    end
    for _, c in ipairs({ f:GetChildren() }) do scan(c, depth + 1) end
  end
  scan(pin, 0)
  if best then GoldLabel(best) end -- only the big zone name; the smaller line keeps its own color
end

function NS.DecoratePin(template, pin, hidden)
  if tostring(template or ""):find("AreaLabel", 1, true) then StyleAreaLabel(pin) return end
  local quest = IsQuestIcon(template, pin)
  if not quest then
    if pin.globusRing then pin.globusRing:Hide() end
    return
  end
  -- Warcraft-style quest marks instead of the game's round icons
  local modern = DB.modernQuest ~= false
  local function blizzArt(alpha)
    local n, pu = pin:GetNormalTexture(), pin:GetPushedTexture()
    if n then n:SetAlpha(alpha) end
    if pu then pu:SetAlpha(alpha) end
    for _, c in ipairs({ pin:GetChildren() }) do c:SetAlpha(alpha) end -- the game's icon on top
  end
  if modern then
    if not pin.globusBadge then
      local g = {}
      g.shadow = pin:CreateTexture(nil, "BACKGROUND", nil, -6); g.shadow:SetTexture(MEDIA .. "BadgeShadow"); g.shadow:SetPoint("CENTER", 0, -1)
      g.ring = pin:CreateTexture(nil, "BORDER", nil, 6); g.ring:SetTexture(MEDIA .. "BadgeRing"); g.ring:SetPoint("CENTER")
      g.fill = pin:CreateTexture(nil, "BORDER", nil, 7); g.fill:SetTexture(MEDIA .. "BadgeFill"); g.fill:SetPoint("CENTER")
      g.sym = pin:CreateTexture(nil, "OVERLAY", nil, 7); g.sym:SetPoint("CENTER")
      pin.globusBadge = g
    end
    local g = pin.globusBadge
    local w = pin:GetWidth()
    if not w or w <= 0 then w = 20 end
    -- retail Warcraft style: glowing gold ? (ready to turn in), silver ? (still in progress)
    g.sym:SetTexture(MEDIA .. (Finished(pin.questID) and "WowTurnIn" or "WowProgress"))
    g.sym:SetSize(w * 1.7, w * 1.7)
    g.shadow:Hide(); g.ring:Hide(); g.fill:Hide()
    g.sym:SetShown(not hidden)
    blizzArt(0)
    if pin.globusRing then pin.globusRing:Hide() end
    return
  elseif pin.globusBadge then
    for _, t in pairs(pin.globusBadge) do t:Hide() end
    blizzArt(1)
  end
  local ring = pin.globusRing
  if not ring then
    ring = pin:CreateTexture(nil, "BACKGROUND", nil, -7)
    ring:SetTexture(MEDIA .. "Ring")
    ring:SetPoint("CENTER")
    pin.globusRing = ring
  end
  local w = pin:GetWidth()
  if not w or w <= 0 then w = 24 end
  ring:SetSize(w * 1.55, w * 1.55)
  local c = QuestColor(pin.questID)
  ring:SetVertexColor(c[1], c[2], c[3], 0.95)
  ring:SetShown(DB.questRings and not hidden)
end

---------------------------------------------------------------- zone levels (#10)
local LEVELS = {
  ["Elwynn Forest"] = { 1, 10 }, ["Dun Morogh"] = { 1, 10 }, ["Tirisfal Glades"] = { 1, 10 },
  ["Durotar"] = { 1, 10 }, ["Mulgore"] = { 1, 10 }, ["Teldrassil"] = { 1, 10 },
  ["Westfall"] = { 10, 20 }, ["Loch Modan"] = { 10, 20 }, ["Silverpine Forest"] = { 10, 20 },
  ["Darkshore"] = { 10, 20 }, ["The Barrens"] = { 10, 25 }, ["Redridge Mountains"] = { 15, 25 },
  ["Stonetalon Mountains"] = { 15, 27 }, ["Ashenvale"] = { 18, 30 }, ["Duskwood"] = { 18, 30 },
  ["Hillsbrad Foothills"] = { 20, 30 }, ["Wetlands"] = { 20, 30 }, ["Thousand Needles"] = { 25, 35 },
  ["Alterac Mountains"] = { 30, 40 }, ["Arathi Highlands"] = { 30, 40 }, ["Desolace"] = { 30, 40 },
  ["Stranglethorn Vale"] = { 30, 45 }, ["Dustwallow Marsh"] = { 35, 45 }, ["Badlands"] = { 35, 45 },
  ["Swamp of Sorrows"] = { 35, 45 }, ["Feralas"] = { 40, 50 }, ["The Hinterlands"] = { 40, 50 },
  ["Hinterlands"] = { 40, 50 }, ["Tanaris"] = { 40, 50 }, ["Searing Gorge"] = { 43, 50 },
  ["Azshara"] = { 45, 55 }, ["Blasted Lands"] = { 45, 55 }, ["Un'Goro Crater"] = { 48, 55 },
  ["Felwood"] = { 48, 55 }, ["Burning Steppes"] = { 50, 58 }, ["Western Plaguelands"] = { 51, 58 },
  ["Eastern Plaguelands"] = { 53, 60 }, ["Winterspring"] = { 53, 60 }, ["Deadwind Pass"] = { 55, 60 },
  ["Moonglade"] = { 55, 60 }, ["Silithus"] = { 55, 60 },
}
local function ZoneLevels(mapID, name)
  if C_Map.GetMapLevels then
    local ok, lo, hi = pcall(C_Map.GetMapLevels, mapID)
    if ok and type(lo) == "number" and lo > 0 and type(hi) == "number" and hi > 0 then return lo, hi end
  end
  local l = name and LEVELS[name]
  if l then return l[1], l[2] end
end
local function LevelText(mapID, name)
  local lo, hi = ZoneLevels(mapID, name)
  if not lo then return name end
  local me = UnitLevel("player") or 1
  local col = (me < lo and "ff4040") or (me > hi and "40ff40") or "ffd200"
  return ("%s |cff%s(%d-%d)|r"):format(name, col, lo, hi)
end

---------------------------------------------------------------- UI pieces
local info, crumbs, zoomBar, buttons, line, names, pings = nil, {}, nil, {}, nil, {}, {}

local ACCENT = { 0.31, 0.76, 0.97 }
local function IconButton(parent, icon, title, tip, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(); b.icon:SetTexture(icon); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(s) Tip(s, type(title) == "function" and title() or title, tip) end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:EnableMouse(false)
  buttons[#buttons + 1] = b
  return b
end
-- Blizzard-style toolbar button: like the round minimap buttons (gold ring, dark center)
local function ToolButton(parent, icon, title, tip, onClick, hint)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(22, 22)
  b.bgTex = b:CreateTexture(nil, "BACKGROUND")
  b.bgTex:SetTexture("Interface\\Minimap\\UI-Minimap-Background"); b.bgTex:SetSize(15, 15)
  b.bgTex:SetPoint("TOPLEFT", 4, -4); b.bgTex:SetVertexColor(0, 0, 0, 0.9)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(MEDIA .. icon); b.icon:SetSize(10, 10); b.icon:SetPoint("CENTER", b.bgTex, "CENTER", 0, 0)
  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); b.border:SetSize(38, 38); b.border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  b:GetHighlightTexture():ClearAllPoints(); b:GetHighlightTexture():SetSize(22, 22); b:GetHighlightTexture():SetPoint("CENTER", b.bgTex, "CENTER")
  b:SetScript("OnClick", function(s, ...)
    onClick(s, ...)
    if GameTooltip:IsOwned(s) then s:GetScript("OnEnter")(s) end -- refresh the on/off text
  end)
  b:SetScript("OnEnter", function(s) Tip(s, type(title) == "function" and title() or title, tip, hint) end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:EnableMouse(false)
  buttons[#buttons + 1] = b
  return b
end
local function TextButton(parent, text, title, tip, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(18, 18)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
  b.bg:SetTexture("Interface\\Buttons\\WHITE8X8"); b.bg:SetVertexColor(0, 0, 0, 0.6)
  b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); b.txt:SetPoint("CENTER", 0, 1); b.txt:SetText(text)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(s) Tip(s, title, tip) end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:EnableMouse(false)
  buttons[#buttons + 1] = b
  return b
end

local function Lit(b, on)
  -- switched on: bright gold like Blizzard's highlighted text; off: dim grey
  if on then b.icon:SetVertexColor(1, 0.82, 0, 1) else b.icon:SetVertexColor(0.75, 0.75, 0.75, 0.9) end
end

---------------------------------------------------------------- mode switches
function Globus_IsMini() return DB ~= nil and DB.mini == true end

function NS.SetMini(on)
  if NS.InCombat() then Print("can't switch mini mode in combat.") return end
  DB.mini = on and true or false
  NS.ApplyPos(); NS.Redock()
  if NS.UpdateButtons then NS.UpdateButtons() end
  Print(DB.mini and "mini mode on (hover to see it clearly, the map button switches back)." or "mini mode off.")
end
function NS.SetLocked(on)
  DB.locked = on and true or false
  if NS.view.RefreshControls then NS.view.RefreshControls() end
  if NS.UpdateButtons then NS.UpdateButtons() end
  Print(DB.locked and "map locked." or "map unlocked.")
end
function NS.SetFollow(on)
  DB.follow = on and true or false
  if NS.UpdateButtons then NS.UpdateButtons() end
  Print(DB.follow and "map follows you." or "map stops following you.")
end

-- Is the player moving? The game can hand addons "secret" values (e.g. speed in combat) that
-- can't be compared, so use the plain yes/no check and never compare a secret value.
function NS.PlayerMoving()
  local secret = issecretvalue
  if IsPlayerMoving then
    local ok, v = pcall(IsPlayerMoving)
    if ok and not (secret and secret(v)) then return v and true or false end
  end
  if GetUnitSpeed then
    local ok, v = pcall(GetUnitSpeed, "player")
    if ok and type(v) == "number" and not (secret and secret(v)) then return v > 0 end
  end
  return false
end

-- transparency: normal / mini mode / while moving (#11, #12); always solid under the mouse
function NS.TargetAlpha()
  local a = DB.alpha or 1
  if NS.view and NS.view:IsMouseOver() then return a end
  if DB.mini then a = math.min(a, DB.miniAlpha) end
  if DB.fadeMoving and NS.PlayerMoving() then a = math.min(a, DB.fadeAlpha) end
  return a
end

---------------------------------------------------------------- breadcrumbs (#5)
local function BuildCrumbs()
  for _, b in ipairs(crumbs) do b:Hide() end
  local bar = NS.view.bar
  bar.txt:SetShown(not DB.crumbs)
  if not DB.crumbs then return end
  local chain, id = {}, MapID()
  while id and id > 0 and #chain < 8 do
    local mi = C_Map.GetMapInfo(id)
    if not mi then break end
    if mi.mapType ~= 0 then table.insert(chain, 1, { id = id, name = mi.name }) end -- skip "Cosmic"
    id = mi.parentMapID
  end
  local prev
  for i, c in ipairs(chain) do
    local b = crumbs[i]
    if not b then
      b = CreateFrame("Button", nil, bar)
      b:SetHeight(20)
      b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.txt:SetPoint("LEFT")
      b:SetScript("OnClick", function(s) if s.mapID and s.mapID ~= MapID() then WorldMapFrame:SetMapID(s.mapID) end end)
      b:SetScript("OnEnter", function(s) s.txt:SetTextColor(1, 1, 1) end)
      b:SetScript("OnLeave", function(s) s.txt:SetTextColor(s.r, s.g, s.b) end)
      crumbs[i] = b
    end
    b.mapID = c.id
    local last = i == #chain
    b.txt:SetText((i > 1 and "|cff9d8a5a>|r " or "") .. c.name)
    if last then b.r, b.g, b.b = 1, 1, 1 else b.r, b.g, b.b = 1, 0.82, 0 end
    b.txt:SetTextColor(b.r, b.g, b.b)
    b:SetWidth(b.txt:GetStringWidth() + 6)
    b:ClearAllPoints()
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("LEFT", bar, "LEFT", 10, 0) end
    b:EnableMouse(NS.hovering == true)
    b:Show()
    prev = b
  end
end

---------------------------------------------------------------- build
local function MakeUI()
  local view, controls, sc = NS.view, NS.controls, SC()
  local child = sc.Child

  -- canvas overlay (lines, party names, pings): above the map art, below QuestMates' dots
  host = CreateFrame("Frame", "GlobusCanvas", child)
  host:SetAllPoints(child)
  host:SetFrameLevel(child:GetFrameLevel() + 2000)
  host:EnableMouse(false)

  -- info line (#1, #10): zone + levels, your coordinates, cursor coordinates
  info = CreateFrame("Frame", nil, view)
  info:SetFrameLevel(view:GetFrameLevel() + 5)
  info:SetHeight(20)
  info:SetPoint("BOTTOM", view, "BOTTOM", 0, 6)
  info.bg = info:CreateTexture(nil, "BACKGROUND"); info.bg:SetAllPoints()
  info.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background"); info.bg:SetVertexColor(0.04, 0.03, 0.02, 0.85)
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                       { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local t = info:CreateTexture(nil, "BORDER")
    t:SetTexture("Interface\\Buttons\\WHITE8X8"); t:SetVertexColor(0.78, 0.62, 0.22, 0.9)
    t:SetPoint(e[1]); t:SetPoint(e[2])
    if e[3] then t:SetHeight(1) else t:SetWidth(1) end
  end
  info.txt = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  info.txt:SetPoint("CENTER")
  info:EnableMouse(false)

  -- top bar buttons: options, follow, mini, lock (left of the close button)
  local bar = view.bar
  local opt = ToolButton(controls, "IconGear", "Options", "Globus settings.", function() NS.OpenOptions() end, "Click to open")
  opt:SetPoint("RIGHT", NS.view.close, "LEFT", -7, 0)
  local follow = ToolButton(controls, "IconFollow", function() return DB.follow and "Follow: on" or "Follow: off" end,
    "The map scrolls with you while you're zoomed in.", function() NS.SetFollow(not DB.follow) end,
    function() return DB.follow and "Click to turn off" or "Click to turn on" end)
  follow:SetPoint("RIGHT", opt, "LEFT", -2, 0)
  local mini = ToolButton(controls, "IconMini", function() return DB.mini and "Mini mode: on" or "Mini mode: off" end,
    "Small and see-through, stays open while you play. Hover to see it clearly.", function() NS.SetMini(not DB.mini) end,
    function() return DB.mini and "Click for the normal map" or "Click for mini mode" end)
  mini:SetPoint("RIGHT", follow, "LEFT", -2, 0)
  local lock = ToolButton(controls, "IconUnlock", function() return DB.locked and "Locked" or "Unlocked" end,
    "Locked: the map can't be moved or resized.", function() NS.SetLocked(not DB.locked) end,
    function() return DB.locked and "Click to unlock" or "Click to lock" end)
  lock:SetPoint("RIGHT", mini, "LEFT", -2, 0)
  -- thin divider between the toggles and the close button
  local div = controls:CreateTexture(nil, "OVERLAY")
  div:SetTexture("Interface\\Buttons\\WHITE8X8"); div:SetVertexColor(0.8, 0.65, 0.25, 0.5)
  div:SetSize(1, 12); div:SetPoint("RIGHT", NS.view.close, "LEFT", -3, 0)
  for _, b in ipairs({ opt, follow, mini, lock }) do b:SetFrameLevel(bar:GetFrameLevel() + 5) end
  function NS.UpdateButtons()
    Lit(follow, DB.follow); Lit(mini, DB.mini); Lit(lock, DB.locked); Lit(opt, true)
    lock.icon:SetTexture(MEDIA .. (DB.locked and "IconLock" or "IconUnlock"))
  end
  NS.UpdateButtons()

  -- zoom bar (#3): + / slider / - / zoom to me, along the right edge.
  -- Dark gold-trimmed panel with minimap-style round buttons, like the toolbar.
  zoomBar = CreateFrame("Frame", nil, controls)
  zoomBar:SetSize(30, 222)
  zoomBar:SetPoint("RIGHT", view, "RIGHT", -6, 0)
  zoomBar.bg = zoomBar:CreateTexture(nil, "BACKGROUND")
  zoomBar.bg:SetAllPoints(); zoomBar.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  zoomBar.bg:SetVertexColor(0.04, 0.03, 0.02, 0.85)
  local function edge(p1, p2, horiz, a)
    local t = zoomBar:CreateTexture(nil, "BORDER")
    t:SetTexture("Interface\\Buttons\\WHITE8X8"); t:SetVertexColor(0.78, 0.62, 0.22, a)
    t:SetPoint(p1); t:SetPoint(p2)
    if horiz then t:SetHeight(1) else t:SetWidth(1) end
  end
  edge("TOPLEFT", "TOPRIGHT", true, 0.9); edge("BOTTOMLEFT", "BOTTOMRIGHT", true, 0.9)
  edge("TOPLEFT", "BOTTOMLEFT", false, 0.9); edge("TOPRIGHT", "BOTTOMRIGHT", false, 0.9)

  local function zoomBy(f) local s = SC(); NS.ZoomTo((s.targetScale or s:GetCanvasScale()) * f) end
  local plus = ToolButton(zoomBar, "IconPlus", "Zoom in", nil, function() zoomBy(1.5) end)
  plus:SetPoint("TOP", zoomBar, "TOP", 0, -4)
  local sl = CreateFrame("Slider", nil, zoomBar)
  sl:SetOrientation("VERTICAL")
  sl:SetSize(16, 126)
  sl:SetPoint("TOP", plus, "BOTTOM", 0, -8)
  sl:SetMinMaxValues(0, 1)
  -- groove: dark channel with a thin gold edge
  sl.bg = sl:CreateTexture(nil, "BACKGROUND"); sl.bg:SetPoint("TOP"); sl.bg:SetPoint("BOTTOM"); sl.bg:SetWidth(6)
  sl.bg:SetTexture("Interface\\Buttons\\WHITE8X8"); sl.bg:SetVertexColor(0.78, 0.62, 0.22, 0.7)
  sl.groove = sl:CreateTexture(nil, "BORDER"); sl.groove:SetPoint("TOP", 0, -1); sl.groove:SetPoint("BOTTOM", 0, 1); sl.groove:SetWidth(4)
  sl.groove:SetTexture("Interface\\Buttons\\WHITE8X8"); sl.groove:SetVertexColor(0, 0, 0, 0.95)
  sl:SetThumbTexture(MEDIA .. "Knob")
  local thumb = sl:GetThumbTexture(); thumb:SetSize(14, 14)
  sl:EnableMouse(false)
  buttons[#buttons + 1] = sl
  local minus = ToolButton(zoomBar, "IconMinus", "Zoom out", nil, function() zoomBy(1 / 1.5) end)
  minus:SetPoint("TOP", sl, "BOTTOM", 0, -8)
  local me = ToolButton(zoomBar, "IconMe", "Zoom to me", "Centers and zooms the map on you.", function()
    local m = MapID()
    local x, y = PlayerPos(m)
    if not x and C_Map.GetBestMapForUnit then
      local best = C_Map.GetBestMapForUnit("player")
      if best and best ~= m then WorldMapFrame:SetMapID(best); m = best; x, y = PlayerPos(m) end
    end
    if not x then Print("you're not on this map.") return end
    local s = SC()
    local cur = s.targetScale or s:GetCanvasScale()
    NS.ZoomTo(math.max(cur, s:GetScaleForMinZoom() * 3), x, y)
  end)
  me:SetPoint("TOP", minus, "BOTTOM", 0, -8)
  for _, b in ipairs({ plus, minus, me }) do Lit(b, true) end
  local function Range()
    local s = SC()
    return s:GetScaleForMinZoom(), s:GetScaleForMaxZoom()
  end
  sl:SetScript("OnValueChanged", function(_, v, user)
    if sl.syncing then return end
    local lo, hi = Range()
    if not (lo and hi and hi > lo) then return end
    NS.ZoomTo(lo * (hi / lo) ^ (1 - v)) -- top = zoomed in
  end)
  sl.Sync = function()
    if sl:IsMouseOver() and IsMouseButtonDown and IsMouseButtonDown("LeftButton") then return end
    local s = SC()
    local lo, hi = Range()
    if not (lo and hi and hi > lo) then return end
    local cur = s.targetScale or s:GetCanvasScale()
    sl.syncing = true
    sl:SetValue(1 - math.log(cur / lo) / math.log(hi / lo))
    sl.syncing = nil
  end
  zoomBar.slider = sl

  -- nearest objective line (#8)
  if host.CreateLine then
    line = host:CreateLine(nil, "OVERLAY")
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(1, 0.82, 0, 0.8)
    line:Hide()
  end

  -- hover: buttons only catch the mouse while you can see them
  NS.OnControlsShown = function(on)
    NS.hovering = on
    for _, b in ipairs(buttons) do b:EnableMouse(on) end
    for _, b in ipairs(crumbs) do b:EnableMouse(on) end
    zoomBar:SetShown(DB.zoomBar)
  end
  zoomBar:SetShown(DB.zoomBar)
end

---------------------------------------------------------------- party names (#15)
local function NameLabel(i)
  local f = names[i]
  if f then return f end
  f = CreateFrame("Frame", nil, host)
  f:SetSize(1, 1)
  f.txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.txt:SetPoint("BOTTOM", f, "BOTTOM")
  f.txt:SetShadowOffset(1, -1)
  names[i] = f
  return f
end
local function UpdateNames(m)
  local n = 0
  if DB.partyNames and IsInGroup and IsInGroup() then
    local raid = IsInRaid and IsInRaid()
    local count = raid and (GetNumGroupMembers() or 0) or 4
    for i = 1, count do
      local u = raid and ("raid" .. i) or ("party" .. i)
      if UnitExists(u) and not UnitIsUnit(u, "player") then
        local x, y = PlayerPos(m, u)
        if x then
          n = n + 1
          local f = NameLabel(n)
          local name = UnitName(u) or "?"
          local _, class = UnitClass(u)
          local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
          f.txt:SetText(name)
          if c then f.txt:SetTextColor(c.r, c.g, c.b) else f.txt:SetTextColor(1, 1, 1) end
          Place(f, x, y, "BOTTOM", 9)
          f:Show()
        end
      end
    end
  end
  for i = n + 1, #names do names[i]:Hide() end
end

---------------------------------------------------------------- nearest objective (#8)
local function UpdateLine(m)
  if not line then return end
  if not DB.nearestLine or not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then line:Hide() return end
  local px, py = PlayerPos(m)
  if not px then line:Hide() return end
  local ok, list = pcall(C_QuestLog.GetQuestsOnMap, m)
  if not ok or type(list) ~= "table" then line:Hide() return end
  local child = SC().Child
  local w, h = child:GetWidth(), child:GetHeight()
  local best, bx, by
  for _, q in ipairs(list) do
    if q.x and q.y and q.questID and QuestShown(q.questID) then
      local d = ((q.x - px) * w) ^ 2 + ((q.y - py) * h) ^ 2
      if not best or d < best then best, bx, by = d, q.x, q.y end
    end
  end
  if not best or best < 1 then line:Hide() return end
  line:SetStartPoint("TOPLEFT", host, px * w, -py * h)
  line:SetEndPoint("TOPLEFT", host, bx * w, -by * h)
  line:SetThickness(3 * InvScale(child))
  line:Show()
end

---------------------------------------------------------------- group pings (#16)
local function PingFrame()
  for _, p in ipairs(pings) do if not p:IsShown() then return p end end
  local p = CreateFrame("Frame", nil, host)
  p:SetSize(40, 40)
  p.ring = p:CreateTexture(nil, "OVERLAY"); p.ring:SetTexture(MEDIA .. "Ring"); p.ring:SetPoint("CENTER")
  p.dot = p:CreateTexture(nil, "OVERLAY"); p.dot:SetTexture(MEDIA .. "Disc"); p.dot:SetSize(10, 10); p.dot:SetPoint("CENTER")
  p.txt = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); p.txt:SetPoint("BOTTOM", p, "TOP", 0, -6)
  p.txt:SetShadowOffset(1, -1)
  p:SetScript("OnUpdate", function(s)
    local t = GetTime() - s.start
    if t > 6 then s:Hide() return end
    local k = (t % 1)                      -- one pulse per second
    s.ring:SetSize(12 + 34 * k, 12 + 34 * k)
    s.ring:SetAlpha(1 - k)
    if s.nx then Place(s, s.nx, s.ny) end   -- stays put while zooming
  end)
  pings[#pings + 1] = p
  return p
end
local function ShowPing(who, m, x, y)
  if WorldMapFrame:IsShown() and host then
    local nx, ny = Project(m, x, y, MapID())
    if nx then
      local p = PingFrame()
      p.start, p.nx, p.ny = GetTime(), nx, ny
      p.txt:SetText(who)
      p.ring:SetVertexColor(1, 0.85, 0.2); p.dot:SetVertexColor(1, 0.85, 0.2)
      Place(p, nx, ny)
      p:Show()
    end
  end
  if who ~= UnitName("player") then
    local mi = C_Map.GetMapInfo(m)
    Print(("%s pinged the map%s."):format(who, mi and mi.name and (" in " .. mi.name) or ""))
    if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.MAP_PING) or 3175) end
  end
end
local lastPing = 0
local function SendPing(m, x, y)
  if GetTime() - lastPing < 1 then return end
  lastPing = GetTime()
  ShowPing(UnitName("player"), m, x, y)
  if not (IsInGroup and IsInGroup()) then return end
  local chan = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
  local msg = ("P:%d:%.4f:%.4f"):format(m, x, y)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, msg, chan)
  elseif SendAddonMessage then SendAddonMessage(PREFIX, msg, chan) end
end

---------------------------------------------------------------- Ctrl-click waypoint (#2) / Alt-click ping
local ourWaypoint
local function SetWaypoint(m, x, y)
  if not (C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
    Print("waypoints aren't supported in this game version.") return
  end
  if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(m) then
    Print("can't place a waypoint on this map - zoom into a zone first.") return
  end
  -- Ctrl-click the same spot again: remove it
  if ourWaypoint and ourWaypoint.m == m and math.abs(ourWaypoint.x - x) < 0.015 and math.abs(ourWaypoint.y - y) < 0.015 then
    if C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
    ourWaypoint = nil
    return
  end
  local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(m, x, y))
  if not ok then Print("couldn't place a waypoint there.") return end
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
  ourWaypoint = { m = m, x = x, y = y }
end

local function HookClicks()
  local sc = SC()
  local downX, downY
  sc:HookScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" then downX, downY = GetCursorPosition() end
  end)
  sc:HookScript("OnMouseUp", function(self, btn)
    if btn ~= "LeftButton" or not downX then return end
    local ux, uy = GetCursorPosition()
    local moved = math.abs(ux - downX) + math.abs(uy - downY)
    downX = nil
    if moved > 6 then return end -- that was a drag, not a click
    local ctrl, alt = IsControlKeyDown(), IsAltKeyDown()
    if not (ctrl or alt) then return end
    local x, y = self:GetNormalizedCursorPosition()
    local m = MapID()
    if not (m and x and y) then return end
    if ctrl and DB.waypoint then
      -- after the game's own click handling, so ours is the one that stays
      C_Timer.After(0, function() SetWaypoint(m, x, y) end)
    elseif alt and DB.ping then
      SendPing(m, x, y)
    end
  end)
end

---------------------------------------------------------------- updates
local function UpdateInfo(m)
  if not DB.coords and not DB.zoneLevels then info:Hide() return end
  local parts = {}
  local sc = SC()
  local cx, cy
  if NS.view:IsMouseOver() then cx, cy = sc:GetNormalizedCursorPosition() end
  if DB.zoneLevels then
    local id, name = m, nil
    if cx and C_Map.GetMapInfoAtPosition then
      local ok, mi = pcall(C_Map.GetMapInfoAtPosition, m, cx, cy)
      if ok and mi and mi.mapID and mi.mapID ~= m then id, name = mi.mapID, mi.name end
    end
    if not name then local mi = C_Map.GetMapInfo(m); name = mi and mi.name end
    if name then parts[#parts + 1] = LevelText(id, name) end
  end
  if DB.coords then
    local px, py = PlayerPos(m)
    local you = "|T" .. MEDIA .. "IconMe:11:11:0:0:64:64:0:64:0:64:255:210:0|t "
    parts[#parts + 1] = px and (you .. "%.1f, %.1f"):format(px * 100, py * 100) or (you .. "-")
    if cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
      parts[#parts + 1] = ("|T" .. MEDIA .. "IconCursor:11:11:0:0:64:64:0:64:0:64:255:210:0|t %.1f, %.1f"):format(cx * 100, cy * 100)
    end
  end
  info.txt:SetText(table.concat(parts, "   |cff9d8a5a|||r   "))
  info:SetWidth(info.txt:GetStringWidth() + 20)
  info:Show()
end

local function Follow(m)
  if not DB.follow then return end
  if NS.view.busy or (IsMouseButtonDown and IsMouseButtonDown("LeftButton") and NS.view:IsMouseOver()) then return end
  local x, y = PlayerPos(m)
  if not x then return end
  local s = SC()
  NS.ZoomTo(s.targetScale or s:GetCanvasScale(), x, y)
end

local alphaNow
local function UpdateAlpha(elapsed)
  local want = NS.TargetAlpha()
  alphaNow = alphaNow or WorldMapFrame:GetAlpha()
  if math.abs(alphaNow - want) < 0.01 then alphaNow = want
  else alphaNow = alphaNow + (want - alphaNow) * math.min(1, elapsed * 8) end
  WorldMapFrame:SetAlpha(alphaNow)
end

local function StartTicker()
  local fast, slow = 0, 0
  local t = CreateFrame("Frame", nil, WorldMapFrame)
  t:SetScript("OnUpdate", function(_, elapsed)
    UpdateAlpha(elapsed)
    fast, slow = fast + elapsed, slow + elapsed
    local m = MapID()
    if not m then return end
    if fast >= 0.05 then
      fast = 0
      UpdateInfo(m)
      if zoomBar and zoomBar:IsShown() then
        zoomBar.slider.Sync()
        -- only on mouse-over: fade in when the cursor comes near the bar
        local want = 1
        if DB.zoomBarHover ~= false then want = zoomBar:IsMouseOver(24, -24, -24, 24) and 1 or 0 end
        local a = zoomBar:GetAlpha()
        if math.abs(a - want) > 0.01 then zoomBar:SetAlpha(a + (want - a) * 0.5) else zoomBar:SetAlpha(want) end
      end
    end
    if slow >= 0.15 then
      slow = 0
      Follow(m)
      UpdateNames(m)
      UpdateLine(m)
    end
  end)
  WorldMapFrame:HookScript("OnShow", function() alphaNow = nil end)
end

---------------------------------------------------------------- options page (#14)
local OPTIONS = {
  { header = "Window" },
  { "Mini mode", "mini", "Small and see-through, stays open while you play.", function(v) NS.SetMini(v) end },
  { "Lock position and size", "locked", nil, function(v) NS.SetLocked(v) end },
  { "Fade while moving", "fadeMoving", "The map turns see-through while you run with it open." },
  { slider = "alpha", label = "Map transparency", min = 30, max = 100 },
  { slider = "fadeAlpha", label = "Transparency while moving", min = 10, max = 100 },
  { slider = "miniAlpha", label = "Transparency in mini mode", min = 20, max = 100 },
  { header = "Getting around" },
  { "Coordinates", "coords", "Your coordinates and the cursor's, at the bottom of the map." },
  { "Zone levels", "zoneLevels", "Zone name and level range (red = too high, yellow = right, green = easy)." },
  { "Breadcrumbs in the top bar", "crumbs", "Click a name to go up to that map." },
  { "Zoom bar", "zoomBar", "+ / - buttons, zoom slider and a zoom-to-me button on the right edge." },
  { "Zoom bar only on mouse-over", "zoomBarHover", "The zoom bar stays hidden until you move the mouse to the right edge of the map." },
  { "Follow me", "follow", "The map scrolls with you while zoomed in.", function(v) NS.SetFollow(v) end },
  { "Ctrl-click sets a waypoint", "waypoint", "Ctrl-click the same spot again to remove it." },
  { slider = "zoom", label = "Max zoom (x past the normal limit)", min = 1, max = 20, raw = true },
  { header = "Quests" },
  { cycle = "questFilter", label = "Quest icons", values = { { "all", "All quests" }, { "tracked", "Tracked only" }, { "notdone", "Hide ready to turn in" } } },
  { "Warcraft-style quest marks", "modernQuest", "Glowing gold ? when ready to turn in, silver ? while still in progress." },
  { "Colored ring per quest", "questRings", "Only used when modern quest icons are off." },
  { "Line to the nearest quest", "nearestLine" },
  { "Show all other map icons too", "allPins", "Flight points, dungeons and everything else the game shows.", function(v) NS.SetAllPins(v) end },
  { header = "Group" },
  { "Names over party members", "partyNames" },
  { "Group pings (Alt-click the map)", "ping", "Everyone in your group with Globus sees it." },
}
local widgets = {}
local function SyncOptions() for _, w in ipairs(widgets) do w.Sync() end end
local function BuildOptions()
  local panel = CreateFrame("Frame")
  panel.name = "Globus"
  local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  t:SetPoint("TOPLEFT", 16, -16); t:SetText("Globus")
  local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
  sub:SetText("Clean, zoomable world map. /globus for commands.")
  local col, y = 0, -56
  for i, o in ipairs(OPTIONS) do
    if i == 17 then col, y = 300, -56 end -- second column
    local x = 16 + col
    if o.header then
      local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      h:SetPoint("TOPLEFT", x, y - 6); h:SetText(o.header)
      y = y - 26
    elseif o.slider then
      local s = CreateFrame("Slider", nil, panel)
      s:SetOrientation("HORIZONTAL"); s:SetSize(200, 16)
      s:SetPoint("TOPLEFT", x + 4, y - 18)
      s:SetMinMaxValues(o.min, o.max); s:SetValueStep(1)
      if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
      s.bg = s:CreateTexture(nil, "BACKGROUND"); s.bg:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
      s.bg:SetPoint("TOPLEFT", 0, -3); s.bg:SetPoint("BOTTOMRIGHT", 0, 3)
      s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
      local l = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3); l:SetText(o.label)
      local v = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"); v:SetPoint("LEFT", s, "RIGHT", 8, 0)
      s:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val + 0.5)
        v:SetText(o.raw and (val .. "x") or (val .. "%"))
        if s.syncing then return end
        if o.raw then
          DB[o.slider] = val
          local sc = SC()
          if sc and sc.CreateZoomLevels and MapID() then pcall(sc.CreateZoomLevels, sc) end
        else
          DB[o.slider] = val / 100
        end
      end)
      s.Sync = function()
        s.syncing = true
        s:SetValue(o.raw and DB[o.slider] or math.floor(DB[o.slider] * 100 + 0.5))
        s.syncing = nil
      end
      widgets[#widgets + 1] = s
      y = y - 46
    elseif o.cycle then
      local l = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("TOPLEFT", x + 4, y - 4); l:SetText(o.label)
      local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
      b:SetSize(160, 22); b:SetPoint("LEFT", l, "RIGHT", 8, 0)
      b.Sync = function()
        for _, v in ipairs(o.values) do if v[1] == DB[o.cycle] then b:SetText(v[2]) end end
      end
      b:SetScript("OnClick", function()
        for k, v in ipairs(o.values) do
          if v[1] == DB[o.cycle] then DB[o.cycle] = o.values[k % #o.values + 1][1]; break end
        end
        NS.FilterPins(); SyncOptions()
      end)
      widgets[#widgets + 1] = b
      y = y - 28
    else
      local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
      cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", x, y)
      local l = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("LEFT", cb, "RIGHT", 4, 1); l:SetText(o[1])
      cb:SetScript("OnClick", function(b)
        local v = b:GetChecked() and true or false
        if o[4] then o[4](v) else DB[o[2]] = v end
        if NS.view and NS.view.bar then BuildCrumbs() end
        if zoomBar then zoomBar:SetShown(DB.zoomBar) end
        NS.FilterPins()
        SyncOptions()
      end)
      if o[3] then
        cb:SetScript("OnEnter", function(b) Tip(b, o[1], o[3]) end)
        cb:SetScript("OnLeave", GameTooltip_Hide)
      end
      cb.Sync = function() cb:SetChecked(DB[o[2]] and true or false) end
      widgets[#widgets + 1] = cb
      y = y - 26
    end
  end
  panel:SetScript("OnShow", SyncOptions)
  local category
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    pcall(Settings.RegisterAddOnCategory, category)
  elseif InterfaceOptions_AddCategory then
    pcall(InterfaceOptions_AddCategory, panel)
  end
  function NS.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
      local id = category.GetID and category:GetID() or category.ID
      pcall(Settings.OpenToCategory, id)
    elseif InterfaceOptionsFrame_OpenToCategory then
      InterfaceOptionsFrame_OpenToCategory(panel)
      InterfaceOptionsFrame_OpenToCategory(panel)
    end
  end
end

---------------------------------------------------------------- start
function NS.SetupFeatures(db)
  DB = db
  MakeUI()
  HookClicks()
  StartTicker()
  do local ok, err = pcall(BuildOptions); if not ok then geterrorhandler()("Globus options: " .. tostring(err)) end end
  if not NS.OpenOptions then NS.OpenOptions = function() Print("options page couldn't be created.") end end
  if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() BuildCrumbs() end) end
  WorldMapFrame:HookScript("OnShow", function() BuildCrumbs() end)

  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("CHAT_MSG_ADDON")
  ev:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
  ev:RegisterEvent("QUEST_LOG_UPDATE")
  local pending
  ev:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
    if event == "CHAT_MSG_ADDON" then
      if prefix ~= PREFIX or not DB.ping or type(msg) ~= "string" then return end
      local who = Ambiguate and Ambiguate(sender or "", "short") or sender
      if who == UnitName("player") then return end -- already shown when sent
      local m, x, y = msg:match("^P:(%d+):([%d%.]+):([%d%.]+)$")
      m, x, y = tonumber(m), tonumber(x), tonumber(y)
      if m and x and y then ShowPing(who, m, x, y) end
      return
    end
    -- quest changes: re-apply the quest filter and rings (once per frame)
    if pending or not WorldMapFrame:IsShown() then return end
    pending = true
    C_Timer.After(0, function() pending = nil; NS.FilterPins() end)
  end)
end
