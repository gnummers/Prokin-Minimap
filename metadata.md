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

Square minimap addon for The Burning Crusade Anniversary with ElvUI-style masking, persistent resizing, custom icon support, and polished header spacing.

## Description

Prokin-Minimap is a lightweight World of Warcraft addon for The Burning Crusade Anniversary that replaces the default round minimap with a square one using the same mask approach ElvUI uses on TBC.

Features:

- Square minimap mask using `Interface\ChatFrame\ChatFrameBackground`
- Reports `GetMinimapShape()` as `SQUARE` for addon compatibility
- Reapplies the square minimap on world entry, minimap show, and Blizzard hybrid minimap load
- Minimap zoom in and out with the mouse wheel
- Uses a pfUI-style custom zone label and runtime-safe suppression of Blizzard minimap header widgets so the floating bar, red X, and duplicate zone text do not appear
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

- **File:** `C:\Users\moose\source\repos\Prokin-Minimap\CurseForge\Prokin-Minimap-1.0.6.zip`
- **Display Name:** Prokin-Minimap v1.0.6
- **Release Type:** Release
- **Supported Version:** Select the TBC / Burning Crusade Anniversary option that matches interface `20505`

## Changelog

- Initial CurseForge release
- Added ElvUI-style square minimap behavior for TBC Anniversary
- Added persistent minimap resizing with a default size of 400x400
- Added refresh hooks for world entry, minimap show, and hybrid minimap loading
- Added mousewheel minimap zoom support
- Switched to a pfUI-style custom zone label and fixed the suppression helper so Blizzard header widgets and duplicate zone text are disabled reliably
- Added 4 pixel zone header spacing to prevent overlap
- Added a 1 pixel black border around the minimap
- Added custom addon icon support

## Packaging Notes

- The release zip already contains a top-level `Prokin-Minimap` folder for CurseForge distribution.
- The zip includes only the addon files needed for installation:
  - `Prokin-Minimap.lua`
  - `Prokin-Minimap.toc`
  - `Media\ProkinFaceIcon.png`
