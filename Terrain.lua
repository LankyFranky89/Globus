-- Globus terrain: when you zoom in past the game's normal limit, the detailed minimap
-- terrain (the same pictures the minimap uses) fades in on top of the map art.
-- Quest areas, quest icons and group dots stay on top.
local ADDON, NS = ...
local DB
local TILE = 533.33333 -- yards per minimap tile
local MAX_TILES = 64
-- continent (instance) id -> minimap folder in the game files
local CONTINENTS = { [0] = "Azeroth", [1] = "Kalimdor" }

local layer          -- frame on the map canvas, just above the map art
local tiles = {}     -- [key] = texture
local missing = {}   -- [path] = true when the game has no picture there (open sea)
local lastKey

local function SC() return NS.SC() end

local function XY(v)
  if not v then return end
  if v.GetXY then return v:GetXY() end
  return v.x, v.y
end

local function ToWorld(mapID, nx, ny)
  local ok, cont, w = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(nx, ny))
  if not ok or not cont or not w then return end
  local wx, wy = XY(w)
  return cont, wx, wy
end
local function ToMap(cont, mapID, wx, wy)
  local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy), mapID)
  if not ok or not pos then return end
  return XY(pos)
end

-- place the terrain layer above the map art AND the explored-area art, but below every
-- other map icon (quest areas, quest icons, you and your group)
local UNDER = { "Exploration", "FogOfWar" }
local function IsUnder(template)
  local t = tostring(template or "")
  for _, k in ipairs(UNDER) do if t:find(k, 1, true) then return true end end
end
local function LevelLayer()
  local child = SC().Child
  local under, over = child:GetFrameLevel(), nil
  for _, c in ipairs({ child:GetChildren() }) do
    if c ~= layer and c:IsShown() then
      local lv = c:GetFrameLevel()
      local tpl = c.pinTemplate
      if tpl then
        if IsUnder(tpl) then
          if lv > under then under = lv end
        elseif not over or lv < over then
          over = lv
        end
      elseif lv < child:GetFrameLevel() + 1000 and lv > under and (not c:GetName() or not tostring(c:GetName()):find("^Globus")) then
        under = lv -- map art frames sit low; other addons' dots sit far above
      end
    end
  end
  local want = under + 1
  if over and want >= over then
    -- no free level between them: lift the other icons above the terrain
    for _, c in ipairs({ child:GetChildren() }) do
      if c.pinTemplate and not IsUnder(c.pinTemplate) and c:GetFrameLevel() <= want then
        c:SetFrameLevel(want + 1)
      end
    end
  end
  if layer:GetFrameLevel() ~= want then layer:SetFrameLevel(want) end
end

local function HideAll()
  for _, t in pairs(tiles) do t:Hide() end
  lastKey = nil
end

local function Fade()
  local sc = SC()
  local base = sc.globusBaseMax
  if not base or base <= 0 then return 0 end
  local cur = sc:GetCanvasScale()
  local k = (cur / base - 0.9) / 0.6 -- starts right at the game's closest zoom, fully in shortly after
  if k <= 0 then return 0 end
  return math.min(1, k) * (DB.terrainAlpha or 0.85)
end

local stats = { shown = 0, missing = 0, reason = "" }
local function Update(force)
  if not (DB and DB.terrain) then HideAll(); layer:Hide(); stats.reason = "off"; return end
  local sc = SC()
  local mapID = WorldMapFrame:GetMapID()
  local alpha = mapID and Fade() or 0
  if alpha <= 0 then layer:Hide(); stats.reason = "not zoomed in far enough"; return end

  local child = sc.Child
  local cw, ch = child:GetWidth(), child:GetHeight()
  local cur = sc:GetCanvasScale()
  local cx, cy = sc.currentScrollX, sc.currentScrollY
  if not (cx and cy and cw > 0 and ch > 0) then layer:Hide(); stats.reason = "no view"; return end
  -- what part of the map is on screen (normalized), with a little margin
  local hw = sc:GetWidth() / (cw * cur) * 0.5 * 1.15
  local hh = sc:GetHeight() / (ch * cur) * 0.5 * 1.15
  local x0, x1 = math.max(0, cx - hw), math.min(1, cx + hw)
  local y0, y1 = math.max(0, cy - hh), math.min(1, cy + hh)

  local cont, wxA, wyA = ToWorld(mapID, x0, y0) -- top-left of the view
  local cont2, wxB, wyB = ToWorld(mapID, x1, y1) -- bottom-right of the view
  local folder = cont and CONTINENTS[cont]
  if not (folder and cont2 == cont) then HideAll(); layer:Hide(); stats.reason = "no minimap pictures for this map"; return end

  -- world X runs north, world Y runs west; tile column from Y, row from X
  local c0 = math.floor(32 - math.max(wyA, wyB) / TILE)
  local c1 = math.floor(32 - math.min(wyA, wyB) / TILE)
  local r0 = math.floor(32 - math.max(wxA, wxB) / TILE)
  local r1 = math.floor(32 - math.min(wxA, wxB) / TILE)
  if (c1 - c0 + 1) * (r1 - r0 + 1) > MAX_TILES then HideAll(); layer:Hide(); stats.reason = "too zoomed out"; return end

  layer:SetAlpha(alpha)
  layer:Show()
  local key = table.concat({ mapID, c0, c1, r0, r1, math.floor(cw), math.floor(ch) }, ":")
  LevelLayer()
  if key == lastKey and not force then return end
  lastKey = key

  local used = {}
  stats.shown, stats.missing = 0, 0
  for col = c0, c1 do
    for row = r0, r1 do
      -- the game only finds these pictures by their file number, not by name
      local ids = NS.MINIMAP_TILES and NS.MINIMAP_TILES[folder]
      local path = ids and ids[col * 100 + row]
      local k = mapID .. ":" .. tostring(path) .. ":" .. col .. "_" .. row
      if not path then
        stats.missing = stats.missing + 1 -- open sea: no picture
      elseif missing[path] then
        stats.missing = stats.missing + 1
      else
        -- tile corners in the world, then on this map
        local nwX, nwY = (32 - row) * TILE, (32 - col) * TILE
        local ax, ay = ToMap(cont, mapID, nwX, nwY)
        local bx, by = ToMap(cont, mapID, nwX - TILE, nwY - TILE)
        if ax and bx then
          local t = tiles[k]
          if not t then
            t = layer:CreateTexture(nil, "ARTWORK")
            local ok = t:SetTexture(path)
            if ok == false then
              missing[path] = true
              t:Hide()
              t = nil
              stats.missing = stats.missing + 1
            else
              tiles[k] = t
            end
          end
          if t then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", layer, "TOPLEFT", ax * cw, -ay * ch)
            t:SetPoint("BOTTOMRIGHT", layer, "TOPLEFT", bx * cw, -by * ch)
            t:Show()
            used[k] = true
            stats.shown = stats.shown + 1
          end
        end
      end
    end
  end
  for k, t in pairs(tiles) do if not used[k] then t:Hide() end end
  stats.reason = ""
end

local function Setup()
  DB = GlobusDB
  local sc = SC()
  if not (DB and sc and sc.Child and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
  layer = CreateFrame("Frame", "GlobusTerrain", sc.Child)
  layer:SetAllPoints(sc.Child)
  layer:EnableMouse(false)
  layer:Hide()
  local acc = 0
  local ticker = CreateFrame("Frame", nil, WorldMapFrame)
  ticker:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc < 0.05 then return end
    acc = 0
    Update()
  end)
  if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() HideAll() end) end
  WorldMapFrame:HookScript("OnShow", function() lastKey = nil end)
end

function NS.TerrainCommand(arg)
  if not layer then NS.Print("terrain isn't available in this game version.") return end
  if arg == "probe" then
    -- try every known way the game might name the minimap picture under you
    local m = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = m and C_Map.GetPlayerMapPosition(m, "player")
    local px, py = XY(pos)
    local cont, wx, wy
    if px then cont, wx, wy = ToWorld(m, px, py) end
    if not wx then NS.Print("probe: can't find your world position here.") return end
    local col, row = math.floor(32 - wy / TILE), math.floor(32 - wx / TILE)
    NS.Print(("probe: continent %s, world %.0f, %.0f, tile %d_%d"):format(tostring(cont), wx, wy, col, row))
    local folder = CONTINENTS[cont] or "Azeroth"
    local tries = {
      ("World\\Minimaps\\%s\\map%d_%d"):format(folder, col, row),
      ("World\\Minimaps\\%s\\map%d_%d.blp"):format(folder, col, row),
      ("World\\Minimaps\\%s\\map%d_%d"):format(folder, row, col),
      ("world/minimaps/%s/map%02d_%02d"):format(folder:lower(), col, row),
      ("Textures\\Minimap\\%s\\map%d_%d"):format(folder, col, row),
      ("World\\Minimaps\\%s\\%s_%d_%d"):format(folder, folder, col, row),
    }
    local ids = NS.MINIMAP_TILES and NS.MINIMAP_TILES[folder]
    if ids and ids[col * 100 + row] then table.insert(tries, 1, ids[col * 100 + row]) end
    -- show the picture under you in the middle of the screen for 8 seconds
    local id = ids and ids[col * 100 + row]
    if id then
      local f = NS.probeFrame or CreateFrame("Frame", nil, UIParent)
      NS.probeFrame = f
      f:SetSize(256, 256); f:SetPoint("CENTER"); f:SetFrameStrata("TOOLTIP")
      f.t = f.t or f:CreateTexture(nil, "ARTWORK"); f.t:SetAllPoints(); f.t:SetTexture(id)
      f:Show()
      C_Timer.After(8, function() f:Hide() end)
      NS.Print("probe: showing terrain picture " .. id .. " in the middle of your screen for 8 seconds.")
    end
    local t = layer:CreateTexture()
    for _, path in ipairs(tries) do
      t:SetTexture(nil)
      local ok = t:SetTexture(path)
      print(("  %s -> %s / %s"):format(path, tostring(ok), tostring(t:GetTexture())))
    end
    t:Hide()
    return
  end
  if arg == "test" then
    Update(true)
    NS.Print(("terrain: %s, %d pictures shown, %d spots without a picture%s."):format(
      DB.terrain and "on" or "off", stats.shown, stats.missing, stats.reason ~= "" and (" (" .. stats.reason .. ")") or ""))
    return
  end
  local n = tonumber(arg)
  if n then
    DB.terrainAlpha = math.max(10, math.min(100, n)) / 100
    NS.Print("terrain strength " .. math.floor(DB.terrainAlpha * 100 + 0.5) .. "%.")
    return
  end
  DB.terrain = not DB.terrain
  Update(true)
  NS.Print(DB.terrain and "detailed terrain on when zoomed in." or "detailed terrain off.")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() C_Timer.After(0, function()
  local ok, err = pcall(Setup)
  if not ok then geterrorhandler()("Globus terrain: " .. tostring(err)) end
end) end)
