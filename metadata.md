# CurseForge Project Metadata

## Project

- **Name:** Prokin-Minimap
- **Game:** World of Warcraft
- **Compatibility:** The Burning Crusade Anniversary / TBC Classic
- **Interface Version:** 20505
- **Class:** Addons
- **Main Category:** Map & Minimap
- **Additional Categories:** UI
- **License:** All Rights Reserved
- **Repository:** https://github.com/gnummers/Prokin-Minimap

## Summary

Square minimap addon for The Burning Crusade Anniversary with ElvUI-style masking, persistent resizing, custom icon support, polished header handling, a server-time zone label, and compatibility shims for minimap buttons, Blizzard widgets, and MinimapButtonButton.

## Description

Prokin-Minimap is a lightweight World of Warcraft addon for The Burning Crusade Anniversary that replaces the default round minimap with a square one using the same mask approach ElvUI uses on TBC.

Features:

- Square minimap mask using `Interface\ChatFrame\ChatFrameBackground`
- Reports `GetMinimapShape()` as `SQUARE` for addon compatibility
- Reapplies the square minimap on world entry, minimap show, and Blizzard hybrid minimap load
- Minimap zoom in and out with the mouse wheel
- Uses a pfUI-style custom zone label with a server-time suffix in `[HH:MM AM/PM]` format, plus runtime-safe suppression of Blizzard minimap header widgets so the floating bar, red X, and duplicate zone text do not appear
- Adds always-visible Blizzard-style tracking and LFG proxy buttons just outside the square minimap border without letting MinimapButtonButton collect them into its tray
- Keeps the Blizzard mail icon visible only while unread mail is waiting
- Keeps a PvP or battleground proxy button outside the square minimap border only when Blizzard battlefield state is active
- Lets you left-drag the visible Blizzard minimap widgets around the outside edge of the square minimap border with saved positions
- Includes MinimapButtonButton compatibility so those Blizzard widgets are not pulled into its collected button tray
- Repositions the AutoMarkAssist minimap button to the square minimap edge without modifying AutoMarkAssist
- Persistent square resizing with a default size of `400x400`
- Header spacing that keeps the zone text visible when the minimap is enlarged
- Custom 1 pixel black border around the minimap

Slash commands:

- `/pkm`
- `/pkm size 400`
- `/pkm larger`
- `/pkm larger 50`
- `/pkm smaller`
- `/pkm smaller 50`
- `/pkm reset`

Saved variable:

- `ProkinMinimapDB`

## Project Avatar

- **File:** `C:\Users\moose\source\repos\Prokin-Minimap\CurseForge\ProjectAvatar-400.png`
- **Size:** 400x400

## Initial Release File

- **File:** `C:\Users\moose\source\repos\Prokin-Minimap\CurseForge\Prokin-Minimap-1.0.16.zip`
- **Display Name:** Prokin-Minimap v1.0.16
- **Release Type:** Release
- **Supported Version:** Select the TBC / Burning Crusade Anniversary option that matches interface `20505`

## Changelog

- Initial CurseForge release
- Added ElvUI-style square minimap behavior for TBC Anniversary
- Added persistent minimap resizing with a default size of 400x400
- Added refresh hooks for world entry, minimap show, and hybrid minimap loading
- Added mousewheel minimap zoom support
- Switched to a pfUI-style custom zone label and fixed the suppression helper so Blizzard header widgets and duplicate zone text are disabled reliably
- Added a server-time suffix to the custom zone label using `[HH:MM AM/PM]`
- Fixed TBC Anniversary compatibility by avoiding `Set*Texture(nil)` calls on Blizzard minimap header buttons
- Added AutoMarkAssist minimap button compatibility so its icon is clamped to the square minimap edge
- Restored the Blizzard tracking, LFG, clock, mail, and PvP or battleground widgets and anchored them outside the square minimap border
- Added MinimapButtonButton compatibility so those Blizzard widgets stay outside the square minimap instead of being collected into its tray
- Added always-visible Blizzard-style tracking and LFG proxy buttons outside the square minimap border
- Restored Blizzard-native tracking dropdown behavior and conditional PvP indicator visibility while keeping LFG proxy access available
- Moved the tracking and LFG proxy buttons off the minimap itself so MinimapButtonButton no longer collects them into its tray
- Added a conditional PvP or battleground proxy button that only shows while Blizzard battlefield state is active
- Tightened the mail icon handling so it only shows when `HasNewMail()` reports unread mail
- Fixed the tracking proxy button so clicking it opens Blizzard's tracking menu correctly
- Added saved left-drag positioning for the visible Blizzard minimap widgets around the outside edge of the square minimap border
- Fixed the draggable widget wrapper so it only hooks scripts Blizzard frames actually support on TBC Anniversary
- Removed the visible pixel gap so the Blizzard minimap widgets sit flush against the square minimap border
- Improved tracking button detection so the proxy targets the first Blizzard tracking control that actually exposes a menu handler on TBC Anniversary
- Split the zone-header spacing from widget edge spacing so the zone name and server time label keep their 4 pixel top offset independently
- Added 4 pixel zone header spacing to prevent overlap
- Added a 1 pixel black border around the minimap
- Added custom addon icon support

## Packaging Notes

- The release zip already contains a top-level `Prokin-Minimap` folder for CurseForge distribution.
- The zip includes only the addon files needed for installation:
  - `Prokin-Minimap.lua`
  - `Prokin-Minimap.toc`
  - `Media\ProkinFaceIcon.png`
