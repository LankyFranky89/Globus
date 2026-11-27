-- Globus fishing ranges: when Forever Fishing is installed, shows the fishing skill range of a zone
-- (minimum / reliable) as a hover tooltip on continent maps and as a badge in the corner of zone maps.
-- Colored by your own fishing skill. Ranges match Forever Fishing's own zone table.
local ADDON, NS = ...
local DB

-- { minimum, reliable, { zones } } (same tiers Forever Fishing uses)
local TIERS = {
  { 1, 25, { "Dun Morogh", "Durotar", "Elwynn Forest", "Mulgore", "Teldrassil", "Tirisfal Glades", "Zephras Isle" } },
  { 1, 75, { "The Barrens", "Darkshore", "Darnassus", "Ironforge", "Loch Modan", "Orgrimmar", "Silverpine Forest",
             "Stormwind City", "Stormwind", "Thunder Bluff", "Undercity", "Westfall", "Blackfathom Deeps", "Wailing Caverns" } },
  { 55, 150, { "Ashenvale", "Duskwood", "Hillsbrad Foothills", "Redridge Mountains", "Stonetalon Mountains", "Wetlands" } },
  { 130, 225, { "Alterac Mountains", "Arathi Highlands", "Desolace", "Dustwallow Marsh", "Stranglethorn Vale",
                "Swamp of Sorrows", "Thousand Needles" } },
  { 205, 300, { "Azshara", "Felwood", "Feralas", "The Hinterlands", "Hinterlands", "Moonglade", "Tanaris",
                "Un'Goro Crater", "Western Plaguelands" } },
  { 330, 425, { "Eastern Plaguelands", "Winterspring", "Zul'Gurub" } },
}
local NOTES = {
  ["Azshara"] = "Bay of Storms, Hetaera's Clutch and Scalebeard's Cave: 330 / 425",
  ["Feralas"] = "Jademir Lake: 330 / 425",
  ["Stranglethorn Vale"] = "Jaguero Isle: 205 / 300",
  ["Ironforge"] = "Some Ironforge water may not be fishable.",
}
-- map IDs (same as Forever Fishing's list) so renamed/localized zones still match
local IDS = {
  [1429] = "Elwynn Forest", [1411] = "Durotar", [1426] = "Dun Morogh", [1412] = "Mulgore", [1438] = "Teldrassil",
  [1420] = "Tirisfal Glades", [1453] = "Stormwind City", [1454] = "Orgrimmar", [1456] = "Thunder Bluff",
  [1457] = "Darnassus", [1455] = "Ironforge", [1458] = "Undercity", [1432] = "Loch Modan", [1436] = "Westfall",
  [1439] = "Darkshore", [1413] = "The Barrens", [1421] = "Silverpine Forest", [1433] = "Redridge Mountains",
  [1437] = "Wetlands", [1440] = "Ashenvale", [1424] = "Hillsbrad Foothills", [1442] = "Stonetalon Mountains",
  [1431] = "Duskwood", [1416] = "Alterac Mountains", [1417] = "Arathi Highlands", [1443] = "Desolace",
  [1445] = "Dustwallow Marsh", [1434] = "Stranglethorn Vale", [1435] = "Swamp of Sorrows", [1441] = "Thousand Needles",
  [1444] = "Feralas", [1446] = "Tanaris", [1425] = "The Hinterlands", [1448] = "Felwood", [1450] = "Moonglade",
  [1449] = "Un'Goro Crater", [1422] = "Western Plaguelands", [1423] = "Eastern Plaguelands", [1452] = "Winterspring",
  [1447] = "Azshara",
}
local RANGE = {}
for _, t in ipairs(TIERS) do for _, z in ipairs(t[3]) do RANGE[z] = { t[1], t[2] } end end

local function FishingInstalled()
  local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if f then local ok, loaded = pcall(f, "ForeverFishing"); if ok and loaded then return true end end
  return _G.ForeverFishing ~= nil
end

local function Lookup(mapID, name)
  local key = (mapID and IDS[mapID]) or name
  if key and RANGE[key] then return key, RANGE[key][1], RANGE[key][2] end
  if name and RANGE[name] then return name, RANGE[name][1], RANGE[name][2] end
end

-- your effective fishing skill (rank + gear/lure bonus), nil if unknown
local skillCache, skillTime = nil, 0
local function MySkill()
  if GetTime() - skillTime < 2 then return skillCache end
  skillTime, skillCache = GetTime(), nil
  local fishing = (GetSpellInfo and GetSpellInfo(7620)) or "Fishing"
  if GetProfessions and GetProfessionInfo then
    local ok, _, _, _, fish = pcall(GetProfessions)
    if ok and fish then
      local ok2, _, _, rank, _, _, _, _, mod = pcall(GetProfessionInfo, fish)
      if ok2 and rank then skillCache = rank + (mod or 0); return skillCache end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local ok, name, header, _, rank, _, mod = pcall(GetSkillLineInfo, i)
      if ok and not header and (name == fishing or name == "Fishing") then
        skillCache = (rank or 0) + (mod or 0); return skillCache
      end
    end
  end
  return nil
end

local function Color(lo, hi)
  local s = MySkill()
  if not s then return "ffffff" end
  if s < lo then return "ff4040" end      -- too low: can't fish here yet
  if s < hi then return "ffd200" end      -- can fish, but fish get away
  if s >= hi + 75 then return "9d9d9d" end -- easy, no skill-ups worth it
  return "40ff40"                         -- reliable
end
local function RangeText(lo, hi) return ("|cff%sFishing %d-%d|r"):format(Color(lo, hi), lo, hi) end

local function FillTip(tip, zone, lo, hi)
  tip:AddLine(zone, 1, 0.82, 0)
  tip:AddLine(RangeText(lo, hi))
  tip:AddLine(("Minimum %d  •  Reliable %d"):format(lo, hi), 0.8, 0.8, 0.8)
  local s = MySkill()
  if s then tip:AddLine(("Your Fishing: %d"):format(s), 0.6, 0.8, 1) end
  if NOTES[zone] then tip:AddLine(NOTES[zone], 0.9, 0.7, 0.4, true) end
end

local tip, badge
local function MakeUI()
  local sc = WorldMapFrame.ScrollContainer
  tip = CreateFrame("GameTooltip", "GlobusFishingTip", UIParent, "GameTooltipTemplate")
  tip:SetFrameStrata("TOOLTIP")

  badge = CreateFrame("Frame", nil, sc)
  badge:SetFrameLevel(sc:GetFrameLevel() + 2100)
  badge:SetHeight(20)
  badge:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", -8, 8)
  badge.bg = badge:CreateTexture(nil, "BACKGROUND"); badge.bg:SetAllPoints()
  badge.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background"); badge.bg:SetVertexColor(0.04, 0.03, 0.02, 0.85)
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                       { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local t = badge:CreateTexture(nil, "BORDER")
    t:SetTexture("Interface\\Buttons\\WHITE8X8"); t:SetVertexColor(0.78, 0.62, 0.22, 0.9)
    t:SetPoint(e[1]); t:SetPoint(e[2])
    if e[3] then t:SetHeight(1) else t:SetWidth(1) end
  end
  badge.icon = badge:CreateTexture(nil, "ARTWORK")
  badge.icon:SetSize(14, 14); badge.icon:SetPoint("LEFT", 5, 0)
  badge.icon:SetTexture("Interface\\Icons\\Trade_Fishing"); badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  badge.txt = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  badge.txt:SetPoint("LEFT", badge.icon, "RIGHT", 4, 0)
  badge:EnableMouse(true)
  badge:SetScript("OnEnter", function(self)
    if not self.zone then return end
    tip:SetOwner(self, "ANCHOR_TOPRIGHT"); tip:ClearLines()
    FillTip(tip, self.zone, self.lo, self.hi); tip:Show()
    self.hovered = true
  end)
  badge:SetScript("OnLeave", function(self) self.hovered = nil; tip:Hide() end)
  badge:Hide()
end

local function Update()
  if not (DB.fishRanges and FishingInstalled()) then badge:Hide(); tip:Hide(); return end
  local m = WorldMapFrame:GetMapID()
  if not m then return end
  local mi = C_Map.GetMapInfo(m)

  -- badge on a zone map
  local zone, lo, hi = Lookup(m, mi and mi.name)
  if zone then
    badge.zone, badge.lo, badge.hi = zone, lo, hi
    badge.txt:SetText(RangeText(lo, hi))
    badge:SetWidth(badge.txt:GetStringWidth() + 30)
    badge:Show()
  else
    badge.zone = nil; badge:Hide()
  end
  if badge.hovered then return end

  -- hover tooltip over zones on a continent map
  local sc = WorldMapFrame.ScrollContainer
  local hz
  if sc:IsMouseOver() and C_Map.GetMapInfoAtPosition then
    local cx, cy = sc:GetNormalizedCursorPosition()
    if cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
      local ok, sub = pcall(C_Map.GetMapInfoAtPosition, m, cx, cy)
      if ok and sub and sub.mapID and sub.mapID ~= m then
        local z, l, h = Lookup(sub.mapID, sub.name)
        if z then hz, lo, hi = z, l, h end
      end
    end
  end
  -- stay out of the way of quest/pin tooltips
  if hz and not (GameTooltip:IsShown() and GameTooltip:GetOwner() ~= nil) then
    if tip.zone ~= hz or not tip:IsShown() then
      tip:SetOwner(sc, "ANCHOR_CURSOR_RIGHT", 18, 0); tip:ClearLines()
      FillTip(tip, hz, lo, hi); tip:Show(); tip.zone = hz
    end
  elseif tip:IsShown() then
    tip:Hide(); tip.zone = nil
  end
end

function NS.SetupFishing(db)
  DB = db
  if DB.fishRanges == nil then DB.fishRanges = true end
  MakeUI()
  local acc = 0
  local driver = CreateFrame("Frame", nil, WorldMapFrame)
  driver:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc < 0.1 then return end
    acc = 0
    Update()
  end)
  WorldMapFrame:HookScript("OnHide", function() tip:Hide(); tip.zone = nil end)
end
NS.FishingInstalled = FishingInstalled
