# Globus

A clean, borderless world map for WoW Forever: just the map and your quest tracking.

## Features

- **Only what matters:** the map, quest areas, quest icons, you and your group. Title bar, frame art, filters and the quest list are hidden (`/globus icons` shows everything again).
- **Deep zoom:** mouse wheel zooms toward the cursor, far past the normal limit (`/globus zoom 2-20`).
- **Detailed terrain:** when zoomed in past the normal limit, the minimap terrain fades in (Eastern Kingdoms and Kalimdor).
- **Move and resize:** drag the empty part of the top bar to move, drag the gold corner to resize. The map keeps its shape at any size.
- **Toolbar** (on hover): clickable breadcrumbs (Azeroth > Eastern Kingdoms > Westfall), lock, mini mode, follow and options.
- **Zoom bar** on the right edge (on mouse-over): + / slider / - and zoom-to-me.
- **Info line:** zone with its level range (red / yellow / green for your level), your coordinates and the cursor's.
- **Ctrl-click** sets a waypoint, **Alt-click** pings your group (everyone with Globus sees it).
- **Quests:** filter (all / tracked only / hide ready to turn in), line to the nearest quest, optional colored ring per quest or Warcraft-style quest marks.
- **Group:** names over party members.
- **Mini mode:** small and see-through, stays open while you play. **Fade while moving** makes the map see-through while you run.
- **Options page:** Esc > Options > AddOns > Globus.

## Works with

- **Quest Ledger Forever:** its quest log docks beside the Globus map.
- **QuestMates:** friends' quest areas and markers on the map, same size on screen at any zoom.
- **TrekTime:** Dungeons / Raids toggles as round buttons on the map.

## Commands

| Command | What it does |
|---|---|
| `/globus` | Help |
| `/globus options` | Settings window |
| `/globus mini` | Mini mode on/off |
| `/globus lock` | Lock / unlock moving and resizing |
| `/globus follow` | Map follows you while zoomed in |
| `/globus zoom 8` | How far past the normal zoom limit you can go |
| `/globus icons` | Show all map icons / only quest tracking |
| `/globus alpha 80` | Map transparency |
| `/globus terrain` | Detailed terrain on/off (`/globus terrain 60` for strength) |
| `/globus reset` | Size and position back to default |
| `/globus debug` | Diagnostics |

## Install

Copy the `Globus` folder into `World of Warcraft\_forever_\Interface\AddOns\` and `/reload` (restart the game the first time so the icons load).

Terrain file numbers in `TerrainData.lua` come from the community WoW listfile (wowdev/wow-listfile).
