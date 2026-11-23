## v1.0.56
- The options window now sizes itself to fit everything in it, so the help text at the bottom is no longer cut off at the window's edge, whatever your UI scale. It also starts 40 px taller

## v1.0.55
- The Revelation proc alert is now a pulsing banner in the middle of the screen with the Revelation icon, "REVELATION!" and "Next spell guaranteed crit". It stays up to 6 seconds, or until the buff fades, and still plays a sound
- Added a "Show Revelation proc alert" option to turn the alert off
- Revelation detection also watches spell ID 1248806, from an earlier build
- The Mark Pack key setting in Options now has Apply and Reset buttons, shows the default (5), and explains key names in its tooltip. Leaving the box empty turns the key off

## v1.0.54
- Fixed the options window layout: the Zone Text Size and Addon Icon Spacing sliders no longer overlap each other or the buff icon buttons, and the help text at the bottom now wraps inside the window instead of running off the right edge

## v1.0.53
- Added separate Options checkboxes to show or hide the Friends and Guild buttons; both remain visible by default
- Tightened the Options layout so the new controls fit in the window

## v1.0.52
- Fixed Revelation fallback detection to read the aura spell ID from the correct `UnitBuff` return value
- Added Wowhead Looter’s standalone minimap button to the left-side icon alignment
- Moved the Friends and Guild hover buttons to the right of player coordinates
- Widened the Options window text area and removed the extra border line beneath the Minimap Size slider

## v1.0.51
- Revelation notifications now detect repeated aura applications and refreshes even while an earlier Revelation buff is still active

## v1.0.50
- Added class colors to character names in the Friends and Guild hover rosters, using class-file tokens and localized class-name fallbacks

## v1.0.49
- Added dedicated Friends and Guild minimap hover buttons with individual online rosters and member locations; positioned the buttons below the minimap to the left of the player coordinates, with clearer spacing between section headers and roster rows
- Aligned GearQuest Forever's standalone minimap button with the left-side icon column

## v1.0.48
- Added separate Friends and Guild minimap hover buttons with individual online rosters and member locations
- Aligned GearQuest Forever's standalone minimap button with the left-side icon column

## v1.0.47
- Added Friends and Guild online rosters to the Prokin minimap button tooltip, including member locations, levels, classes, and status where the client provides them

## v1.0.46
- Mark Pack's prepared secure macro now remains available after combat starts, so the nearby pack can still be marked during combat. Mark Mob continues to mark a hovered NPC at any time.
- Added a Mark Pack key field to Prokin Minimap Options; press Enter to save. `/pkm mark key <key|none|default>` remains available.
- Added a visual notification and sound when Revelation activates. Detection uses WoW Forever's class-specific Revelation spell IDs.

## v1.0.45
- Smart marking and Mark Pack now follow the full standard target marker convention, using the crowd control of the classes in your party or raid:
  - Skull: first kill target. Cross: second kill target
  - Moon: Mage, Polymorph
  - Square: Hunter, Freezing Trap
  - Star: Rogue, Sap; without a rogue, the third kill target
  - Diamond: Warlock, Banish, then Seduce, then Fear
  - Triangle: Druid, Hibernate, then Entangling Roots; without a druid, an elite for the off-tank
  - Circle: Priest, Shackle Undead, then Mind Control; without a priest, Circle goes on your tank (the player with the Tank role, or a raid's main tank) as the stack/tank marker
- Crowd control that only holds certain creature types is placed first, so Freezing Trap no longer takes a demon a warlock could banish. In combat, the third kill target moves up to Cross when Skull dies

## v1.0.44
- Mark Pack now works outside dungeon groups: on your own anywhere, as a party leader, and in raids as the raid leader or an assistant (the only raid members the game lets mark). Raid crowd control counts every class in the raid
- The Mark Pack key (5) no longer takes over its action button. Near unmarked mobs, one press marks the pack; with nothing to mark, and all through combat, the key uses its usual action button. A key bound to something other than an action button is only taken inside instances
- On The Burning Crusade Anniversary, Mark Pack is also available where automatic marking is off, such as raids and solo play

## v1.0.43
- Fixed an `[ADDON_ACTION_FORBIDDEN]` error on WoW Forever at login: smart marking no longer registers the combat log, which Forever does not allow addons to use. Deaths are now seen on the mobs themselves
- Fixed a "junk after document element" warning from `Bindings.xml`

## v1.0.42
- Added smart dungeon marking, on by default when you lead a 5-player dungeon group. Each pack gets a kill order: Skull, then Cross, going to bosses, elites, healers and casters first. Crowd-control icons follow your group: Moon for Polymorph, Square for Freezing Trap, Circle for Shackle Undead, Diamond for Banish, Triangle for Hibernate and Star for Sap, each only on mobs it can hold. In combat, Cross moves to Skull when Skull dies and the next mob gets Cross. Icons other players placed are left alone
- On The Burning Crusade Anniversary, packs are marked automatically as you approach them. WoW Forever only lets the game place icons from a key press, so bind Mark Mob (Key Bindings > AddOns > Prokin Minimap) and press it while hovering a mob. A Clear All Marks binding is included
- On WoW Forever, the Mark Pack key marks a whole pack with one press: walk up to a pack and press **5**. Prokin holds 5 only while you lead a dungeon group, without changing your saved key bindings, so action button 5 works as normal everywhere else. Change it with `/pkm mark key <key>` (or `none`), or bind Mark Pack in Key Bindings. An account-wide "Prokin Mark Pack" macro is also created once, for putting it on an action bar on any character. Mark Pack works before the pull; in combat, use Mark Mob
- `/pkm mark` shows the marking state and your group's crowd control. `/pkm mark on|off`, `/pkm mark leader|anyone`, `/pkm mark priority` and `/pkm mark ignore` (for your target's NPC), and `/pkm mark clear`. Marking pauses while AutoMarkAssist is loaded
- Smart marking knows every 5-player dungeon boss in Classic, TBC and WoW Forever's new dungeons, so bosses get Skull and are never given a crowd-control icon, even though most show an ordinary level. It also knows over 100 dangerous trash mobs (healers, summoners, fears and hard-hitting casters, with TBC heroic versions), which are killed first, such as Scarlet Abbots, Coilfang Oracles and Cabal Acolytes. Boss names for Classic and Forever dungeons come from AKForeverTargeter by Purrdee (MIT License)

## v1.0.41
- Added an experimental Auction House upgrade scan for WoW Forever. A Prokin tab on the Auction House scans armor and weapons and lists the biggest upgrade and best value for every equipment slot (or that there is none). Items are scored with Pawn scales or RestedXP Guides stat weights (requires Pawn or RestedXP Guides). Options picks the weights, class, specialization (every spec of all 9 classes) and required level range, and can add stat filters so only items with the stats you want (any or all, with optional minimums) are listed. Options are saved per character. Show opens the listing in the Buy view, where you confirm the purchase, and Shift+Right-click on a result links the item in chat
- Added an experimental WoW Forever language test. `/pkm language` shows your preferred language, datacenter, guild language and change cooldown. Confirmed layers are logged with those settings (`/pkm language log`) to test reports that language affects layer placement. `/pkm language set <language> confirm` changes the account language, which the game then locks for its cooldown
- The layer log also records what players report can move you to another layer: joining or leaving a group (with the leader's zone), joining or leaving a guild, crossing into another zone, loading screens and world-refresh notices. A changed layer in the same zone is announced in chat and marked in the log. `/pkm language note <text>` adds your own note

## v1.0.40
- On WoW Forever, Prokin now warns in chat when your group leader is in a different zone, because that invite cannot change your layer. When the leader is in your zone, it reminds you to click the blue world-refresh notice and press Refresh Now

## v1.0.39
- Added an experimental layer display for WoW Forever in the bottom-right corner of the minimap, read from NPC data after two NPCs agree. It also shares the layer with AutoLayer, and can be turned off in options. `/pkm layer` shows details
- Fills AutoLayer's Hopper layer list without Nova World Buffs, using the highest copy seen in each zone over the last 12 hours
- Added an any-layer AutoLayer request, even when the current layer is known: left-click the layer display or type `/pkm hop`. Right-click the layer display opens the AutoLayer Hopper

## v1.0.38
- Fixed addon icons breaking out of the left-border column on minimaps smaller than 400. Icons now tighten to fit, and any that still don't fit start a new column outside the map
- Fixed invisible addon buttons leaving gaps in the left-border column. Show-on-hover buttons now go after the always-visible icons

## v1.0.37
- Added movable Blizzard buff icons: unlock them from the options window or `/pkm buffs`, then drag the blue box. Debuffs stay anchored under the buffs

## v1.0.36
- Added World of Warcraft: Forever support (TOC `16001`) alongside The Burning Crusade Anniversary
- Updated the Anniversary TOC to `20506` for patch 2.5.6
- Removed the clock below the minimap; the zone label still shows the time
- Pinned Blizzard's player coordinates directly under the minimap and centered them
- With icon alignment off, Forever's day/night icon can be left-dragged anywhere on the map; `/pkm resetmoon` restores it to the top-right corner
- Addon minimap buttons now share one size and line up along the left border, with an option to turn this off
- Added an Addon Icon Spacing slider to the options window to move those icons closer together or further apart
- The Blizzard tracking button and Forever's day/night icon now match the addon icon size, and join the left-border column and its spacing slider
- Added a zone text size setting in the options window and `/pkm zonetext <number|reset>`
- Updated tracking, item info, and addon-loading calls to the namespaced APIs Forever requires
- Fixed a Lua error on new mail, an invisible mail icon, and the round mask returning when map rotation changes on Forever
- Moved the Forever zoom buttons and addon compartment onto the square minimap
- Forever uses its native queue eye, which appears only while queued, instead of the LFG proxy button
- Handled secret values in the role tooltip, character ledger, and loot message parsing
- Fixed a Lua error when a loot message mentioned disenchanting
- Stopped replacing the global `GetRepairAllCost`, which could taint the merchant repair UI

## v1.0.34
- Tooltip and gold tracking now display negative values for net loss (e.g., after repairs or expenses)

## v1.0.33
- Added comprehensive expense tracking system with multi-category support (repairs, postage, crafting, disenchanting)
- Implemented per-character ledgers with timestamped expense history and category breakdowns
- Added inventory worth calculation using TSM pricing or vendor fallback
- Simplified tooltip to show only GPH, Session net, and Daily net income
- Added new slash commands: `/pkm ledger`, `/pkm expenses`, `/pkm allcharacters`
- Automatic repair cost detection via `GetRepairAllCost()`
- Automatic postage detection via `GetSendMailPrice()`
- Crafting material cost tracking through inventory snapshots
- Disenchanting transaction detection via chat message parsing
- Maintained backward compatibility with existing tracking features

## v1.0.32
- Changed the persistent Daily Total so each character tracks its own total separately
- Kept the midnight server-time reset behavior for each character's daily total

## v1.0.31
- Added TSM-independent item pricing fallback so gold tracking still works without TradeSkillMaster installed
- Added visible TradeSkillMaster author credit in the options help text and documentation

## v1.0.30
- Fixed the mail visibility watchdog so it no longer recurses when the mail frame is hidden
- Kept the periodic mail visibility check and alpha restore without the direct hide hook loop

## v1.0.29
- Added a periodic mail visibility watchdog that re-shows the mail icon, restores alpha, and keeps checking after reload if another addon hides it

## v1.0.28
- Hardened the Blizzard mail icon so it re-evaluates on inbox updates and re-shows itself if another addon hides it while unread mail exists
- Added one-time mail visibility hooks so the mail frame keeps correcting itself without accumulating duplicate hooks

## v1.0.27
- Added a digital-clock safeguard that suppresses the circular minimap sundial icon (`GameTimeFrame`) whenever it appears
- Forces Prokin Minimap to use the Blizzard digital minimap clock path so the clock consistently stays in the desired style

## v1.0.26
- Added a Prokin minimap button with left-click role checks, right-click options access, tooltip role display, and saved edge positioning
- Added an in-game options window for minimap size, addon button visibility, server-time display, minimap border visibility, and load-announcement toggles
- Restyled and resized the options UI, slider, and Prokin minimap button to better match the surrounding addon buttons and keep all option text within the window border
- Changed raid role display from per-player lines to summarized Tank, Healers, and DPS counts in the tooltip and raid role-check output

## v1.0.25
- Replaced the battleground proxy click path with Blizzard's native battlefield button so protected queue actions and the battleground confirmation dialog keep working
- Stopped hiding the Blizzard battlefield button so its dismiss and queue controls stay visible when the battleground countdown prompt appears

## v1.0.24
- Fixed the battleground or PvP proxy button so queue actions like `Leave Queue` stay on Blizzard's secure battlefield button path
- Reanchored the hidden Blizzard battlefield button to the saved proxy position so its native queue menu opens from the same place without tainting `AcceptBattlefieldPort()`

## v1.0.23
- Fixed the battleground or PvP proxy button so both left-click and right-click open Blizzard's queue menu while queued or ready to enter
- Preserved the active battleground button behavior so left-click still opens the scoreframe and right-click still opens the leave menu

## v1.0.22
- Deferred minimap refresh work that resizes the minimap while combat lockdown is active
- Reapplies the pending square minimap layout automatically after combat ends to avoid `ADDON_ACTION_BLOCKED`

## v1.0.21
- Lowered the Blizzard minimap clock by 5 pixels on the bottom edge so the square border no longer cuts through it
- Added a delayed, colorized load announcement that stays visible after `/reload`
- Fixed the load announcement to read the addon version correctly from the Anniversary metadata API and updated the message text formatting

## v1.0.20
- Fixed the Tracking proxy on TBC Anniversary's modern Blizzard minimap by opening the generated tracking menu directly on the proxy owner region
- Preserved Tracking drag behavior while moving menu activation onto Blizzard's required mouse-down flow and handling the menu system's global mouse event correctly
- Added an opt-in `/pkm trackingdebug` diagnostic toggle and changed tracking debug logging to default off for public builds

## v1.0.19
- Fixed the tracking proxy to open Blizzard's TBC tracking dropdown through `MiniMapTrackingDropDown` and reanchor it after the menu appears
- Matched the tracking proxy art to Blizzard's native TBC dimensions and tightened the widget overlap again to remove the last visible border gap

## v1.0.18
- Increased the Blizzard widget border overlap so the minimap icons sit closer to the square border art
- Switched the tracking proxy to Blizzard's exact TBC `MiniMapTracking` dropdown call for more reliable tracking-menu opening

## v1.0.17
- Switched the Blizzard proxy buttons to mouse-up activation so the tracking proxy follows the TBC control flow more closely
- Added explicit widget border overlap to eliminate the remaining visible gap between the square minimap border and Blizzard widgets

## v1.0.16
- Removed the visible pixel gap so the Blizzard minimap widgets sit flush against the square minimap border
- Improved tracking button detection so the proxy targets the first Blizzard tracking control that actually exposes a menu handler on TBC Anniversary
- Split the zone-header spacing from widget edge spacing so the zone name and server time label keep their 4 pixel top offset independently

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
