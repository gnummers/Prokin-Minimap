# Changelog

## v1.0.15
- Fixed the draggable widget wrapper so it only hooks scripts a Blizzard frame actually supports on TBC Anniversary
- Resolved the `GameTimeFrame:GetScript()` and `MiniMapMailFrame:GetScript()` Lua errors caused by drag suppression logic probing missing `OnClick` handlers

## v1.0.14
- Fixed the tracking proxy button so clicking it opens Blizzard's tracking menu correctly
- Added saved left-drag positioning for the visible Blizzard minimap widgets around the outside edge of the square minimap border
- Preserves widget reordering across reloads and keeps the dragged widgets clamped to the square border

## v1.0.13
- Moved the tracking and LFG proxy buttons off the minimap itself so MinimapButtonButton no longer collects them into its tray
- Added a conditional PvP or battleground proxy button that only shows while Blizzard battlefield state is active
- Tightened the mail icon handling so it only shows when `HasNewMail()` reports unread mail

## v1.0.12
- Added always-visible Blizzard-style tracking and LFG proxy buttons outside the square minimap border
- Wired the tracking proxy to Blizzard's native tracking dropdown behavior and forwarded the LFG proxy to Blizzard queue handlers when available
- Stopped force-showing the PvP or battleground indicator so it only appears when Blizzard would normally display it

## v1.0.11
- Added MinimapButtonButton compatibility for the Blizzard tracking, LFG/queue, clock, mail, and PvP/battleground widgets
- Preserves the original widget methods so Prokin-Minimap can still reparent and anchor those frames even after MinimapButtonButton overrides them
- Writes those Blizzard widgets into the MinimapButtonButton blacklist so they stay out of its collected button tray on future loads

## v1.0.10
- Restored the Blizzard tracking, LFG/queue, clock, mail, and PvP/battleground minimap widgets
- Anchored those Blizzard widgets just outside the square minimap border
- Added re-anchoring hooks so Blizzard repositioning is corrected automatically
- Added `Blizzard_TimeManager` handling so the clock is re-anchored when it loads

## v1.0.9
- Added a Prokin-Minimap compatibility hook for AutoMarkAssist
- Repositions the `AMA_MinimapButton` to the square minimap edge without modifying AutoMarkAssist
- Updated README and release metadata for the new compatibility behavior

## v1.0.8
- Fixed the TBC Anniversary Lua error caused by calling Blizzard minimap button texture setters with `nil`
- Changed header suppression to clear and hide existing texture objects directly instead of using `Set*Texture(nil)`
- Updated release metadata for the compatibility fix

## v1.0.7
- Added a server-time suffix to the custom zone label
- Time displays in 12-hour format as `[HH:MM AM/PM]`
- Updated README and release metadata to document the new label format

## v1.0.6
- Fixed the minimap header suppression helper to handle Blizzard objects more safely at runtime
- Improved reliability of hiding the floating header chrome, red X, and duplicate zone text
- Updated README to reflect the pfUI-style custom zone label approach

## v1.0.5
- Expanded suppression of Blizzard minimap header elements
- Added broader handling for legacy and cluster-owned header widgets
- Improved attempts to stop the default zone header from reappearing

## v1.0.4
- Hardened the custom zone label replacement
- Improved Blizzard header suppression behavior
- Updated documentation for the custom zone label behavior

## v1.0.3
- Switched toward a custom minimap zone label approach
- Reduced reliance on Blizzard's default zone header
- Continued work on removing duplicate zone text and header chrome

## v1.0.2
- Added the first pass of minimap zone-header chrome cleanup
- Began removing the floating frame and close button around the zone name

## v1.0.1
- Added mousewheel zoom support for the minimap
- Matched the ElvUI-style zoom behavior for wheel up/down
- Applied zoom handling to both the normal minimap and hybrid minimap

## v1.0.0
- Initial public release
- Added ElvUI-style square minimap masking for TBC Anniversary
- Added persistent minimap resizing with a default size of `400x400`
- Added refresh hooks so the square minimap reapplies correctly
- Added hybrid minimap compatibility
- Added zone header spacing improvements
- Added a custom 1px black minimap border
- Added addon icon support and release packaging for GitHub/CurseForge
